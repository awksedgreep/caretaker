defmodule Caretaker.TR069.CancelTransferTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{CancelTransfer, CancelTransferResponse}

  test "CancelTransfer encode/decode and response" do
    c = CancelTransfer.new(command_key: "CKC")
    {:ok, body} = CancelTransfer.encode(c)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "CT1"})
    {:ok, %{body: %{rpc: "CancelTransfer", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %CancelTransfer{command_key: "CKC"}} = CancelTransfer.decode(xml)

    {:ok, body2} = CancelTransferResponse.encode(%CancelTransferResponse{})
    {:ok, env2} = SOAP.encode_envelope(body2, %{id: "CT2"})
    {:ok, %{body: %{rpc: "CancelTransferResponse", xml: xml2}}} = SOAP.decode_envelope(IO.iodata_to_binary(env2))
    assert {:ok, %CancelTransferResponse{}} = CancelTransferResponse.decode(xml2)
  end
end