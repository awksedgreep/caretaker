defmodule Caretaker.CWMP.SOAPTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.InformResponse

  test "encode_envelope wraps body with SOAP 1.1 and cwmp header id" do
    {:ok, body} = InformResponse.encode(%InformResponse{max_envelopes: 1})

    {:ok, xml} = SOAP.encode_envelope(body, %{id: "abc123", cwmp_ns: "urn:dslforum-org:cwmp-1-0"})
    xml = IO.iodata_to_binary(xml)

    assert xml =~ ~s|<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"|
    assert xml =~ ~s|xmlns:cwmp="urn:dslforum-org:cwmp-1-0"|
    assert xml =~ ~s|<soapenv:Header><cwmp:ID mustUnderstand="1">abc123</cwmp:ID></soapenv:Header>|
    assert xml =~ ~s|<soapenv:Body><cwmp:InformResponse><MaxEnvelopes>1</MaxEnvelopes></cwmp:InformResponse></soapenv:Body>|
  end

  test "decode_envelope extracts id, cwmp_ns, and rpc local-name" do
    xml = """
    <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:cwmp="urn:dslforum-org:cwmp-1-0">
      <soapenv:Header>
        <cwmp:ID mustUnderstand="1">xyz</cwmp:ID>
      </soapenv:Header>
      <soapenv:Body>
        <cwmp:InformResponse><MaxEnvelopes>2</MaxEnvelopes></cwmp:InformResponse>
      </soapenv:Body>
    </soapenv:Envelope>
    """

    assert {:ok, %{header: %{id: "xyz", cwmp_ns: ns}, body: %{rpc: rpc, xml: body_xml}}} = SOAP.decode_envelope(xml)
    assert ns == "urn:dslforum-org:cwmp-1-0"
    assert rpc == "InformResponse"
    assert body_xml =~ "<MaxEnvelopes>2</MaxEnvelopes>"
  end

  test "content_type returns SOAP 1.1 type" do
    assert SOAP.content_type() == "text/xml; charset=utf-8"
  end
end