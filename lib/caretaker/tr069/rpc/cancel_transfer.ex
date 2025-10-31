defmodule Caretaker.TR069.RPC.CancelTransfer do
  @moduledoc """
  TR-069 CancelTransfer (ACS -> CPE)
  """

  @enforce_keys [:command_key]
  defstruct [:command_key]

  @type t :: %__MODULE__{command_key: String.t()}

  @spec new(keyword()) :: t()
  def new(opts), do: %__MODULE__{command_key: Keyword.fetch!(opts, :command_key)}

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = c) do
    Lather.Xml.Builder.build_fragment(%{"cwmp:CancelTransfer" => %{"CommandKey" => c.command_key}})
  end

  @doc "Decode body via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:CancelTransfer"] || root["CancelTransfer"] || %{}
        {:ok, %__MODULE__{command_key: node["CommandKey"] || ""}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end