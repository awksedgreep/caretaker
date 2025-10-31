defmodule Caretaker.TR069.QueuedTransfersTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{GetQueuedTransfers, GetQueuedTransfersResponse}

  test "GetQueuedTransfers request/response round-trip" do
    {:ok, body} = GetQueuedTransfers.encode(%GetQueuedTransfers{})
    {:ok, env} = SOAP.encode_envelope(body, %{id: "QT1"})
    {:ok, %{body: %{rpc: "GetQueuedTransfers", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %GetQueuedTransfers{}} = GetQueuedTransfers.decode(xml)

    resp = %{transfers: [%{command_key: "CK1", state: "Scheduled", is_download: true}]}
    {:ok, body2} = GetQueuedTransfersResponse.encode(resp)
    {:ok, env2} = SOAP.encode_envelope(body2, %{id: "QT2"})
    {:ok, %{body: %{rpc: "GetQueuedTransfersResponse", xml: xml2}}} = SOAP.decode_envelope(IO.iodata_to_binary(env2))
    assert {:ok, %{transfers: [got]}} = GetQueuedTransfersResponse.decode(xml2)
    assert got.command_key == "CK1"
    assert got.state == "Scheduled"
    assert got.is_download == true
  end
end