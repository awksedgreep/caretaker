defmodule Caretaker.TR069.RPC.AddObject do
  @moduledoc """
  TR-069 AddObject RPC (encode of request body).
  """

  @enforce_keys [:object_name]
  defstruct [:object_name, parameter_key: ""]

  @type t :: %__MODULE__{object_name: String.t(), parameter_key: String.t()}

  @spec new(String.t(), keyword()) :: t()
  def new(object_name, opts \\ []),
    do: %__MODULE__{
      object_name: object_name,
      parameter_key: Keyword.get(opts, :parameter_key, "")
    }

  @doc "Encode body element (without SOAP Envelope)"
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{object_name: name, parameter_key: key}) do
    {:ok,
     [
       "<cwmp:AddObject>",
       "<ObjectName>",
       name,
       "</ObjectName>",
       "<ParameterKey>",
       key,
       "</ParameterKey>",
       "</cwmp:AddObject>"
     ]}
  end

  @doc "Decode body element from XML"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}
        node = root["cwmp:AddObject"] || root["AddObject"] || %{}
        object_name = node["ObjectName"] || ""
        parameter_key = node["ParameterKey"] || ""

        {:ok, %__MODULE__{object_name: object_name, parameter_key: parameter_key}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end
