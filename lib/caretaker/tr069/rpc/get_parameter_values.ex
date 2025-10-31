defmodule Caretaker.TR069.RPC.GetParameterValues do
  @moduledoc """
  TR-069 GetParameterValues RPC (encode only, minimal).
  """

  @enforce_keys [:names]
  defstruct [:names]

  @type t :: %__MODULE__{names: [String.t()]}

  @spec new([String.t()]) :: t()
  def new(names), do: %__MODULE__{names: names}

  @doc "Encode body element (without SOAP Envelope)"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{names: names}) do
    start = System.monotonic_time()
    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :start], %{}, %{rpc: :get_parameter_values})

    items = for n <- names, do: ["<string>", n, "</string>"]

    body =
      [
        "<cwmp:GetParameterValues>",
        "<ParameterNames xsi:type=\"cwmp:ParameterNames\" arrayType=\"xsd:string[",
        Integer.to_string(length(names)),
        "]\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">",
        items,
        "</ParameterNames>",
        "</cwmp:GetParameterValues>"
      ]

    :telemetry.execute([:caretaker, :tr069, :rpc, :encode, :stop], %{duration: System.monotonic_time() - start}, %{rpc: :get_parameter_values})

    {:ok, body}
  end
end
