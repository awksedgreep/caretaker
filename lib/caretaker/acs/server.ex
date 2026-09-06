defmodule Caretaker.ACS.Server do
  @moduledoc """
  Minimal ACS Plug router.

  Session flow (TR-069 §3.7):
  - Inform -> InformResponse (the device is detected and bound to the caller)
  - Any CPE RPC response, Fault, or empty POST -> the next queued RPC, or 204
    when the queue is empty (which ends the session)

  Callers are correlated by a `caretaker_sid` session cookie set on the
  InformResponse; CPEs that do not return cookies fall back to their peer
  address and port.

  Note: Library code does not start Bandit by default. Use child_spec in your app.
  """

  use Plug.Router
  require Logger

  alias Caretaker.ACS.{DeviceDetection, Session}
  alias Caretaker.CWMP.SOAP

  @default_cwmp_ns "urn:dslforum-org:cwmp-1-0"
  @session_cookie "caretaker_sid"

  plug(:match)
  plug(:dispatch)

  post "/cwmp" do
    start = System.monotonic_time()
    conn = Plug.Conn.fetch_cookies(conn)
    caller_key = caller_key(conn)

    :telemetry.execute([:caretaker, :acs, :request, :start], %{}, %{path: "/cwmp", method: "POST"})

    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Logger.info("ACS /cwmp bytes=#{byte_size(body)}")

    conn =
      cond do
        not acceptable_content_type?(conn) ->
          text(conn, 415, "Unsupported Media Type")

        body == <<>> ->
          next_or_204(conn, caller_key)

        true ->
          handle_envelope(conn, caller_key, body)
      end

    duration = System.monotonic_time() - start

    :telemetry.execute([:caretaker, :acs, :request, :stop], %{duration: duration}, %{
      status: conn.status
    })

    conn
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "Not Found")
  end

  @doc "Child spec to start Bandit with this router"
  @spec child_spec(keyword()) :: {Bandit, keyword()}
  def child_spec(opts \\ []) do
    bandit_opts = [
      plug: __MODULE__,
      port: Keyword.get(opts, :port, 4000),
      scheme: Keyword.get(opts, :scheme, :http)
    ]

    {Bandit, bandit_opts}
  end

  # -- Envelope dispatch --

  defp handle_envelope(conn, caller_key, body) do
    case SOAP.decode_envelope(body) do
      {:ok, %{header: %{id: id, cwmp_ns: ns}, body: %{rpc: "Inform", xml: inform_xml}}} ->
        handle_inform(conn, caller_key, id, ns, inform_xml)

      {:ok, %{header: %{id: id, cwmp_ns: ns}, body: %{rpc: "TransferComplete", xml: tc_xml}}} ->
        handle_transfer_complete(conn, id, ns, tc_xml)

      {:ok, %{body: %{rpc: "GetParameterValuesResponse", xml: body_xml, node: node}}} ->
        handle_gpv_response(conn, caller_key, body_xml, node)

      {:ok, %{body: %{rpc: "Fault", xml: fault_xml}}} ->
        handle_fault(conn, caller_key, fault_xml)

      {:ok, %{body: %{rpc: rpc}}} when is_binary(rpc) ->
        if String.ends_with?(rpc, "Response") do
          acknowledge_response(conn, caller_key, rpc)
        else
          text(conn, 400, "Bad Request")
        end

      _other ->
        text(conn, 400, "Bad Request")
    end
  end

  defp handle_inform(conn, caller_key, id, ns, inform_xml) do
    with {:ok, inform} <- Caretaker.TR069.RPC.Inform.decode(inform_xml),
         :ok <- Caretaker.PubSub.broadcast(Caretaker.PubSub.topic_tr069_inform(), inform),
         _ <-
           :telemetry.execute([:caretaker, :acs, :inform, :received], %{}, %{
             device_id: inform.device_id
           }),
         {:ok, conn} <- bind_session(conn, caller_key, inform, ns),
         {:ok, resp_body} <-
           Caretaker.TR069.RPC.InformResponse.encode(
             %Caretaker.TR069.RPC.InformResponse{max_envelopes: 1}
           ),
         {:ok, envelope} <- SOAP.encode_envelope(resp_body, %{id: id, cwmp_ns: ns}) do
      xml(conn, 200, envelope)
    else
      _ -> text(conn, 400, "Bad Request")
    end
  end

  defp handle_transfer_complete(conn, id, ns, tc_xml) do
    case Caretaker.TR069.RPC.TransferComplete.decode(tc_xml) do
      {:ok, tc} ->
        :telemetry.execute([:caretaker, :acs, :transfer_complete, :received], %{}, %{
          command_key: tc.command_key,
          fault_code: tc.fault_code
        })

        {:ok, resp_body} =
          Caretaker.TR069.RPC.TransferCompleteResponse.encode(
            %Caretaker.TR069.RPC.TransferCompleteResponse{}
          )

        {:ok, envelope} = SOAP.encode_envelope(resp_body, %{id: id, cwmp_ns: ns})
        xml(conn, 200, envelope)

      _ ->
        text(conn, 400, "Bad Request")
    end
  end

  defp handle_gpv_response(conn, caller_key, body_xml, node) do
    dev_key = session_running?() && Session.device_key_for_caller(caller_key)

    case dev_key do
      {oui, pc, sn} ->
        params =
          case Caretaker.TR069.RPC.GetParameterValuesResponse.decode(body_xml) do
            {:ok, %{parameters: p}} -> p
            _ -> extract_gpv_params_from_node(node)
          end

        case Process.whereis(Caretaker.TR181.Store) do
          nil ->
            next_or_204(conn, caller_key)

          _pid ->
            case Caretaker.TR181.Store.merge_params(
                   dev_key,
                   params,
                   Caretaker.TR181.Schema.default()
                 ) do
              :ok ->
                :telemetry.execute([:caretaker, :tr181, :store, :updated], %{}, %{
                  device: %{oui: oui, product_class: pc, serial: sn}
                })

                next_or_204(conn, caller_key)

              {:error, errs} ->
                Logger.warning("ACS GPV response rejected by schema: #{inspect(errs)}")
                text(conn, 400, "Bad Request")
            end
        end

      _ ->
        # No session bound to this caller: nothing to store, nothing queued
        if session_running?(), do: text(conn, 400, "Bad Request"), else: text(conn, 204, "")
    end
  end

  defp handle_fault(conn, caller_key, fault_xml) do
    {code, string} =
      case fault_xml && Caretaker.TR069.RPC.Fault.decode(fault_xml) do
        {:ok, %{code: c, string: s}} -> {c, s}
        _ -> {"", ""}
      end

    Logger.warning("ACS received CWMP fault #{code} #{string}")

    :telemetry.execute([:caretaker, :acs, :fault, :received], %{}, %{
      fault_code: code,
      fault_string: string
    })

    next_or_204(conn, caller_key)
  end

  defp acknowledge_response(conn, caller_key, rpc) do
    case rpc do
      "DownloadResponse" -> :telemetry.execute([:caretaker, :acs, :download, :response], %{}, %{})
      "RebootResponse" -> :telemetry.execute([:caretaker, :acs, :reboot, :response], %{}, %{})
      _ -> :ok
    end

    next_or_204(conn, caller_key)
  end

  # -- Session helpers --

  defp session_running?, do: Process.whereis(Session) != nil

  # Upsert the session, queue the initial GPV and bind a session cookie.
  # A no-op when Session is not running.
  defp bind_session(conn, caller_key, inform, ns) do
    if session_running?() do
      device_id = Map.take(inform.device_id, [:oui, :product_class, :serial_number])
      detected = DeviceDetection.detect(inform)

      context = %{
        device_type: detected.type,
        quirks_module: Caretaker.Quirks.get_quirks(detected.oui),
        detected_at: DateTime.utc_now()
      }

      :ok = Session.upsert_for_caller_with_context(caller_key, device_id, ns, context)

      {:ok, gpv} =
        Caretaker.TR069.RPC.GetParameterValues.encode(
          Caretaker.TR069.RPC.GetParameterValues.new(["Device.DeviceInfo."])
        )

      :telemetry.execute([:caretaker, :acs, :queue, :enqueue], %{}, %{
        rpc: :get_parameter_values
      })

      :ok = Session.queue_for_caller(caller_key, gpv)

      sid = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      :ok = Session.bind_alias(caller_key, {:cookie, sid})

      {:ok, Plug.Conn.put_resp_cookie(conn, @session_cookie, sid, http_only: true)}
    else
      {:ok, conn}
    end
  end

  # Reply with the next queued RPC for this caller, or 204 when there is none.
  defp next_or_204(conn, caller_key) do
    next =
      if session_running?() do
        Session.next_for_caller(caller_key)
      else
        :empty
      end

    case next do
      {:ok, cmd_body} ->
        :telemetry.execute([:caretaker, :acs, :queue, :dequeue], %{}, %{rpc: :next})

        ns = Session.cwmp_ns_for_caller(caller_key) || @default_cwmp_ns
        id = Base.encode16(:crypto.strong_rand_bytes(6), case: :upper)
        {:ok, envelope} = SOAP.encode_envelope(cmd_body, %{id: id, cwmp_ns: ns})
        xml(conn, 200, envelope)

      :empty ->
        text(conn, 204, "")
    end
  end

  # -- Request helpers --

  defp acceptable_content_type?(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [] -> true
      [ct | _] -> ct |> String.downcase() |> String.starts_with?("text/xml")
    end
  end

  defp caller_key(conn) do
    case conn.cookies do
      %{@session_cookie => sid} when is_binary(sid) and sid != "" -> {:cookie, sid}
      _ -> peer_key(conn)
    end
  end

  defp peer_key(conn) do
    peer_data = Plug.Conn.get_peer_data(conn)

    if use_test_remote_ip_fallback?(conn, peer_data) do
      {:ip, conn.remote_ip}
    else
      {:peer, peer_data.address, peer_data.port}
    end
  rescue
    KeyError -> {:ip, conn.remote_ip}
  end

  defp use_test_remote_ip_fallback?(%Plug.Conn{adapter: {Plug.Adapters.Test.Conn, _}}, peer_data) do
    peer_data == %{address: {127, 0, 0, 1}, port: 111_317, ssl_cert: nil}
  end

  defp use_test_remote_ip_fallback?(_conn, _peer_data), do: false

  defp extract_gpv_params_from_node(%{} = node) do
    plist = node["ParameterList"] || %{}
    items = plist["ParameterValueStruct"] |> List.wrap()
    Enum.map(items, &Caretaker.TR069.RPC.GetParameterValuesResponse.parameter_value_struct/1)
  end

  defp extract_gpv_params_from_node(_), do: []

  # -- Response helpers --

  defp text(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "text/plain")
    |> Plug.Conn.send_resp(status, body)
  end

  defp xml(conn, status, envelope) do
    conn
    |> Plug.Conn.put_resp_header("content-type", SOAP.content_type())
    |> Plug.Conn.send_resp(status, IO.iodata_to_binary(envelope))
  end
end
