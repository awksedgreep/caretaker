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
    items = for n <- names, do: ["<string>", n, "</string>"]

    body =
      [
        "<cwmp:GetParameterValues>",
        "<ParameterNames xsi:type=\"cwmp:ParameterNames\" arrayType=\"xsd:string[",
        Integer.to_string(length(names)), "]\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">",
        items,
        "</ParameterNames>",
        "</cwmp:GetParameterValues>"
      ]

    {:ok, body}
  end
end
