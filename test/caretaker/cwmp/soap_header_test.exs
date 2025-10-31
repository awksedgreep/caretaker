defmodule Caretaker.CWMP.SOAPHeaderTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP

  test "encode_envelope mirrors cwmp ns and includes cwmp:ID with mustUnderstand=1" do
    {:ok, body} = Caretaker.TR069.RPC.InformResponse.encode(%Caretaker.TR069.RPC.InformResponse{max_envelopes: 1})
    {:ok, xml} = SOAP.encode_envelope(body, %{id: "ABC123", cwmp_ns: "urn:dslforum-org:cwmp-1-2"})
    bin = IO.iodata_to_binary(xml)

    assert bin =~ ~s/xmlns:cwmp="urn:dslforum-org:cwmp-1-2"/
    assert bin =~ ~s/<cwmp:ID mustUnderstand="1">ABC123<\/cwmp:ID>/
  end

  test "encode_envelope defaults cwmp ns to 1-0 when not provided" do
    {:ok, body} = Caretaker.TR069.RPC.InformResponse.encode(%Caretaker.TR069.RPC.InformResponse{max_envelopes: 1})
    {:ok, xml} = SOAP.encode_envelope(body, %{id: "X"})
    bin = IO.iodata_to_binary(xml)

    assert bin =~ ~s/xmlns:cwmp="urn:dslforum-org:cwmp-1-0"/
  end

  test "encode_envelope includes optional header flags when provided" do
    {:ok, body} = Caretaker.TR069.RPC.InformResponse.encode(%Caretaker.TR069.RPC.InformResponse{max_envelopes: 1})

    {:ok, xml} =
      SOAP.encode_envelope(body, %{
        id: "ID1",
        cwmp_ns: "urn:dslforum-org:cwmp-1-4",
        hold_requests: true,
        no_more_requests: false,
        session_timeout: 30
      })

    bin = IO.iodata_to_binary(xml)
    assert bin =~ ~s/<cwmp:HoldRequests>1<\/cwmp:HoldRequests>/
    assert bin =~ ~s/<cwmp:NoMoreRequests>0<\/cwmp:NoMoreRequests>/
    assert bin =~ ~s/<cwmp:SessionTimeout>30<\/cwmp:SessionTimeout>/
  end

  test "decode_envelope returns cwmp_ns and id from encoded envelope" do
    {:ok, body} = Caretaker.TR069.RPC.InformResponse.encode(%Caretaker.TR069.RPC.InformResponse{max_envelopes: 1})
    {:ok, xml} = SOAP.encode_envelope(body, %{id: "ID789", cwmp_ns: "urn:dslforum-org:cwmp-1-3"})

    assert {:ok, %{header: %{id: "ID789", cwmp_ns: "urn:dslforum-org:cwmp-1-3"}, body: %{rpc: "InformResponse"}}} =
             SOAP.decode_envelope(IO.iodata_to_binary(xml))
  end
end