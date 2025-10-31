defmodule Caretaker.TR069.RPC.RequestDownloadResponse do
  @moduledoc """
  TR-069 RequestDownloadResponse (ACS -> CPE).
  """

  @enforce_keys [:status]
  defstruct [:status]

  @type t :: %__MODULE__{status: integer()}

  @spec new(keyword()) :: t()
  def new(opts), do: %__MODULE__{status: Keyword.get(opts, :status, 0)}

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = r) do
    map = %{"cwmp:RequestDownloadResponse" => %{"Status" => Integer.to_string(r.status)}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode body via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:RequestDownloadResponse"] || root["RequestDownloadResponse"] || %{}
        {:ok, %__MODULE__{status: to_int(node["Status"], 0)}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  defp to_int(nil, d), do: d
  defp to_int(<<>>, d), do: d
  defp to_int(v, _d) when is_integer(v), do: v
  defp to_int(v, _d) when is_binary(v), do: String.to_integer(v)
end