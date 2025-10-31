defmodule Caretaker.TR069.RPC.SetParameterAttributes do
  @moduledoc """
  TR-069 SetParameterAttributes (ACS -> CPE)
  """

  @type spa :: %{
          name: String.t(),
          notification_change: boolean(),
          notification: integer(),
          access_list_change: boolean(),
          access_list: [String.t()]
        }

  @type t :: %{parameters: [spa()]}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%{parameters: list}) do
    items =
      Enum.map(list, fn %{name: n, notification_change: nc, notification: nof, access_list_change: ac, access_list: al} ->
        %{
          "SetParameterAttributesStruct" => %{
            "Name" => n,
            "NotificationChange" => bool(nc),
            "Notification" => Integer.to_string(nof),
            "AccessListChange" => bool(ac),
            "AccessList" => Enum.map(al, fn s -> %{"string" => s} end)
          }
        }
      end)

    map = %{"cwmp:SetParameterAttributes" => %{"ParameterList" => items}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:SetParameterAttributes"] || root["SetParameterAttributes"] || %{}
        plist = node["ParameterList"] || %{}
        items = plist["SetParameterAttributesStruct"] |> List.wrap()

        params =
          Enum.map(items, fn item ->
            al = item["AccessList"] || []
            access_list = normalize_string_list(al)

            %{
              name: item["Name"] || "",
              notification_change: to_bool(item["NotificationChange"]),
              notification: to_int(item["Notification"], 0),
              access_list_change: to_bool(item["AccessListChange"]),
              access_list: access_list
            }
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

  defp bool(true), do: "1"
  defp bool(false), do: "0"
  defp to_bool(v) when v in ["1", 1, true], do: true
  defp to_bool(_), do: false

  defp to_int(nil, d), do: d
  defp to_int(<<>>, d), do: d
  defp to_int(v, _d) when is_integer(v), do: v
  defp to_int(v, _d) when is_binary(v), do: String.to_integer(v)
end