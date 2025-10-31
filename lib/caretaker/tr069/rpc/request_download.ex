defmodule Caretaker.TR069.RPC.RequestDownload do
  @moduledoc """
  TR-069 RequestDownload (CPE -> ACS).
  """

  @enforce_keys [:file_type, :file_type_arg]
  defstruct [:file_type, :file_type_arg]

  @type t :: %__MODULE__{file_type: String.t(), file_type_arg: String.t()}

  @spec new(keyword()) :: t()
  def new(opts), do: %__MODULE__{file_type: Keyword.fetch!(opts, :file_type), file_type_arg: Keyword.fetch!(opts, :file_type_arg)}

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = r) do
    map = %{"cwmp:RequestDownload" => %{"FileType" => r.file_type, "FileTypeArg" => r.file_type_arg}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode body via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:RequestDownload"] || root["RequestDownload"] || %{}
        {:ok, %__MODULE__{file_type: node["FileType"] || "", file_type_arg: node["FileTypeArg"] || ""}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end