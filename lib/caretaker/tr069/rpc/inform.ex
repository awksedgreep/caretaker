defmodule Caretaker.TR069.RPC.Inform do
  @moduledoc """
  TR-069 Inform RPC.
  """

  @enforce_keys [:device_id, :events, :max_envelopes, :current_time, :retry_count]
  @derive {Jason.Encoder,
           only: [
             :device_id,
             :events,
             :max_envelopes,
             :current_time,
             :retry_count,
             :parameter_list
           ]}
  defstruct [:device_id, :events, :max_envelopes, :current_time, :retry_count, parameter_list: []]

  @type device_id :: %{
          manufacturer: String.t(),
          oui: String.t(),
          product_class: String.t(),
          serial_number: String.t()
        }

  @type t :: %__MODULE__{
          device_id: device_id(),
          events: [String.t()],
          max_envelopes: pos_integer(),
          current_time: NaiveDateTime.t() | DateTime.t() | String.t(),
          retry_count: non_neg_integer(),
          parameter_list: list()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      device_id: Keyword.fetch!(opts, :device_id),
      events: Keyword.get(opts, :events, []),
      max_envelopes: Keyword.get(opts, :max_envelopes, 1),
      current_time: Keyword.get(opts, :current_time, DateTime.utc_now()),
      retry_count: Keyword.get(opts, :retry_count, 0),
      parameter_list: Keyword.get(opts, :parameter_list, [])
    }
  end

  @doc "Encode to SOAP body structure (without Envelope) via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = inform) do
    start = System.monotonic_time()
    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :start], %{}, %{rpc: :inform})

    did = inform.device_id

    event_list = Enum.map(inform.events, fn e -> %{"EventStruct" => %{"EventCode" => e, "CommandKey" => ""}} end)

    map = %{
      "cwmp:Inform" => %{
        "DeviceId" => %{
          "Manufacturer" => did.manufacturer,
          "OUI" => did.oui,
          "ProductClass" => did.product_class,
          "SerialNumber" => did.serial_number
        },
        "Event" => event_list,
        "MaxEnvelopes" => Integer.to_string(inform.max_envelopes),
        "CurrentTime" => to_iso8601(inform.current_time),
        "RetryCount" => Integer.to_string(inform.retry_count),
        "ParameterList" => %{}
      }
    }

    res = Lather.Xml.Builder.build_fragment(map)

    duration = System.monotonic_time() - start
    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :stop], %{duration: duration}, %{rpc: :inform})
    res
  end

  @doc "Decode from Inform body xml to struct via Lather (no SweetXml)"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    start = System.monotonic_time()
    :telemetry.execute([:caretaker, :tr069, :rpc, :decode, :start], %{}, %{rpc: :inform})

    try do
      # Wrap to stabilize prefixes; tolerate cwmp or no-prefix keys
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:Inform"] || root["Inform"] || %{}

        dev = node["DeviceId"] || %{}
        did = %{
          manufacturer: dev["Manufacturer"] || "",
          oui: dev["OUI"] || "",
          product_class: dev["ProductClass"] || "",
          serial_number: dev["SerialNumber"] || ""
        }

        events_list =
          case node["Event"] || %{} do
            %{} = ev -> List.wrap(ev["EventStruct"]) |> Enum.map(&event_code/1)
            other -> List.wrap(other) |> Enum.map(&event_code/1)
          end
          |> Enum.reject(&is_nil/1)

        max_env = to_int((node["MaxEnvelopes"] || "1"), 1)
        retry_count = to_int((node["RetryCount"] || "0"), 0)
        current_time = node["CurrentTime"] || ""

        result =
          {:ok,
           %__MODULE__{
             device_id: did,
             events: events_list,
             max_envelopes: max_env,
             current_time: current_time,
             retry_count: retry_count,
             parameter_list: []
           }}

        duration = System.monotonic_time() - start
        :telemetry.execute([:caretaker, :tr069, :rpc, :decode, :stop], %{duration: duration}, %{rpc: :inform})
        result
      end
    rescue
      e ->
        duration = System.monotonic_time() - start
        :telemetry.execute([:caretaker, :tr069, :rpc, :decode, :stop], %{duration: duration}, %{rpc: :inform, error: true})
        {:error, {:decode_failed, e}}
    end
  end

  defp event_code(%{"EventCode" => v}) when is_binary(v), do: v
  defp event_code(%{"EventCode" => %{"#text" => v}}), do: v
  defp event_code(_), do: nil

  def to_map(%__MODULE__{} = i) do
    %{
      device_id: i.device_id,
      events: i.events,
      max_envelopes: i.max_envelopes,
      current_time: to_iso8601(i.current_time),
      retry_count: i.retry_count,
      parameter_list: i.parameter_list
    }
  end

  defp tag(name, value), do: ["<", name, ">", value, "</", name, ">"]

  defp to_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_iso8601(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp to_iso8601(iso) when is_binary(iso), do: iso

  defp to_int(<<>> = _empty, default), do: default
  defp to_int(nil, default), do: default
  defp to_int(str, _default) when is_binary(str), do: String.to_integer(str)
end
