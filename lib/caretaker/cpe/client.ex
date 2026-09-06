defmodule Caretaker.CPE.Client do
  @moduledoc """
  Minimal CPE HTTP client for running a TR-069 session:
  - Sends Inform (with the forced Inform parameters when a DeviceState is given)
  - Awaits InformResponse
  - Sends an empty POST, then answers every RPC the ACS returns until the ACS
    replies 204 (end of session)
  - Echoes session cookies and answers Basic/Digest authentication challenges
  - Supports firmware upgrade simulation via FirmwareSimulator

  This module uses Finch for HTTP. Applications should run
  `{Finch, name: Caretaker.Finch}` in their supervision tree; otherwise a
  detached pool is started on first use (see `Caretaker.HTTP`).
  """
  alias Caretaker.CWMP.SOAP
  alias Caretaker.HTTP
  alias Caretaker.TR069.RPC.Inform
  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.FirmwareSimulator

  @default_timeout 5_000
  @default_backoff 200
  @default_max_retries 3
  @default_cwmp_ns "urn:dslforum-org:cwmp-1-0"
  @user_agent "CaretakerCPE/" <> Mix.Project.config()[:version]

  # Parameters TR-069 requires in every Inform (when the device has them).
  @forced_inform_params [
    "Device.DeviceInfo.HardwareVersion",
    "Device.DeviceInfo.SoftwareVersion",
    "Device.DeviceInfo.ProvisioningCode",
    "Device.ManagementServer.ParameterKey",
    "Device.ManagementServer.ConnectionRequestURL",
    "Device.ManagementServer.AliasBasedAddressing"
  ]

  @type device_id :: %{
          manufacturer: String.t(),
          oui: String.t(),
          product_class: String.t(),
          serial_number: String.t()
        }

  @type session_result ::
          {:ok,
           %{
             cwmp_id: String.t(),
             cwmp_ns: String.t(),
             inform_ack: boolean(),
             rpc: String.t() | nil,
             rpc_xml: String.t() | nil
           }}
          | {:error, term()}

  @doc """
  Run a TR-069 session against an ACS URL.

  Steps:
    1) POST Inform and verify InformResponse
    2) POST an empty body; answer each RPC the ACS returns, and end when the
       ACS answers with 204

  Returns the last RPC handled (if any) with metadata.

  Options:
    - `device_id` - Device identification map (required if no device_state)
    - `device_state` - DeviceState agent (optional, enables stateful responses)
    - `timeout`, `max_retries`, `backoff_base` - HTTP settings
    - `events` - Event codes for Inform (default: ["1 BOOT"])
    - `parameter_list` - Inform ParameterList entries (`%{name, value, type}`);
      defaults to the forced Inform parameters read from `device_state`
    - `cwmp_ns` - CWMP namespace
    - `username`, `password` - Credentials for Basic/Digest challenges
  """
  @spec run_session(String.t(), keyword()) :: session_result()
  def run_session(acs_url, opts \\ []) when is_binary(acs_url) do
    :telemetry.execute([:caretaker, :cpe_client, :session, :start], %{}, %{acs_url: acs_url})

    device_state = Keyword.get(opts, :device_state)

    device_id =
      Keyword.get(opts, :device_id, %{
        manufacturer: "Acme",
        oui: "A1B2C3",
        product_class: "Router",
        serial_number: "XYZ123"
      })

    ctx = %{
      acs_url: acs_url,
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      backoff_base: Keyword.get(opts, :backoff_base, @default_backoff),
      device_id: device_id,
      device_state: device_state,
      cwmp_ns: Keyword.get(opts, :cwmp_ns, @default_cwmp_ns),
      credentials: credentials(opts),
      cookies: %{},
      authorization: nil
    }

    inform =
      Inform.new(
        device_id: device_id,
        events: Keyword.get(opts, :events, ["1 BOOT"]),
        max_envelopes: 1,
        retry_count: Keyword.get(opts, :retry_count, 0),
        parameter_list: Keyword.get_lazy(opts, :parameter_list, fn -> inform_params(device_state) end)
      )

    cwmp_id = gen_id()

    with {:ok, inform_body} <- Inform.encode(inform),
         {:ok, inform_env} <-
           SOAP.encode_envelope(inform_body, %{id: cwmp_id, cwmp_ns: ctx.cwmp_ns}),
         :ok <- HTTP.ensure_finch(),
         {:ok, ack, ctx} <- http_retry(ctx, &http_post_xml(&1, inform_env)),
         {:ok, ctx} <- expect_inform_response(ack, ctx),
         {:ok, last_rpc} <- session_loop(ctx) do
      :telemetry.execute([:caretaker, :cpe_client, :session, :stop], %{}, %{
        acs_url: acs_url,
        cwmp_id: cwmp_id,
        cwmp_ns: ctx.cwmp_ns,
        rpc: last_rpc
      })

      {:ok,
       %{cwmp_id: cwmp_id, cwmp_ns: ctx.cwmp_ns, inform_ack: true, rpc: last_rpc, rpc_xml: nil}}
    else
      {:error, reason} = err ->
        :telemetry.execute([:caretaker, :cpe_client, :error], %{}, %{
          acs_url: acs_url,
          cwmp_id: cwmp_id,
          reason: reason
        })

        err
    end
  end

  # -- Inform helpers --

  defp credentials(opts) do
    case {Keyword.get(opts, :username), Keyword.get(opts, :password)} do
      {nil, _} -> nil
      {user, pass} -> %{username: user, password: pass || ""}
    end
  end

  defp inform_params(nil), do: []

  defp inform_params(device_state) do
    Enum.flat_map(@forced_inform_params, fn path ->
      case DeviceState.get_parameters(device_state, path) do
        [param | _] -> [param]
        _ -> []
      end
    end)
  end

  defp expect_inform_response(%{status: 200, body: ack_xml}, ctx) do
    case SOAP.decode_envelope(ack_xml) do
      {:ok, %{header: %{cwmp_ns: ns}, body: %{rpc: "InformResponse"}}} ->
        {:ok, %{ctx | cwmp_ns: ns}}

      {:ok, %{body: %{rpc: "Fault", xml: xml}}} ->
        {:error, {:fault, decode_fault(xml)}}

      {:ok, %{body: %{rpc: other}}} ->
        {:error, {:unexpected_rpc, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp expect_inform_response(%{status: status}, _ctx), do: {:error, {:http, status}}

  defp decode_fault(nil), do: %{code: "", string: ""}

  defp decode_fault(xml) do
    case Caretaker.TR069.RPC.Fault.decode(xml) do
      {:ok, %{code: code, string: string}} -> %{code: code, string: string}
      _ -> %{code: "", string: ""}
    end
  end

  # -- Session loop --
  #
  # The CPE has nothing more to send after Inform, so it POSTs an empty body.
  # The ACS answers either with an RPC (which we respond to, and the ACS
  # answers that response with the next RPC or 204) or with 204, ending the
  # session.

  defp session_loop(ctx) do
    case http_retry(ctx, &http_post_empty/1) do
      {:ok, reply, ctx} -> handle_acs_reply(reply, ctx, nil)
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_acs_reply(%{status: 204}, _ctx, last_rpc), do: {:ok, last_rpc}

  defp handle_acs_reply(%{status: 200, body: body}, ctx, last_rpc) do
    case SOAP.decode_envelope(body) do
      {:ok, %{header: %{id: id, cwmp_ns: ns}, body: %{rpc: rpc_name, xml: body_xml}}}
      when is_binary(rpc_name) ->
        ctx = %{ctx | cwmp_ns: ns}

        :telemetry.execute([:caretaker, :cpe_client, :rpc, :received], %{}, %{
          acs_url: ctx.acs_url,
          cwmp_ns: ctx.cwmp_ns,
          rpc: rpc_name
        })

        case respond_to_rpc(ctx, rpc_name, body_xml, id) do
          {:ok, next_reply, ctx} -> handle_acs_reply(next_reply, ctx, rpc_name)
          {:end_session, _reply, _ctx} -> {:ok, rpc_name}
          {:error, reason} -> {:error, reason}
        end

      {:ok, _} ->
        # A 200 with no RPC element is treated as end of session
        {:ok, last_rpc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_acs_reply(%{status: status}, _ctx, _last_rpc), do: {:error, {:http, status}}

  # -- RPC handlers --
  #
  # Each handler builds a response body and returns
  # {:ok, next_acs_reply, ctx} | {:end_session, reply, ctx} | {:error, reason}

  defp respond_to_rpc(ctx, "GetParameterValues", rpc_xml, id) do
    requested_paths = parse_parameter_names(rpc_xml)

    params =
      case ctx.device_state do
        nil ->
          [
            %{
              name: "Device.DeviceInfo.Manufacturer",
              value: ctx.device_id.manufacturer,
              type: "xsd:string"
            },
            %{
              name: "Device.DeviceInfo.SerialNumber",
              value: ctx.device_id.serial_number,
              type: "xsd:string"
            }
          ]

        state ->
          Enum.flat_map(requested_paths, &DeviceState.get_parameters(state, &1))
      end

    with {:ok, body} <- Caretaker.TR069.RPC.GetParameterValuesResponse.encode(%{parameters: params}) do
      send_response(ctx, body, id, %{rpc: "GetParameterValues", param_count: length(params)})
    end
  end

  defp respond_to_rpc(ctx, "SetParameterValues", rpc_xml, id) do
    params_to_set = parse_parameter_values(rpc_xml)

    if ctx.device_state && params_to_set != [] do
      DeviceState.update_parameters(ctx.device_state, params_to_set)

      :telemetry.execute([:caretaker, :cpe_client, :params, :updated], %{}, %{
        count: length(params_to_set)
      })
    end

    with {:ok, body} <- Caretaker.TR069.RPC.SetParameterValuesResponse.encode(%{status: 0}) do
      send_response(ctx, body, id, %{rpc: "SetParameterValues"})
    end
  end

  defp respond_to_rpc(ctx, "GetParameterNames", rpc_xml, id) do
    {path, next_level} =
      case Caretaker.TR069.RPC.GetParameterNames.decode(rpc_xml) do
        {:ok, %{parameter_path: p, next_level: nl}} -> {p, nl}
        _ -> {"Device.", false}
      end

    params =
      case ctx.device_state do
        nil -> [%{name: "Device.DeviceInfo.", writable: false}]
        state -> DeviceState.get_parameter_names(state, path, next_level)
      end

    with {:ok, body} <- Caretaker.TR069.RPC.GetParameterNamesResponse.encode(%{parameters: params}) do
      send_response(ctx, body, id, %{
        rpc: "GetParameterNames",
        param_count: length(params),
        next_level: next_level
      })
    end
  end

  defp respond_to_rpc(ctx, "GetRPCMethods", _rpc_xml, id) do
    methods = [
      "GetRPCMethods",
      "GetParameterValues",
      "GetParameterNames",
      "GetParameterAttributes",
      "SetParameterValues",
      "SetParameterAttributes",
      "AddObject",
      "DeleteObject",
      "Download",
      "Reboot",
      "Inform"
    ]

    response = %Caretaker.TR069.RPC.GetRPCMethodsResponse{methods: methods}

    with {:ok, body} <- Caretaker.TR069.RPC.GetRPCMethodsResponse.encode(response) do
      send_response(ctx, body, id, %{rpc: "GetRPCMethods", method_count: length(methods)})
    end
  end

  defp respond_to_rpc(ctx, "GetParameterAttributes", rpc_xml, id) do
    paths =
      case Caretaker.TR069.RPC.GetParameterAttributes.decode(rpc_xml) do
        {:ok, %{names: names}} -> names
        _ -> []
      end

    params =
      case ctx.device_state do
        nil -> Enum.map(paths, &%{name: &1, notification: 0, access_list: ["Subscriber"]})
        state -> DeviceState.get_parameter_attributes(state, paths)
      end

    with {:ok, body} <-
           Caretaker.TR069.RPC.GetParameterAttributesResponse.encode(%{parameters: params}) do
      send_response(ctx, body, id, %{rpc: "GetParameterAttributes", param_count: length(params)})
    end
  end

  defp respond_to_rpc(ctx, "SetParameterAttributes", rpc_xml, id) do
    attrs =
      case Caretaker.TR069.RPC.SetParameterAttributes.decode(rpc_xml) do
        {:ok, %{parameters: params}} -> params
        _ -> []
      end

    if ctx.device_state && attrs != [] do
      DeviceState.set_parameter_attributes(ctx.device_state, attrs)
      :telemetry.execute([:caretaker, :cpe_client, :attrs, :updated], %{}, %{count: length(attrs)})
    end

    response = %Caretaker.TR069.RPC.SetParameterAttributesResponse{}

    with {:ok, body} <- Caretaker.TR069.RPC.SetParameterAttributesResponse.encode(response) do
      send_response(ctx, body, id, %{rpc: "SetParameterAttributes"})
    end
  end

  defp respond_to_rpc(ctx, "AddObject", rpc_xml, id) do
    object_path =
      case Caretaker.TR069.RPC.AddObject.decode(rpc_xml) do
        {:ok, %{object_name: name}} -> name
        _ -> ""
      end

    instance_number =
      case ctx.device_state do
        nil ->
          1

        state ->
          {:ok, inst} = DeviceState.add_object_instance(state, object_path)
          inst
      end

    with {:ok, body} <-
           Caretaker.TR069.RPC.AddObjectResponse.encode(%{
             instance_number: instance_number,
             status: 0
           }) do
      send_response(ctx, body, id, %{
        rpc: "AddObject",
        object_path: object_path,
        instance_number: instance_number
      })
    end
  end

  defp respond_to_rpc(ctx, "DeleteObject", rpc_xml, id) do
    object_path =
      case Caretaker.TR069.RPC.DeleteObject.decode(rpc_xml) do
        {:ok, %{object_name: name}} -> name
        _ -> ""
      end

    status =
      case ctx.device_state do
        nil ->
          0

        state ->
          case DeviceState.delete_object_instance(state, object_path) do
            :ok -> 0
            {:error, :not_found} -> 1
          end
      end

    with {:ok, body} <- Caretaker.TR069.RPC.DeleteObjectResponse.encode(%{status: status}) do
      send_response(ctx, body, id, %{rpc: "DeleteObject", object_path: object_path})
    end
  end

  defp respond_to_rpc(ctx, "Download", rpc_xml, id) do
    download =
      case Caretaker.TR069.RPC.Download.decode(rpc_xml) do
        {:ok, d} -> d
        _ -> %{command_key: "", file_type: "", url: "", delay_seconds: 0}
      end

    {status, start_time, complete_time} =
      case get_firmware_simulator(ctx.device_state) do
        nil ->
          now = DateTime.to_iso8601(DateTime.utc_now())
          {0, now, now}

        sim ->
          case FirmwareSimulator.start_download(sim, %{
                 url: download.url,
                 command_key: download.command_key,
                 file_type: download.file_type
               }) do
            {:ok, :downloading} ->
              # Download will complete asynchronously; TransferComplete follows later
              {1, "0001-01-01T00:00:00Z", "0001-01-01T00:00:00Z"}

            {:error, _reason} ->
              now = DateTime.to_iso8601(DateTime.utc_now())
              {9001, now, now}
          end
      end

    response =
      Caretaker.TR069.RPC.DownloadResponse.new(
        status: status,
        start_time: start_time,
        complete_time: complete_time
      )

    with {:ok, body} <- Caretaker.TR069.RPC.DownloadResponse.encode(response) do
      send_response(ctx, body, id, %{
        rpc: "Download",
        command_key: download.command_key,
        status: status
      })
    end
  end

  defp respond_to_rpc(ctx, "Reboot", _rpc_xml, id) do
    case get_firmware_simulator(ctx.device_state) do
      nil -> :ok
      sim -> FirmwareSimulator.start_reboot(sim)
    end

    response = Caretaker.TR069.RPC.RebootResponse.new()

    with {:ok, body} <- Caretaker.TR069.RPC.RebootResponse.encode(response),
         {:ok, reply, ctx} <- send_response(ctx, body, id, %{rpc: "Reboot"}) do
      # The device is "rebooting": end the session regardless of what follows
      {:end_session, reply, ctx}
    end
  end

  defp respond_to_rpc(ctx, rpc, _rpc_xml, id) when is_binary(rpc) do
    :telemetry.execute([:caretaker, :cpe_client, :rpc, :unsupported], %{}, %{rpc: rpc})

    fault = Caretaker.TR069.RPC.Fault.new(8000, "Method not supported")

    with {:ok, body} <- Caretaker.TR069.RPC.Fault.encode(fault) do
      send_response(ctx, body, id, %{rpc: rpc, fault: 8000})
    end
  end

  # Wrap the body in an envelope, POST it, and return the ACS's reply.
  defp send_response(ctx, body, id, meta) do
    with {:ok, env} <- SOAP.encode_envelope(body, %{cwmp_ns: ctx.cwmp_ns, id: id}),
         {:ok, reply, ctx} <- http_retry(ctx, &http_post_xml(&1, env)) do
      :telemetry.execute(
        [:caretaker, :cpe_client, :rpc, :responded],
        %{},
        Map.merge(%{acs_url: ctx.acs_url, cwmp_ns: ctx.cwmp_ns}, meta)
      )

      {:ok, reply, ctx}
    end
  end

  defp get_firmware_simulator(device_state) when is_pid(device_state) do
    case DeviceState.get_option(device_state, :firmware_simulator) do
      {:ok, sim} -> sim
      _ -> nil
    end
  end

  defp get_firmware_simulator(_), do: nil

  # -- RPC parsing helpers --

  # Falls back to "Device.DeviceInfo." when the request carries no names.
  defp parse_parameter_names(xml) do
    case Caretaker.TR069.RPC.GetParameterValues.decode(xml) do
      {:ok, %{names: [_ | _] = names}} -> names
      _ -> ["Device.DeviceInfo."]
    end
  end

  # Extracts name, value, and type from SetParameterValues ParameterValueStruct elements
  defp parse_parameter_values(xml) do
    case parse_rpc_fragment(xml) do
      {:ok, parsed} ->
        # The parsed fragment nests ParameterList under the RPC element.
        node = parsed["cwmp:SetParameterValues"] || parsed["SetParameterValues"] || parsed

        node
        |> get_in(["ParameterList", "ParameterValueStruct"])
        |> List.wrap()
        |> Enum.map(fn struct ->
          param = Caretaker.TR069.RPC.GetParameterValuesResponse.parameter_value_struct(struct)
          %{param | type: if(param.type == "", do: "xsd:string", else: param.type)}
        end)

      {:error, _} ->
        []
    end
  end

  defp parse_rpc_fragment(xml) when is_binary(xml) do
    wrapped = [
      "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\"",
      " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"",
      " xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">",
      xml,
      "</root>"
    ]

    with {:ok, parsed} <- Lather.Xml.Parser.parse(IO.iodata_to_binary(wrapped)) do
      {:ok, parsed["root"] || %{}}
    end
  end

  # -- HTTP helpers --
  #
  # Every request returns {:ok, %{status, body}, ctx} so that cookies and
  # authorization learned from the response are carried into the next request.

  defp http_post_xml(ctx, body) do
    headers = [
      {"content-type", SOAP.content_type()},
      {"soapaction", ""},
      {"accept", "text/xml"}
    ]

    http_post(ctx, headers, IO.iodata_to_binary(body))
  end

  defp http_post_empty(ctx) do
    http_post(ctx, [{"accept", "text/xml"}], "")
  end

  defp http_post(ctx, headers, body, retried_auth? \\ false) do
    headers = [{"user-agent", @user_agent} | headers] ++ cookie_headers(ctx) ++ auth_headers(ctx)
    req = Finch.build(:post, ctx.acs_url, headers, body)

    :telemetry.execute([:caretaker, :cpe_client, :http, :request, :start], %{}, %{
      method: :post,
      url: ctx.acs_url
    })

    case Finch.request(req, HTTP.finch(), receive_timeout: ctx.timeout) do
      {:ok, %Finch.Response{status: status, body: resp_body, headers: resp_headers}} ->
        :telemetry.execute([:caretaker, :cpe_client, :http, :request, :stop], %{}, %{
          method: :post,
          url: ctx.acs_url,
          status: status
        })

        ctx = store_cookies(ctx, resp_headers)

        case {status, ctx.credentials, retried_auth?} do
          {401, %{} = creds, false} ->
            case authorization_for(resp_headers, creds, ctx.acs_url) do
              nil -> {:ok, %{status: status, body: resp_body}, ctx}
              auth -> http_post(%{ctx | authorization: auth}, headers_without_auth(headers), body, true)
            end

          _ ->
            {:ok, %{status: status, body: resp_body}, ctx}
        end

      {:error, reason} ->
        :telemetry.execute([:caretaker, :cpe_client, :http, :request, :stop], %{}, %{
          method: :post,
          url: ctx.acs_url,
          error: reason
        })

        {:error, reason}
    end
  end

  defp headers_without_auth(headers) do
    Enum.reject(headers, fn {k, _} -> k in ["authorization", "cookie", "user-agent"] end)
  end

  defp cookie_headers(%{cookies: cookies}) when map_size(cookies) == 0, do: []

  defp cookie_headers(%{cookies: cookies}) do
    [{"cookie", Enum.map_join(cookies, "; ", fn {k, v} -> k <> "=" <> v end)}]
  end

  defp auth_headers(%{authorization: nil}), do: []
  defp auth_headers(%{authorization: auth}), do: [{"authorization", auth}]

  defp store_cookies(ctx, resp_headers) do
    cookies =
      resp_headers
      |> Enum.filter(fn {k, _} -> String.downcase(k) == "set-cookie" end)
      |> Enum.reduce(ctx.cookies, fn {_, v}, acc ->
        case v |> String.split(";", parts: 2) |> hd() |> String.split("=", parts: 2) do
          [name, value] -> Map.put(acc, String.trim(name), String.trim(value))
          _ -> acc
        end
      end)

    %{ctx | cookies: cookies}
  end

  defp authorization_for(resp_headers, creds, url) do
    challenge =
      Enum.find_value(resp_headers, fn {k, v} ->
        if String.downcase(k) == "www-authenticate", do: v
      end)

    case challenge do
      nil -> nil
      value -> Caretaker.HTTP.Auth.authorization(value, creds, :post, URI.parse(url).path || "/")
    end
  end

  # -- Retry helpers --

  defp http_retry(ctx, fun, attempt \\ 0) when is_function(fun, 1) do
    case fun.(ctx) do
      {:ok, %{status: status}, _ctx} = ok when status in 200..299 ->
        ok

      {:ok, %{status: status}, ctx} when status == 408 or status >= 500 ->
        if attempt < ctx.max_retries do
          backoff(ctx, attempt)
          http_retry(ctx, fun, attempt + 1)
        else
          {:error, {:http, :max_retries_exceeded, status}}
        end

      {:ok, %{status: status}, _ctx} ->
        {:error, {:http, status}}

      {:error, reason} ->
        if attempt < ctx.max_retries do
          backoff(ctx, attempt)
          http_retry(ctx, fun, attempt + 1)
        else
          {:error, reason}
        end
    end
  end

  defp backoff(ctx, attempt) do
    base = trunc(:math.pow(2, attempt) * ctx.backoff_base)
    jitter = if base > 0, do: :rand.uniform(base), else: 0

    :telemetry.execute([:caretaker, :cpe_client, :retry], %{}, %{
      attempt: attempt + 1,
      backoff_ms: jitter
    })

    Process.sleep(jitter)
  end

  defp gen_id do
    Base.encode16(:crypto.strong_rand_bytes(6), case: :upper)
  end
end
