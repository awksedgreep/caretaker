defmodule Caretaker.TR069.RPC.GetParameterNamesResponse do
  @moduledoc """
  Decoder for GetParameterNamesResponse (ParameterList -> ParameterInfoStruct[]).
  """

  @type info :: %{name: String.t(), writable: boolean()}
  @type t :: %{parameters: [info()]}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%{parameters: params}) do
    _infos = Enum.map(params, fn %{name: n, writable: w} -> %{"ParameterInfoStruct" => %{"Name" => n, "Writable" => if(w, do: "1", else: "0")}} end)

    map = %{
      "cwmp:GetParameterNamesResponse" => %{
        "ParameterList" => %{
          "ParameterInfoStruct" => Enum.map(params, fn %{name: n, writable: w} -> %{"Name" => n, "Writable" => if(w, do: "1", else: "0")} end)
        }
      }
    }

    Lather.Xml.Builder.build_fragment(map)
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:GetParameterNamesResponse"] || root["GetParameterNamesResponse"] || %{}
        plist = node["ParameterList"] || %{}
        pi = plist["ParameterInfoStruct"] || []

        list =
          pi
          |> List.wrap()
          |> Enum.map(fn item ->
            name = item["Name"] || ""
            w = item["Writable"] || "0"
            %{name: name, writable: w in ["1", 1, true]}
          end)

        {:ok, %{parameters: list}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end