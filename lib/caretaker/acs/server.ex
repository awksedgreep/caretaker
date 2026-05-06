defmodule Caretaker.ACS.Server do
  @moduledoc """
  Minimal ACS Plug router.

  Note: Library code does not start Bandit by default. Use child_spec in your app.
  """

  use Plug.Router
  require Logger

  @default_cwmp_ns "urn:dslforum-org:cwmp-1-0"

  plug(:match)
  plug(:dispatch)

  post "/cwmp" do
    start = System.monotonic_time()
    caller_key = caller_key(conn)

    :telemetry.execute([:caretaker, :acs, :request, :start], %{}, %{path: "/cwmp", method: "POST"})

    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Logger.info("ACS /cwmp bytes=#{byte_size(body)}")

    # Content-Type guard (allow missing or text/xml; otherwise 415)
    case Plug.Conn.get_req_header(conn, "content-type") do
      [] ->
        :ok

      [ct | _] ->
        if not String.starts_with?(ct, "text/xml") do
          duration = System.monotonic_time() - start

          conn =
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/plain")
            |> Plug.Conn.send_resp(415, "Unsupported Media Type")

          :telemetry.execute([:caretaker, :acs, :request, :stop], %{duration: duration}, %{
            status: conn.status
          })

          throw({:halt, conn})
        end
    end

    conn =
      case body do
        <<>> ->
          case Caretaker.ACS.Session.next_for_caller(caller_key) do
            {:ok, cmd_body} ->
              _ = :telemetry.execute([:caretaker, :acs, :queue, :dequeue], %{}, %{rpc: :next})

              ns =
                Caretaker.ACS.Session.cwmp_ns_for_caller(caller_key) || @default_cwmp_ns

              id = Base.encode16(:crypto.strong_rand_bytes(6), case: :upper)

              {:ok, envelope} =
                Caretaker.CWMP.SOAP.encode_envelope(cmd_body, %{id: id, cwmp_ns: ns})

              conn
              |> Plug.Conn.put_resp_header("content-type", Caretaker.CWMP.SOAP.content_type())
              |> Plug.Conn.send_resp(200, IO.iodata_to_binary(envelope))

            :empty ->
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")
          end

        _ ->
          # Parse SOAP envelope and dispatch by RPC using Lather-based decoders
          case Caretaker.CWMP.SOAP.decode_envelope(body) do
            {:ok, %{header: %{id: id, cwmp_ns: ns}, body: %{rpc: "Inform", xml: inform_xml}}} ->
              with {:ok, inform} <- Caretaker.TR069.RPC.Inform.decode(inform_xml),
                   :ok <-
                     Caretaker.PubSub.broadcast(Caretaker.PubSub.topic_tr069_inform(), inform),
                   _ <-
                     :telemetry.execute([:caretaker, :acs, :inform, :received], %{}, %{
                       device_id: inform.device_id
                     }),
                   # Upsert session and enqueue GPV if Session is running; otherwise no-op.
                   :ok <- maybe_enqueue_gpv(caller_key, inform.device_id, ns),
                   {:ok, resp_body} <-
                     Caretaker.TR069.RPC.InformResponse.encode(
                       %Caretaker.TR069.RPC.InformResponse{max_envelopes: 1}
                     ),
                   {:ok, envelope} <-
                     Caretaker.CWMP.SOAP.encode_envelope(resp_body, %{id: id, cwmp_ns: ns}) do
                conn
                |> Plug.Conn.put_resp_header(
                  "content-type",
                  Caretaker.CWMP.SOAP.content_type()
                )
                |> Plug.Conn.send_resp(200, IO.iodata_to_binary(envelope))
              else
                _ ->
                  conn
                  |> Plug.Conn.put_resp_header("content-type", "text/plain")
                  |> Plug.Conn.send_resp(400, "Bad Request")
              end

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "GetParameterValuesResponse", xml: body_xml, node: body_node}
             }} ->
              # Map response into TR-181 store for this device; respond 204.
              case Caretaker.ACS.Session.device_key_for_caller(caller_key) do
                {oui, pc, sn} = dev_key ->
                  params =
                    case Caretaker.TR069.RPC.GetParameterValuesResponse.decode(body_xml) do
                      {:ok, %{parameters: p}} -> p
                      _ -> extract_gpv_params_from_node(body_node)
                    end

                  case Process.whereis(Caretaker.TR181.Store) do
                    nil ->
                      conn
                      |> Plug.Conn.put_resp_header("content-type", "text/plain")
                      |> Plug.Conn.send_resp(204, "")

                    _pid ->
                      with :ok <-
                             Caretaker.TR181.Store.merge_params(
                               dev_key,
                               params,
                               Caretaker.TR181.Schema.default()
                             ) do
                        :telemetry.execute([:caretaker, :tr181, :store, :updated], %{}, %{
                          device: %{oui: oui, product_class: pc, serial: sn}
                        })

                        conn
                        |> Plug.Conn.put_resp_header("content-type", "text/plain")
                        |> Plug.Conn.send_resp(204, "")
                      else
                        _ ->
                          conn
                          |> Plug.Conn.put_resp_header("content-type", "text/plain")
                          |> Plug.Conn.send_resp(400, "Bad Request")
                      end
                  end

                nil ->
                  conn
                  |> Plug.Conn.put_resp_header("content-type", "text/plain")
                  |> Plug.Conn.send_resp(400, "Bad Request")
              end

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "GetParameterNamesResponse"}
             }} ->
              # Acknowledge receipt of GetParameterNamesResponse
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "GetRPCMethodsResponse"}
             }} ->
              # Acknowledge receipt of GetRPCMethodsResponse
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "SetParameterValuesResponse"}
             }} ->
              # Acknowledge receipt of SetParameterValuesResponse
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "GetParameterAttributesResponse"}
             }} ->
              # Acknowledge receipt of GetParameterAttributesResponse
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "SetParameterAttributesResponse"}
             }} ->
              # Acknowledge receipt of SetParameterAttributesResponse
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "AddObjectResponse"}
             }} ->
              # Acknowledge receipt of AddObjectResponse
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "DeleteObjectResponse"}
             }} ->
              # Acknowledge receipt of DeleteObjectResponse
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "DownloadResponse"}
             }} ->
              # Acknowledge receipt of DownloadResponse
              :telemetry.execute([:caretaker, :acs, :download, :response], %{}, %{})

              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: _id, cwmp_ns: _ns},
               body: %{rpc: "RebootResponse"}
             }} ->
              # Acknowledge receipt of RebootResponse
              :telemetry.execute([:caretaker, :acs, :reboot, :response], %{}, %{})

              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")

            {:ok,
             %{
               header: %{id: id, cwmp_ns: ns},
               body: %{rpc: "TransferComplete", xml: tc_xml}
             }} ->
              # Handle TransferComplete from CPE
              with {:ok, tc} <- Caretaker.TR069.RPC.TransferComplete.decode(tc_xml) do
                :telemetry.execute([:caretaker, :acs, :transfer_complete, :received], %{}, %{
                  command_key: tc.command_key,
                  fault_code: tc.fault_code
                })

                # Send TransferCompleteResponse
                {:ok, resp_body} =
                  Caretaker.TR069.RPC.TransferCompleteResponse.encode(
                    %Caretaker.TR069.RPC.TransferCompleteResponse{}
                  )

                {:ok, envelope} =
                  Caretaker.CWMP.SOAP.encode_envelope(resp_body, %{id: id, cwmp_ns: ns})

                conn
                |> Plug.Conn.put_resp_header("content-type", Caretaker.CWMP.SOAP.content_type())
                |> Plug.Conn.send_resp(200, IO.iodata_to_binary(envelope))
              else
                _ ->
                  conn
                  |> Plug.Conn.put_resp_header("content-type", "text/plain")
                  |> Plug.Conn.send_resp(400, "Bad Request")
              end

            _other ->
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(400, "Bad Request")
          end
      end

    duration = System.monotonic_time() - start

    :telemetry.execute([:caretaker, :acs, :request, :stop], %{duration: duration}, %{
      status: conn.status
    })

    conn
  end

  @spec maybe_enqueue_gpv(Caretaker.ACS.Session.caller_key(), map(), String.t()) :: :ok
  defp maybe_enqueue_gpv(caller_key, device_id, ns) do
    case Process.whereis(Caretaker.ACS.Session) do
      nil ->
        :ok

      _pid ->
        session_device_id = Map.take(device_id, [:oui, :product_class, :serial_number])
        :ok = Caretaker.ACS.Session.upsert_for_caller(caller_key, session_device_id, ns)

        {:ok, gpv} =
          Caretaker.TR069.RPC.GetParameterValues.encode(
            Caretaker.TR069.RPC.GetParameterValues.new(["Device.DeviceInfo."])
          )

        _ =
          :telemetry.execute([:caretaker, :acs, :queue, :enqueue], %{}, %{
            rpc: :get_parameter_values
          })

        :ok = Caretaker.ACS.Session.queue_for_caller(caller_key, gpv)
        :ok
    end
  end

  defp caller_key(conn) do
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

    Enum.map(items, fn item ->
      name = item["Name"] || ""

      val =
        case item["Value"] do
          %{"#text" => v} -> v
          v when is_binary(v) -> v
          _ -> ""
        end

      typ =
        case item["Value"] do
          %{"@xsi:type" => t} -> t
          _ -> ""
        end

      %{name: name, value: val, type: typ}
    end)
  end

  defp extract_gpv_params_from_node(_), do: []

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
end
