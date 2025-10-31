defmodule Caretaker.TR069.RPC.FaultTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.Fault

  test "decode cwmp Fault" do
    xml = """
    <cwmp:Fault xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">
      <FaultCode>9003</FaultCode>
      <FaultString>Invalid arguments</FaultString>
    </cwmp:Fault>
    """

    assert {:ok, %Fault{code: "9003", string: "Invalid arguments"}} = Fault.decode(xml)
  end

  test "decode SOAP Fault" do
    xml = """
    <soapenv:Fault xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\">
      <faultcode>Client</faultcode>
      <faultstring>Version Mismatch</faultstring>
    </soapenv:Fault>
    """

    assert {:ok, %Fault{}} = Fault.decode(xml)
  end
end
