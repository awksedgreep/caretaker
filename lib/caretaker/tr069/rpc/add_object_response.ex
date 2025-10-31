defmodule Caretaker.TR069.RPC.AddObjectResponse do
  @moduledoc """
  Decoder for AddObjectResponse.
  """

  @type t :: %{instance_number: integer(), status: integer()}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%{instance_number: inst, status: status}) do
    map = %{"cwmp:AddObjectResponse" => %{"InstanceNumber" => Integer.to_string(inst), "Status" => Integer.to_string(status)}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:AddObjectResponse"] || root["AddObjectResponse"] || %{}
        inst = node["InstanceNumber"] || "0"
        s = node["Status"] || "0"
        {:ok, %{instance_number: String.to_integer(to_string(inst)), status: String.to_integer(to_string(s))}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end