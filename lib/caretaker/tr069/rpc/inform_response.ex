defmodule Caretaker.TR069.RPC.InformResponse do
  @moduledoc """
  TR-069 InformResponse RPC.
  """

  @enforce_keys [:max_envelopes]
  defstruct [:max_envelopes]

  @type t :: %__MODULE__{max_envelopes: pos_integer()}

  @spec new(pos_integer()) :: t()
  def new(max_envelopes), do: %__MODULE__{max_envelopes: max_envelopes}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(_resp) do
    # TODO: Use Lather to build body node
    {:error, :not_implemented}
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(_xml) do
    # TODO: Use Lather to parse InformResponse
    {:error, :not_implemented}
  end
end
