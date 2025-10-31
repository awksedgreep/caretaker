defmodule Caretaker.TR069.RPC.InformResponse do
  @moduledoc """
  TR-069 InformResponse RPC.
  """

  @enforce_keys [:max_envelopes]
  defstruct [:max_envelopes]

  @type t :: %__MODULE__{max_envelopes: pos_integer()}

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{max_envelopes: Keyword.get(opts, :max_envelopes, 1)}
  end

  @doc "Encode body element (without SOAP Envelope) via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{max_envelopes: max}) do
    map = %{"cwmp:InformResponse" => %{"MaxEnvelopes" => Integer.to_string(max)}}
    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode body element into struct via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:InformResponse"] || root["InformResponse"] || %{}
        max = node["MaxEnvelopes"] || ""
        {:ok, %__MODULE__{max_envelopes: String.to_integer(max)}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end
