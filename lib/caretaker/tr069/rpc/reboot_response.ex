defmodule Caretaker.TR069.RPC.RebootResponse do
  @moduledoc """
  TR-069 RebootResponse (CPE -> ACS), empty body.
  """

  @type t :: %__MODULE__{}
  defstruct []

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Encode empty body via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{}) do
    Lather.Xml.Builder.build_fragment(%{"cwmp:RebootResponse" => %{}})
  end

  @doc "Decode empty body via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        _node = root["cwmp:RebootResponse"] || root["RebootResponse"] || %{}
        {:ok, %__MODULE__{}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end