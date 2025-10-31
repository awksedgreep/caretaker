defmodule Caretaker.TR069.TransferCompleteTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{TransferComplete, TransferCompleteResponse}

  test "TransferComplete encode/decode" do
    t = TransferComplete.new(
      command_key: "FW-123",
      start_time: "2020-01-01T00:00:00Z",
      complete_time: "2020-01-01T00:05:00Z",
      fault_code: 0,
      fault_string: ""
    )

    {:ok, body} = TransferComplete.encode(t)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "T1"})
    {:ok, %{body: %{rpc: "TransferComplete", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %TransferComplete{} = back} = TransferComplete.decode(xml)
    assert back.command_key == "FW-123"
    assert back.fault_code == 0
  end

  test "TransferCompleteResponse encode/decode" do
    {:ok, body} = TransferCompleteResponse.encode(%TransferCompleteResponse{})
    {:ok, env} = SOAP.encode_envelope(body, %{id: "T2"})
    {:ok, %{body: %{rpc: "TransferCompleteResponse", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %TransferCompleteResponse{}} = TransferCompleteResponse.decode(xml)
  end
end