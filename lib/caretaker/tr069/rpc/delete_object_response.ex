defmodule Caretaker.TR069.RPC.DeleteObjectResponse do
  @moduledoc """
  Decoder for DeleteObjectResponse.
  """

  @type t :: %{status: integer()}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%{status: status}) do
    map = %{"cwmp:DeleteObjectResponse" => %{"Status" => Integer.to_string(status)}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:DeleteObjectResponse"] || root["DeleteObjectResponse"] || %{}
        s = node["Status"] || "0"
        {:ok, %{status: String.to_integer(to_string(s))}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end