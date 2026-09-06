defmodule Caretaker.TR069.RPC.GetParameterValues do
  @moduledoc """
  TR-069 GetParameterValues RPC (encode/decode of the request body).
  """

  @enforce_keys [:names]
  defstruct [:names]

  @type t :: %__MODULE__{names: [String.t()]}

  @spec new([String.t()]) :: t()
  def new(names), do: %__MODULE__{names: names}

  @doc """
  Encode body element (without SOAP Envelope).

  `ParameterNames` is a SOAP array whose items are direct `<string>` children,
  so the element is assembled by hand; Lather's builder cannot emit repeated
  siblings under an element that also carries attributes.
  """
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{names: names}) do
    start = System.monotonic_time()

    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :start], %{}, %{
      rpc: :get_parameter_values
    })

    items =
      Enum.map(names, fn n ->
        {:ok, frag} = Lather.Xml.Builder.build_fragment(%{"string" => n})
        frag
      end)

    xml = [
      "<cwmp:GetParameterValues>",
      "<ParameterNames xsi:type=\"cwmp:ParameterNames\" arrayType=\"xsd:string[",
      Integer.to_string(length(names)),
      "]\">",
      items,
      "</ParameterNames>",
      "</cwmp:GetParameterValues>"
    ]

    :telemetry.execute(
      [:caretaker, :tr069, :rpc, :encode, :stop],
      %{duration: System.monotonic_time() - start},
      %{rpc: :get_parameter_values}
    )

    {:ok, IO.iodata_to_binary(xml)}
  end

  @doc "Decode request body into struct via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped =
        "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">" <>
          xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:GetParameterValues"] || root["GetParameterValues"] || %{}
        pn = node["ParameterNames"] || %{}
        {:ok, %__MODULE__{names: extract_names(pn)}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  # Accepts the spec shape (direct <string> children) as well as the nested
  # shape that older Caretaker releases emitted.
  defp extract_names(%{"string" => v}), do: extract_names(v)
  defp extract_names(v) when is_binary(v), do: [v]
  defp extract_names(l) when is_list(l), do: Enum.flat_map(l, &extract_names/1)
  defp extract_names(%{"#text" => v}) when is_binary(v), do: [v]
  defp extract_names(_), do: []
end
