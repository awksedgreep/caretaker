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

    header_map = %{}

    header_map =
      case id do
        nil -> header_map
        id -> Map.put(header_map, "cwmp:ID", %{"@mustUnderstand" => "1", "#text" => id})
      end

    header_map =
      case Map.get(headers, :hold_requests) do
        true -> Map.put(header_map, "cwmp:HoldRequests", "1")
        false -> Map.put(header_map, "cwmp:HoldRequests", "0")
        _ -> header_map
      end

    header_map =
      case Map.get(headers, :no_more_requests) do
        true -> Map.put(header_map, "cwmp:NoMoreRequests", "1")
        false -> Map.put(header_map, "cwmp:NoMoreRequests", "0")
        _ -> header_map
      end

    header_map =
      case Map.get(headers, :session_timeout) do
        t when is_integer(t) and t >= 0 ->
          Map.put(header_map, "cwmp:SessionTimeout", Integer.to_string(t))

        _ ->
          header_map
      end

    header_xml =
      if map_size(header_map) == 0 do
        ""
      else
        {:ok, frag} = Lather.Xml.Builder.build_fragment(header_map)
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

        # Prefer a non-Fault element; fall back to the Fault element itself so
        # callers see rpc: "Fault" regardless of the SOAP prefix in use.
        keys = Map.keys(body)

        rpc_key =
          Enum.find(keys, fn k -> local_name(k) != "Fault" end) ||
            Enum.find(keys, fn k -> local_name(k) == "Fault" end)

        op = rpc_key && local_name(rpc_key)

        # Slice the RPC element out of the original document. Re-encoding the
        # parsed map would collapse repeated siblings (ParameterValueStruct,
        # string) into a single nested element. The element's prefix is
        # normalized to `cwmp:` so RPC decoders can rely on it.
        rpc_xml = rpc_key && slice_rpc(xml, rpc_key, body[rpc_key] || %{})

        {:ok,
         %{
           header: %{id: id_val, cwmp_ns: cwmp_ns},
           body: %{rpc: op, xml: rpc_xml, node: rpc_key && (body[rpc_key] || %{}), key: rpc_key}
         }}
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

  defp slice_rpc(xml, key, node) do
    escaped = Regex.escape(key)

    case Regex.run(~r/<#{escaped}(?:\s[^>]*)?(?:\/>|>.*?<\/#{escaped}\s*>)/s, xml) do
      [frag] ->
        normalize_prefix(frag, key)

      _ ->
        case Lather.Xml.Builder.build_fragment(%{key => node}) do
          {:ok, frag} -> frag
          _ -> nil
        end
    end
  end

  defp normalize_prefix(frag, key) do
    case String.split(key, ":") do
      [prefix, local] when prefix != "cwmp" ->
        frag
        |> String.replace("<" <> key, "<cwmp:" <> local)
        |> String.replace("</" <> key, "</cwmp:" <> local)

      [_local] ->
        frag

      _ ->
        frag
    end
  end

  @doc "Return the local (unprefixed) name of an XML element key."
  @spec local_name(String.t()) :: String.t()
  def local_name(key) when is_binary(key), do: key |> String.split(":") |> List.last()

  @doc "True when the decoded envelope body carries a SOAP Fault."
  @spec fault?(%{body: map()}) :: boolean()
  def fault?(%{body: %{rpc: "Fault"}}), do: true
  def fault?(_), do: false
end
