defmodule Caretaker.TR069.RPC.Reboot do
  @moduledoc """
  TR-069 Reboot RPC (ACS -> CPE).
  """

  @enforce_keys [:command_key]
  defstruct [:command_key]

  @type t :: %__MODULE__{command_key: String.t()}

  @spec new(keyword()) :: t()
  def new(opts), do: %__MODULE__{command_key: Keyword.fetch!(opts, :command_key)}

  @doc "Encode body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = r) do
    map = %{"cwmp:Reboot" => %{"CommandKey" => r.command_key}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode body via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:Reboot"] || root["Reboot"] || %{}
        {:ok, %__MODULE__{command_key: node["CommandKey"] || ""}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end