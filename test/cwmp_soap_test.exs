defmodule Caretaker.CWMP.SOAPTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{Inform, InformResponse}

  test "encode_envelope wraps body with SOAP 1.1 and cwmp header id" do
    {:ok, body} = InformResponse.encode(%InformResponse{max_envelopes: 1})

    {:ok, xml} = SOAP.encode_envelope(body, %{id: "abc123", cwmp_ns: "urn:dslforum-org:cwmp-1-0"})
    xml = IO.iodata_to_binary(xml)

    assert xml =~ ~s|<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"|
    assert xml =~ ~s|xmlns:cwmp="urn:dslforum-org:cwmp-1-0"|

    assert xml =~
             ~s|<soapenv:Header><cwmp:ID mustUnderstand="1">abc123</cwmp:ID></soapenv:Header>|

    assert xml =~
             ~s|<soapenv:Body><cwmp:InformResponse><MaxEnvelopes>1</MaxEnvelopes></cwmp:InformResponse></soapenv:Body>|
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

    assert {:ok, %{header: %{id: "xyz", cwmp_ns: ns}, body: %{rpc: rpc, xml: body_xml}}} =
             SOAP.decode_envelope(xml)

    assert ns == "urn:dslforum-org:cwmp-1-0"
    assert rpc == "InformResponse"
    assert body_xml =~ "<MaxEnvelopes>2</MaxEnvelopes>"
  end

  test "decode_envelope re-injects ancestor xmlns declarations onto the sliced RPC" do
    # Real CPEs declare soap-enc/xsi/xsd on the Envelope and reference them from
    # inside the RPC element; the sliced fragment must still parse standalone.
    xml = """
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soap-enc="http://schemas.xmlsoap.org/soap/encoding/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:cwmp="urn:dslforum-org:cwmp-1-2">
      <soap:Header><cwmp:ID soap:mustUnderstand="1">42</cwmp:ID></soap:Header>
      <soap:Body>
        <cwmp:Inform>
          <DeviceId><Manufacturer>Acme</Manufacturer><OUI>001122</OUI><ProductClass>Router</ProductClass><SerialNumber>SN1</SerialNumber></DeviceId>
          <Event soap-enc:arrayType="cwmp:EventStruct[1]"><EventStruct><EventCode>2 PERIODIC</EventCode><CommandKey></CommandKey></EventStruct></Event>
          <MaxEnvelopes>1</MaxEnvelopes><CurrentTime>2026-01-01T00:00:00Z</CurrentTime><RetryCount>0</RetryCount>
          <ParameterList soap-enc:arrayType="cwmp:ParameterValueStruct[1]">
            <ParameterValueStruct><Name>Device.DeviceInfo.SoftwareVersion</Name><Value xsi:type="xsd:string">1.0</Value></ParameterValueStruct>
          </ParameterList>
        </cwmp:Inform>
      </soap:Body>
    </soap:Envelope>
    """

    assert {:ok, %{header: %{id: "42"}, body: %{rpc: "Inform", xml: body_xml}}} =
             SOAP.decode_envelope(xml)

    assert body_xml =~ ~s|xmlns:soap-enc="http://schemas.xmlsoap.org/soap/encoding/"|
    assert body_xml =~ ~s|xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"|
    assert body_xml =~ ~s|xmlns:xsd="http://www.w3.org/2001/XMLSchema"|

    assert {:ok, %Inform{} = inform} = Inform.decode(body_xml)
    assert inform.device_id.serial_number == "SN1"
    assert inform.events == ["2 PERIODIC"]

    assert [%{name: "Device.DeviceInfo.SoftwareVersion", value: "1.0", type: "xsd:string"}] =
             inform.parameter_list
  end

  test "content_type returns SOAP 1.1 type" do
    assert SOAP.content_type() == "text/xml; charset=utf-8"
  end
end
