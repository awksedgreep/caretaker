defmodule Caretaker.TR069.RPC.SetParameterValues do
  @moduledoc """
  TR-069 SetParameterValues RPC (encode of request body).
  """

  @type param :: %{name: String.t(), value: String.t(), type: String.t()}

  @enforce_keys [:parameters]
  defstruct [:parameters, parameter_key: ""]

  @type t :: %__MODULE__{parameters: [param()], parameter_key: String.t()}

  @spec new([param()], keyword()) :: t()
  def new(params, opts \\ []) do
    %__MODULE__{parameters: params, parameter_key: Keyword.get(opts, :parameter_key, "")}
  end

  @doc "Encode body element (without SOAP Envelope)"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{parameters: params, parameter_key: key}) do
    items =
      Enum.map(params, fn %{name: n, value: v, type: t} ->
        [
          "<ParameterValueStruct>",
          "<Name>", n, "</Name>",
          "<Value xsi:type=\"", t, "\">", v, "</Value>",
          "</ParameterValueStruct>"
        ]
      end)

    {:ok,
     [
       "<cwmp:SetParameterValues>",
       "<ParameterList xsi:type=\"cwmp:ParameterValueList\" arrayType=\"cwmp:ParameterValueStruct[",
       Integer.to_string(length(params)), "]\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">",
       items,
       "</ParameterList>",
       "<ParameterKey>", key, "</ParameterKey>",
       "</cwmp:SetParameterValues>"
     ]}
  end
end
