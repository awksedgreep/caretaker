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

  @doc "Encode body element (without SOAP Envelope) via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{parameters: params, parameter_key: key}) do
    plist = %{
      "@xsi:type" => "cwmp:ParameterValueList",
      "@arrayType" => "cwmp:ParameterValueStruct[#{length(params)}]",
      "ParameterValueStruct" =>
        Enum.map(params, fn %{name: n, value: v, type: t} ->
          %{"Name" => n, "Value" => %{"@xsi:type" => t, "#text" => v}}
        end)
    }

    map = %{
      "cwmp:SetParameterValues" => %{
        "ParameterList" => plist,
        "ParameterKey" => key
      }
    }

    Lather.Xml.Builder.build_fragment(map)
  end
end
