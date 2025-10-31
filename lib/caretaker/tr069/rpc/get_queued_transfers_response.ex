defmodule Caretaker.TR069.RPC.GetQueuedTransfersResponse do
  @moduledoc """
  TR-069 GetQueuedTransfersResponse (CPE -> ACS).
  """

  @type item :: %{command_key: String.t(), state: String.t(), is_download: boolean()}
  @type t :: %{transfers: [item()]}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%{transfers: list}) do
    encoded =
      Enum.map(list, fn %{command_key: ck, state: st, is_download: id} ->
        %{"TransferStruct" => %{"CommandKey" => ck, "State" => st, "IsDownload" => bool(id)}}
      end)

    map = %{"cwmp:GetQueuedTransfersResponse" => %{"TransferList" => encoded}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:GetQueuedTransfersResponse"] || root["GetQueuedTransfersResponse"] || %{}
        tl = node["TransferList"] || %{}
        items = tl["TransferStruct"] |> List.wrap()

        transfers =
          Enum.map(items, fn item ->
            %{
              command_key: item["CommandKey"] || "",
              state: item["State"] || "",
              is_download: to_bool(item["IsDownload"]) || false
            }
          end)

        {:ok, %{transfers: transfers}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  defp bool(true), do: "1"
  defp bool(false), do: "0"
  defp to_bool(v) when v in ["1", 1, true], do: true
  defp to_bool(_), do: false
end