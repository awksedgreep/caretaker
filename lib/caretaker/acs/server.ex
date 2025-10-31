defmodule Caretaker.ACS.Server do
  @moduledoc """
  Minimal ACS Plug router.

  Note: Library code does not start Bandit by default. Use child_spec in your app.
  """

  use Plug.Router
  require Logger

  plug(:match)
  plug(:dispatch)

  post "/cwmp" do
    start = System.monotonic_time()

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
          case Caretaker.ACS.Session.next_for_ip(conn.remote_ip || {127, 0, 0, 1}) do
            {:ok, cmd_body} ->
              _ = :telemetry.execute([:caretaker, :acs, :queue, :dequeue], %{}, %{rpc: :next})
              {:ok, envelope} = Caretaker.CWMP.SOAP.encode_envelope(cmd_body, %{})

              conn
              |> Plug.Conn.put_resp_header("content-type", Caretaker.CWMP.SOAP.content_type())
              |> Plug.Conn.send_resp(200, IO.iodata_to_binary(envelope))

            :empty ->
              conn
              |> Plug.Conn.put_resp_header("content-type", "text/plain")
              |> Plug.Conn.send_resp(204, "")
          end

        _ ->
          # Fast-path: handle GetParameterValuesResponse directly from raw XML
          case Regex.run(
                 ~r/<cwmp:GetParameterValuesResponse[\s\S]*?<\/cwmp:GetParameterValuesResponse>/,
                 body
               ) do
            [frag] ->
              ip = conn.remote_ip || {127, 0, 0, 1}

              case Caretaker.ACS.Session.device_key_for_ip(ip) do
                {oui, pc, sn} = dev_key ->
                  with {:ok, %{parameters: params}} <-
                         Caretaker.TR069.RPC.GetParameterValuesResponse.decode(frag),
                       :ok <-
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

                nil ->
                  conn
                  |> Plug.Conn.put_resp_header("content-type", "text/plain")
                  |> Plug.Conn.send_resp(400, "Bad Request")
              end

            _ ->
              # Attempt to parse Inform and respond with InformResponse
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
                       :ok <-
                         maybe_enqueue_gpv(conn.remote_ip || {127, 0, 0, 1}, inform.device_id, ns),
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
                   body: %{rpc: "GetParameterValuesResponse", xml: body_xml}
                 }} ->
                  # Map response into TR-181 store for this device; respond 204.
                  ip = conn.remote_ip || {127, 0, 0, 1}

                  case Caretaker.ACS.Session.device_key_for_ip(ip) do
                    {oui, pc, sn} = dev_key ->
                      with {:ok, %{parameters: params}} <-
                             Caretaker.TR069.RPC.GetParameterValuesResponse.decode(body_xml),
                           :ok <-
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

                    nil ->
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
      end

    duration = System.monotonic_time() - start

    :telemetry.execute([:caretaker, :acs, :request, :stop], %{duration: duration}, %{
      status: conn.status
    })

    conn
  end

  defp maybe_enqueue_gpv(ip, device_id, ns) do
    case Process.whereis(Caretaker.ACS.Session) do
      nil ->
        :ok

      _pid ->
        :ok = Caretaker.ACS.Session.upsert_from_ip(ip, device_id, ns)

        {:ok, gpv} =
          Caretaker.TR069.RPC.GetParameterValues.encode(
            Caretaker.TR069.RPC.GetParameterValues.new(["Device.DeviceInfo."])
          )

        _ =
          :telemetry.execute([:caretaker, :acs, :queue, :enqueue], %{}, %{
            rpc: :get_parameter_values
          })

        :ok = Caretaker.ACS.Session.queue_for_ip(ip, gpv)
        :ok
    end
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "Not Found")
  end

  @doc "Child spec to start Bandit with this router"
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    bandit_opts = [
      plug: __MODULE__,
      port: Keyword.get(opts, :port, 4000),
      scheme: Keyword.get(opts, :scheme, :http)
    ]

    {Bandit, bandit_opts}
  end
end
