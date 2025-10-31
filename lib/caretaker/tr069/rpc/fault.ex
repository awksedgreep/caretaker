defmodule Caretaker.TR069.RPC.Fault do
  @moduledoc """
  CWMP Fault decoder (parses SOAP Fault detail or cwmp:Fault element).
  """

  @enforce_keys [:code, :string]
  defstruct [:code, :string]

  @type t :: %__MODULE__{code: String.t(), string: String.t()}

  @doc "Decode cwmp:Fault or SOAP Fault into struct"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    import SweetXml

    try do
      doc = SweetXml.parse(xml)

      # Try cwmp:Fault first
      code = xpath(doc, ~x"//*[local-name()='FaultCode']/text()"s)
      str = xpath(doc, ~x"//*[local-name()='FaultString']/text()"s)

      {code, str} =
        case {code, str} do
          {nil, nil} ->
            # Try SOAP Fault (fallback with XPath then regex)
            xcode = xpath(doc, ~x"//*[local-name()='faultcode']/text()"s)
            xstr = xpath(doc, ~x"//*[local-name()='faultstring']/text()"s)
            cond do
              xcode && xstr -> {xcode, xstr}
              true ->
                rc = with [_, c] <- Regex.run(~r/<faultcode>([^<]+)<\/faultcode>/, xml), do: c
                rs = with [_, s] <- Regex.run(~r/<faultstring>([^<]+)<\/faultstring>/, xml), do: s
                {rc, rs}
            end

          other -> other
        end

      code = code || ""
      str = str || ""
      {:ok, %__MODULE__{code: code, string: str}}
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end
end
