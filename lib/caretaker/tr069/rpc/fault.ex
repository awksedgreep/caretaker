defmodule Caretaker.TR069.RPC.Fault do
  @moduledoc """
  CWMP Fault encoder/decoder (SOAP Fault carrying a cwmp:Fault detail).
  """

  @enforce_keys [:code, :string]
  defstruct [:code, :string, faultcode: "Client", faultstring: "CWMP fault"]

  @type t :: %__MODULE__{
          code: String.t(),
          string: String.t(),
          faultcode: String.t(),
          faultstring: String.t()
        }

  @doc """
  Build a Fault. `faultcode` is the SOAP-level code: `"Client"` for faults
  raised by the CPE and `"Server"` for faults raised by the ACS.
  """
  @spec new(String.t() | integer(), String.t(), keyword()) :: t()
  def new(code, string, opts \\ []) do
    %__MODULE__{
      code: to_string(code),
      string: string,
      faultcode: Keyword.get(opts, :faultcode, "Client"),
      faultstring: Keyword.get(opts, :faultstring, "CWMP fault")
    }
  end

  @doc "Encode a SOAP 1.1 Fault body element carrying the cwmp:Fault detail."
  @spec encode(t()) :: {:ok, iodata()}
  def encode(%__MODULE__{} = f) do
    map = %{
      "soapenv:Fault" => %{
        "faultcode" => "soapenv:" <> f.faultcode,
        "faultstring" => f.faultstring,
        "detail" => %{
          "cwmp:Fault" => %{"FaultCode" => f.code, "FaultString" => f.string}
        }
      }
    }

    Lather.Xml.Builder.build_fragment(map)
  end

  @doc "Decode cwmp:Fault or SOAP Fault into struct via Lather"
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) when is_binary(xml) do
    try do
      wrapped =
        "<root xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <>
          xml <> "</root>"

      with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
        root = parsed["root"] || %{}

        sf =
          root["soapenv:Fault"] || root["soap:Fault"] || root["SOAP-ENV:Fault"] ||
            root["Fault"] || %{}

        # Prefer a top-level cwmp:Fault, then the one nested in the SOAP detail
        cf = root["cwmp:Fault"] || get_in(sf, ["detail", "cwmp:Fault"]) || get_in(sf, ["detail", "Fault"])

        {code, string} =
          if is_map(cf) do
            {text(cf["FaultCode"]), text(cf["FaultString"])}
          else
            # Plain SOAP fault without cwmp detail; fall back to its fields
            {text(sf["faultcode"]), text(sf["faultstring"])}
          end

        {:ok,
         %__MODULE__{
           code: code,
           string: string,
           faultcode: sf["faultcode"] |> text() |> strip_prefix(),
           faultstring: text(sf["faultstring"])
         }}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    end
  end

  defp text(%{"#text" => v}) when is_binary(v), do: v
  defp text(v) when is_binary(v), do: v
  defp text(_), do: ""

  defp strip_prefix(""), do: "Client"
  defp strip_prefix(v), do: v |> String.split(":") |> List.last()
end
