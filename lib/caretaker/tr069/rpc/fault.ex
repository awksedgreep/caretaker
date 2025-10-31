defmodule Caretaker.TR069.RPC.Fault do
  @moduledoc """
  CWMP Fault decoder (parses SOAP Fault detail or cwmp:Fault element).
  """

  @enforce_keys [:code, :string]
  defstruct [:code, :string]

  @type t :: %__MODULE__{code: String.t(), string: String.t()}

  @doc "Decode cwmp:Fault or SOAP Fault into struct via Lather (no SweetXml/regex)"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped = "<root xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}

        # Prefer cwmp:Fault
        cf = root["cwmp:Fault"] || root["Fault"]
        {code, string} =
          cond do
            is_map(cf) ->
              {cf["FaultCode"] || "", cf["FaultString"] || ""}

            true ->
              # Try SOAP 1.1 Fault shape
              sf = root["soapenv:Fault"] || root["Fault"] || %{}
              {sf["faultcode"] || "", sf["faultstring"] || ""}
          end

        {:ok, %__MODULE__{code: code, string: string}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end
