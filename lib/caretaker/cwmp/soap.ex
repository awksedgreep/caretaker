defmodule Caretaker.CWMP.SOAP do
  @moduledoc """
  Helpers for CWMP SOAP envelopes and headers.

  Spec-driven defaults:
  - SOAP 1.1 Envelope namespace: http://schemas.xmlsoap.org/soap/envelope/
  - Mirror CWMP namespace from CPE when known; default to urn:dslforum-org:cwmp-1-0
  - Always include cwmp:ID with mustUnderstand="1" when an ID is provided
  """

  @type cwmp_id :: String.t()
  @type header_opts :: %{
          optional(:id) => cwmp_id,
          optional(:cwmp_ns) => String.t(),
          optional(:hold_requests) => boolean(),
          optional(:no_more_requests) => boolean(),
          optional(:session_timeout) => non_neg_integer()
        }

  @soapenv "http://schemas.xmlsoap.org/soap/envelope/"
  @default_cwmp "urn:dslforum-org:cwmp-1-0"

  @doc "Encode a CWMP SOAP envelope from an RPC body fragment using Lather (SOAP 1.1)"
  @spec encode_envelope(iodata() | map(), header_opts()) :: {:ok, iodata()}
  def encode_envelope(body, headers \\ %{}) do
    cwmp_ns = Map.get(headers, :cwmp_ns, @default_cwmp)
    id = Map.get(headers, :id)

    body_xml =
      cond do
        is_map(body) ->
          {:ok, frag} = Lather.Xml.Builder.build_fragment(body)
          frag

        is_list(body) or is_binary(body) ->
          IO.iodata_to_binary(body)

        true ->
          ""
      end

    header_xml =
      case id do
        nil ->
          ""

        id ->
          {:ok, frag} =
            Lather.Xml.Builder.build_fragment(%{
              "cwmp:ID" => %{"@mustUnderstand" => "1", "#text" => id}
            })

          frag
      end

    # Minify fragments to avoid whitespace differences
    header_xml = Regex.replace(~r/>\s+</, header_xml, "><")
    body_xml = Regex.replace(~r/>\s+</, body_xml, "><")

    xml = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<soapenv:Envelope xmlns:soapenv=\"",
      @soapenv,
      "\" xmlns:cwmp=\"",
      cwmp_ns,
      "\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"",
      " xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"",
      ">",
      "<soapenv:Header>",
      header_xml,
      "</soapenv:Header>",
      "<soapenv:Body>",
      body_xml,
      "</soapenv:Body>",
      "</soapenv:Envelope>"
    ]

    {:ok, IO.iodata_to_binary(xml)}
  end

  @doc "Decode a CWMP SOAP envelope xml into header (id, cwmp_ns) and body (rpc local-name and raw xml) using Lather"
  @spec decode_envelope(binary()) :: {:ok, %{header: map(), body: map()}} | {:error, term()}
  def decode_envelope(xml) when is_binary(xml) do
    try do
      with {:ok, parsed} <- Lather.Xml.Parser.parse(xml) do
        env =
          parsed["soapenv:Envelope"] || parsed["SOAP-ENV:Envelope"] || parsed["s:Envelope"] ||
            parsed["soap:Envelope"] || parsed["Envelope"] || %{}

        cwmp_ns = env["@xmlns:cwmp"] || @default_cwmp

        header =
          env["soapenv:Header"] || env["SOAP-ENV:Header"] || env["s:Header"] || env["soap:Header"] ||
            env["Header"] || %{}

        id_val =
          case header["cwmp:ID"] do
            %{"#text" => v} -> v
            v when is_binary(v) -> v
            _ -> nil
          end

        body =
          env["soapenv:Body"] || env["SOAP-ENV:Body"] || env["s:Body"] || env["soap:Body"] ||
            env["Body"] || %{}

        rpc_key =
          body
          |> Map.keys()
          |> Enum.find(fn k -> k not in ["soap:Fault", "Fault"] end)

        op = rpc_key && String.split(rpc_key, ":") |> List.last()

        # Rebuild RPC fragment using Lather builder to avoid regex fragility
        rpc_xml =
          case rpc_key do
            nil -> nil
            key ->
              node = body[key] || %{}

              case Lather.Xml.Builder.build_fragment(%{key => node}) do
                {:ok, frag} -> frag
                _ -> nil
              end
          end

        {:ok, %{header: %{id: id_val, cwmp_ns: cwmp_ns}, body: %{rpc: op, xml: rpc_xml, node: (rpc_key && (body[rpc_key] || %{})), key: rpc_key}}}
      end
    rescue
      e -> {:error, {:decode_failed, e}}
    catch
      :exit, reason -> {:error, {:decode_failed, reason}}
    end
  end

  @doc "CWMP SOAP content type"
  @spec content_type() :: String.t()
  def content_type, do: "text/xml; charset=utf-8"

  # -- internal helpers --
end
