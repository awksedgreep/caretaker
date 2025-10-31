defmodule Caretaker.TR069.RPC.GetParameterValues do
  @moduledoc """
  TR-069 GetParameterValues RPC (encode only, minimal).
  """

  @enforce_keys [:names]
  defstruct [:names]

  @type t :: %__MODULE__{names: [String.t()]}

  @spec new([String.t()]) :: t()
  def new(names), do: %__MODULE__{names: names}

  @doc "Encode body element (without SOAP Envelope) via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{names: names}) do
    start = System.monotonic_time()
    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :start], %{}, %{rpc: :get_parameter_values})

    pn = %{
      "@xsi:type" => "cwmp:ParameterNames",
      "@arrayType" => "xsd:string[#{length(names)}]",
      "string" => Enum.map(names, fn n -> %{"string" => n} end)
    }

    map = %{"cwmp:GetParameterValues" => %{"ParameterNames" => pn}}

    res = Lather.Xml.Builder.build_fragment(map)
    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :stop], %{duration: System.monotonic_time() - start}, %{rpc: :get_parameter_values})
    res
  end
end
