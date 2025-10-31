defmodule Caretaker.TR069.RPC.GetParameterAttributesResponse do
  @moduledoc """
  TR-069 GetParameterAttributesResponse (CPE -> ACS)
  """

  @type attr :: %{name: String.t(), notification: integer(), access_list: [String.t()]}
  @type t :: %{parameters: [attr()]}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%{parameters: params}) do
    pis =
      Enum.map(params, fn %{name: n, notification: notif, access_list: alist} ->
        %{
          "ParameterAttributeStruct" => %{
            "Name" => n,
            "Notification" => Integer.to_string(notif),
            "AccessList" => Enum.map(alist, fn s -> %{"string" => s} end)
          }
        }
      end)

    map = %{"cwmp:GetParameterAttributesResponse" => %{"ParameterList" => pis}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:GetParameterAttributesResponse"] || root["GetParameterAttributesResponse"] || %{}
        plist = node["ParameterList"] || %{}
        items = plist["ParameterAttributeStruct"] |> List.wrap()

        params =
          Enum.map(items, fn item ->
            name = item["Name"] || ""
            notif = to_int(item["Notification"], 0)
            al = item["AccessList"] || []
            access_list = normalize_string_list(al)

            %{name: name, notification: notif, access_list: access_list}
          end)

        {:ok, %{parameters: params}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  defp normalize_string_list(val) do
    base =
      case val do
        l when is_list(l) -> Enum.flat_map(l, &normalize_string_list/1)
        %{} = m -> List.wrap(m["string"]) |> Enum.flat_map(&normalize_string_list/1)
        v when is_binary(v) -> [v]
        _ -> []
      end

    base
    |> Enum.flat_map(fn s ->
      s
      |> String.split(~r/\s+/, trim: true)
    end)
  end

  defp to_int(nil, d), do: d
  defp to_int(<<>>, d), do: d
  defp to_int(v, _d) when is_integer(v), do: v
  defp to_int(v, _d) when is_binary(v), do: String.to_integer(v)
end