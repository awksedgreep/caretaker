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

  @doc "Encode to SOAP body structure (without Envelope)"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = inform) do
    start = System.monotonic_time()
    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :start], %{}, %{rpc: :inform})

    did = inform.device_id

    events =
      Enum.map(inform.events, fn e ->
        ["<EventStruct><EventCode>", e, "</EventCode><CommandKey></CommandKey></EventStruct>"]
      end)

    body =
      [
        "<cwmp:Inform>",
        "<DeviceId>",
        tag("Manufacturer", did.manufacturer),
        tag("OUI", did.oui),
        tag("ProductClass", did.product_class),
        tag("SerialNumber", did.serial_number),
        "</DeviceId>",
        "<Event>",
        events,
        "</Event>",
        tag("MaxEnvelopes", Integer.to_string(inform.max_envelopes)),
        tag("CurrentTime", to_iso8601(inform.current_time)),
        tag("RetryCount", Integer.to_string(inform.retry_count)),
        "<ParameterList arrayType=\"xsd:anyType[]\" xsi:type=\"cwmp:ParameterValueList\"></ParameterList>",
        "</cwmp:Inform>"
      ]

    duration = System.monotonic_time() - start

    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :stop], %{duration: duration}, %{
      rpc: :inform
    })

    {:ok, body}
  end

  @doc "Decode from Inform body xml to struct (best-effort, spec-first)"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    import SweetXml

    start = System.monotonic_time()
    :telemetry.execute([:caretaker, :tr069, :rpc, :decode, :start], %{}, %{rpc: :inform})

    try do
      doc = SweetXml.parse(xml)

      did = %{
        manufacturer:
          xpath(doc, ~x"//*[local-name()='DeviceId']/*[local-name()='Manufacturer']/text()"s) ||
            "",
        oui: xpath(doc, ~x"//*[local-name()='DeviceId']/*[local-name()='OUI']/text()"s) || "",
        product_class:
          xpath(doc, ~x"//*[local-name()='DeviceId']/*[local-name()='ProductClass']/text()"s) ||
            "",
        serial_number:
          xpath(doc, ~x"//*[local-name()='DeviceId']/*[local-name()='SerialNumber']/text()"s) ||
            ""
      }

      events =
        xpath(doc, ~x"//*[local-name()='Event']/*/*[local-name()='EventCode']/text()"ls)
        |> Enum.map(&to_string/1)

      max_env = (xpath(doc, ~x"//*[local-name()='MaxEnvelopes']/text()"s) || "1") |> to_int(1)
      retry_count = (xpath(doc, ~x"//*[local-name()='RetryCount']/text()"s) || "0") |> to_int(0)
      current_time = xpath(doc, ~x"//*[local-name()='CurrentTime']/text()"s) || ""

      result =
        {:ok,
         %__MODULE__{
           device_id: did,
           events: events,
           max_envelopes: max_env,
           current_time: current_time,
           retry_count: retry_count,
           parameter_list: []
         }}

      duration = System.monotonic_time() - start

      :telemetry.execute([:caretaker, :tr069, :rpc, :decode, :stop], %{duration: duration}, %{
        rpc: :inform
      })

      result
    rescue
      e ->
        duration = System.monotonic_time() - start

        :telemetry.execute([:caretaker, :tr069, :rpc, :decode, :stop], %{duration: duration}, %{
          rpc: :inform,
          error: true
        })

        {:error, {:decode_failed, e}}
    end
  end

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
