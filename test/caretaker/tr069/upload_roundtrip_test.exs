defmodule Caretaker.TR069.UploadRoundtripTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{Upload, UploadResponse}

  test "Upload encode/decode" do
    u = Upload.new(command_key: "CK", file_type: "3 VendorConfig", url: "http://ex/upload", delay_seconds: 10)
    {:ok, body} = Upload.encode(u)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "U1"})
    {:ok, %{body: %{rpc: "Upload", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %Upload{} = back} = Upload.decode(xml)
    assert back.command_key == "CK"
    assert back.delay_seconds == 10
  end

  test "UploadResponse encode/decode" do
    r = UploadResponse.new(status: 0, start_time: "", complete_time: "")
    {:ok, body} = UploadResponse.encode(r)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "U2"})
    {:ok, %{body: %{rpc: "UploadResponse", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %UploadResponse{}} = UploadResponse.decode(xml)
  end
end