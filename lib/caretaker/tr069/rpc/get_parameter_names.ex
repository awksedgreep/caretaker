defmodule Caretaker.TR069.RPC.GetParameterNames do
  @moduledoc """
  TR-069 GetParameterNames RPC (encode/decode of the request body).
  """

  @enforce_keys [:parameter_path, :next_level]
  defstruct [:parameter_path, :next_level]

  @type t :: %__MODULE__{parameter_path: String.t(), next_level: boolean()}

  @spec new(String.t(), boolean()) :: t()
  def new(path, next_level), do: %__MODULE__{parameter_path: path, next_level: next_level}

  @doc "Encode body element (without SOAP Envelope)"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{parameter_path: path, next_level: next}) do
    {:ok,
     [
       "<cwmp:GetParameterNames>",
       "<ParameterPath>", path, "</ParameterPath>",
       "<NextLevel>", (if next, do: "1", else: "0"), "</NextLevel>",
       "</cwmp:GetParameterNames>"
     ]}
  end

  @doc "Decode request body into struct"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    import SweetXml

    try do
      doc = SweetXml.parse(xml)
      path = xpath(doc, ~x"//*[local-name()='ParameterPath']/text()"s) || ""
      next = (xpath(doc, ~x"//*[local-name()='NextLevel']/text()"s) || "0") in ["1", 1]
      {:ok, %__MODULE__{parameter_path: path, next_level: next}}
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end
