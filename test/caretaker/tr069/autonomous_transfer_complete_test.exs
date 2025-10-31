defmodule Caretaker.TR069.AutonomousTransferCompleteTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{AutonomousTransferComplete, AutonomousTransferCompleteResponse}

  test "AutonomousTransferComplete encode/decode and response" do
    t = AutonomousTransferComplete.new(
      command_key: "CKA",
      start_time: "2020-01-01T00:00:00Z",
      complete_time: "2020-01-01T00:05:00Z",
      is_download: true,
      file_type: "1 Firmware",
      fault_code: 0,
      fault_string: ""
    )

    {:ok, body} = AutonomousTransferComplete.encode(t)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "AT1"})
    {:ok, %{body: %{rpc: "AutonomousTransferComplete", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %AutonomousTransferComplete{} = back} = AutonomousTransferComplete.decode(xml)
    assert back.command_key == "CKA"
    assert back.is_download == true
    assert back.file_type == "1 Firmware"

    {:ok, body2} = AutonomousTransferCompleteResponse.encode(%AutonomousTransferCompleteResponse{})
    {:ok, env2} = SOAP.encode_envelope(body2, %{id: "AT2"})
    {:ok, %{body: %{rpc: "AutonomousTransferCompleteResponse", xml: xml2}}} = SOAP.decode_envelope(IO.iodata_to_binary(env2))
    assert {:ok, %AutonomousTransferCompleteResponse{}} = AutonomousTransferCompleteResponse.decode(xml2)
  end
end