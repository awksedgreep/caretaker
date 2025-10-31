defmodule Caretaker.TR069.RPC.GetParameterNames do
  @moduledoc """
  TR-069 GetParameterNames RPC (encode/decode of the request body).
  """

  @enforce_keys [:parameter_path, :next_level]
  defstruct [:parameter_path, :next_level]

  @type t :: %__MODULE__{parameter_path: String.t(), next_level: boolean()}

  @spec new(String.t(), boolean()) :: t()
  def new(path, next_level), do: %__MODULE__{parameter_path: path, next_level: next_level}

  @doc "Encode body element (without SOAP Envelope) via Lather"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{parameter_path: path, next_level: next}) do
    map = %{
      "cwmp:GetParameterNames" => %{
        "ParameterPath" => path,
        "NextLevel" => if(next, do: "1", else: "0")
      }
    }

    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode request body into struct via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:GetParameterNames"] || root["GetParameterNames"] || %{}
        path = node["ParameterPath"] || ""
        next_raw = node["NextLevel"] || "0"
        next = next_raw in ["1", 1, true]
        {:ok, %__MODULE__{parameter_path: path, next_level: next}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end
