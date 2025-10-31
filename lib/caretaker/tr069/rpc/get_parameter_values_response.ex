defmodule Caretaker.TR069.RPC.GetParameterValuesResponse do
  @moduledoc """
  Decoder for GetParameterValuesResponse.
  """

  @type param :: %{name: String.t(), value: String.t(), type: String.t()}
  @type t :: %{parameters: [param()]}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%{parameters: params}) do
    # Build as repeated ParameterValueStruct elements under ParameterList
    pvs =
      Enum.map(params, fn %{name: n, value: v, type: t} ->
        %{"ParameterValueStruct" => %{"Name" => n, "Value" => %{"@xsi:type" => t, "#text" => v}}}
      end)

    map = %{
      "cwmp:GetParameterValuesResponse" => %{
        "ParameterList" => pvs
      }
    }

    Lather.Xml.Builder.build_fragment(map)
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      # Ensure xsi/xsd prefixes are tolerated
      wrapped =
        "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">" <>
          xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}

        node =
          root["cwmp:GetParameterValuesResponse"] || root["GetParameterValuesResponse"] || %{}

        plist = node["ParameterList"] || %{}
        pv = plist["ParameterValueStruct"] || []

        list =
          pv
          |> List.wrap()
          |> Enum.map(fn item ->
            name = item["Name"] || ""
            val = get_in(item, ["Value", "#text"]) || item["Value"] || ""
            typ = get_in(item, ["Value", "@xsi:type"]) || ""
            %{name: name, value: val, type: typ}
          end)

        {:ok, %{parameters: list}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end
