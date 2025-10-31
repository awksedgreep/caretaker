defmodule Caretaker.CPE.Client do
  @moduledoc """
  Minimal CPE HTTP client for initiating a TR-069 session:
  - Sends Inform to the ACS
  - Awaits InformResponse
  - Sends an empty POST to fetch the next queued RPC (e.g., GetParameterValues)

  This module uses Finch for HTTP. Ensure a Finch supervisor is running:
    {Finch, name: Caretaker.Finch}
  """

  require Logger
  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.Inform

  @default_timeout 5_000
  @default_backoff 200
  @default_max_retries 3
  @default_cwmp_ns "urn:dslforum-org:cwmp-1-0"

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
  Run a one-shot TR-069 session against an ACS URL.
  Steps:
    1) POST Inform and verify InformResponse
    2) POST empty body to fetch queued RPC
  Returns the received RPC (if any) with metadata.
  """
  @spec run_session(String.t(), keyword()) :: session_result()
  def run_session(acs_url, opts \\ []) when is_binary(acs_url) do
    :telemetry.execute([:caretaker, :cpe_client, :session, :start], %{}, %{acs_url: acs_url})

    timeout = Keyword.get(opts, :timeout, @default_timeout)
    cwmp_ns = Keyword.get(opts, :cwmp_ns, @default_cwmp_ns)
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    backoff_base = Keyword.get(opts, :backoff_base, @default_backoff)

    device_id =
      Keyword.get(opts, :device_id, %{
        manufacturer: "Acme",
        oui: "A1B2C3",
        product_class: "Router",
        serial_number: "XYZ123"
      })

    inform =
      Inform.new(
        device_id: device_id,
        events: Keyword.get(opts, :events, ["1 BOOT"]),
        max_envelopes: 1,
        retry_count: 0
      )

    cwmp_id = gen_id()

    with {:ok, inform_body} <- Inform.encode(inform),
         {:ok, inform_env} <- SOAP.encode_envelope(inform_body, %{id: cwmp_id, cwmp_ns: cwmp_ns}),
         :ok <- ensure_finch_started(),
         {:ok, %{status: 200, body: ack_xml}} <-
           http_retry(
             fn ->
               http_post_xml(acs_url, inform_env, timeout)
             end,
             max_retries,
             backoff_base
           ),
         {:ok, %{body: %{rpc: "InformResponse"}}} <- SOAP.decode_envelope(ack_xml) do
      case session_loop(acs_url, cwmp_ns, device_id, timeout, max_retries, backoff_base) do
        {:ok, last_rpc} ->
          :telemetry.execute([:caretaker, :cpe_client, :session, :stop], %{}, %{
            acs_url: acs_url,
            cwmp_id: cwmp_id,
            cwmp_ns: cwmp_ns,
            rpc: last_rpc
          })

          {:ok,
           %{cwmp_id: cwmp_id, cwmp_ns: cwmp_ns, inform_ack: true, rpc: last_rpc, rpc_xml: nil}}

        {:error, reason} = err ->
          :telemetry.execute([:caretaker, :cpe_client, :error], %{}, %{
            acs_url: acs_url,
            cwmp_id: cwmp_id,
            reason: reason
          })

          err
      end
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

  defp session_loop(acs_url, ns, device_id, timeout, max_retries, backoff_base, last_rpc \\ nil) do
    empty_res =
      http_retry(
        fn ->
          http_post_empty(acs_url, timeout)
        end,
        max_retries,
        backoff_base
      )

    case empty_res do
      {:ok, %{status: 204}} ->
        {:ok, last_rpc}

      {:ok, %{status: 200, body: rpc_xml}} ->
        ns2 =
          case Regex.run(~r/xmlns:cwmp="([^"]+)"/, rpc_xml) do
            [_, v] -> v
            _ -> ns
          end

        rpc =
          case Regex.run(~r/<soap(?:env)?:Body>\s*<(?:(\w+):)?(\w+)/, rpc_xml,
                 capture: :all_but_first
               ) do
            ["cwmp", name] -> name
            [_, name] -> name
            [name] -> name
            _ -> nil
          end

        :telemetry.execute([:caretaker, :cpe_client, :rpc, :received], %{}, %{
          acs_url: acs_url,
          cwmp_ns: ns2,
          rpc: rpc
        })

        _ = respond_to_rpc(acs_url, rpc, device_id, ns2, timeout)
        session_loop(acs_url, ns2, device_id, timeout, max_retries, backoff_base, rpc)

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected, other}}
    end
  end

  defp respond_to_rpc(acs_url, "GetParameterValues", device_id, ns, timeout) do
    params = [
      %{
        name: "Device.DeviceInfo.Manufacturer",
        value: device_id.manufacturer,
        type: "xsd:string"
      },
      %{
        name: "Device.DeviceInfo.SerialNumber",
        value: device_id.serial_number,
        type: "xsd:string"
      }
    ]

    with {:ok, body} <-
           Caretaker.TR069.RPC.GetParameterValuesResponse.encode(%{parameters: params}),
         {:ok, env} <- SOAP.encode_envelope(body, %{cwmp_ns: ns}),
         {:ok, %{status: 204}} <- http_post_xml(acs_url, env, timeout) do
      :telemetry.execute([:caretaker, :cpe_client, :rpc, :responded], %{}, %{
        acs_url: acs_url,
        cwmp_ns: ns,
        rpc: "GetParameterValues"
      })

      :ok
    else
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  defp respond_to_rpc(_acs_url, rpc, _device_id, _ns, _timeout) when is_binary(rpc) do
    :telemetry.execute([:caretaker, :cpe_client, :rpc, :unsupported], %{}, %{rpc: rpc})
    :ok
  end

  # -- HTTP helpers --

  defp http_post_xml(url, body, timeout) do
    headers = [
      {"content-type", SOAP.content_type()},
      {"soapaction", ""},
      {"user-agent", "CaretakerCPE/0.1"},
      {"accept", "text/xml"}
    ]

    req = Finch.build(:post, url, headers, IO.iodata_to_binary(body))

    :telemetry.execute([:caretaker, :cpe_client, :http, :request, :start], %{}, %{
      method: :post,
      url: url
    })

    case Finch.request(req, Caretaker.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        :telemetry.execute([:caretaker, :cpe_client, :http, :request, :stop], %{}, %{
          method: :post,
          url: url,
          status: status
        })

        {:ok, %{status: status, body: resp_body}}

      {:error, reason} ->
        :telemetry.execute([:caretaker, :cpe_client, :http, :request, :stop], %{}, %{
          method: :post,
          url: url,
          error: reason
        })

        {:error, reason}
    end
  end

  defp http_post_empty(url, timeout) do
    headers = [
      {"user-agent", "CaretakerCPE/0.1"},
      {"accept", "text/xml"}
    ]

    req = Finch.build(:post, url, headers)

    :telemetry.execute([:caretaker, :cpe_client, :http, :request, :start], %{}, %{
      method: :post,
      url: url
    })

    case Finch.request(req, Caretaker.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        :telemetry.execute([:caretaker, :cpe_client, :http, :request, :stop], %{}, %{
          method: :post,
          url: url,
          status: status
        })

        {:ok, %{status: status, body: resp_body}}

      {:error, reason} ->
        :telemetry.execute([:caretaker, :cpe_client, :http, :request, :stop], %{}, %{
          method: :post,
          url: url,
          error: reason
        })

        {:error, reason}
    end
  end

  # -- Retry helpers --

  defp http_retry(fun, max_retries, base_ms) when is_function(fun, 0) do
    do_retry(fun, 0, max_retries, base_ms)
  end

  defp do_retry(fun, attempt, max_retries, base_ms) do
    case fun.() do
      {:ok, %{status: status}} = ok when status in 200..299 ->
        ok

      {:ok, %{status: status}} when status in [408] or status >= 500 ->
        if attempt < max_retries do
          backoff = trunc(:math.pow(2, attempt) * base_ms)
          jitter = if backoff > 0, do: :rand.uniform(backoff), else: 0

          :telemetry.execute([:caretaker, :cpe_client, :retry], %{}, %{
            attempt: attempt + 1,
            backoff_ms: jitter
          })

          Process.sleep(jitter)
          do_retry(fun, attempt + 1, max_retries, base_ms)
        else
          {:error, {:http, :max_retries_exceeded, status}}
        end

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        if attempt < max_retries do
          backoff = trunc(:math.pow(2, attempt) * base_ms)
          jitter = if backoff > 0, do: :rand.uniform(backoff), else: 0

          :telemetry.execute([:caretaker, :cpe_client, :retry], %{}, %{
            attempt: attempt + 1,
            backoff_ms: jitter
          })

          Process.sleep(jitter)
          do_retry(fun, attempt + 1, max_retries, base_ms)
        else
          {:error, reason}
        end
    end
  end

  defp gen_id do
    Base.encode16(:crypto.strong_rand_bytes(6), case: :upper)
  end

  defp ensure_finch_started do
    case Process.whereis(Caretaker.Finch) do
      nil ->
        case Supervisor.start_link([{Finch, name: Caretaker.Finch}], strategy: :one_for_one) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        :ok
    end
  end
end
