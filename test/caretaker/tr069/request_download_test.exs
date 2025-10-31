defmodule Caretaker.TR069.RequestDownloadTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{RequestDownload, RequestDownloadResponse}

  test "RequestDownload encode/decode and response" do
    r = RequestDownload.new(file_type: "1 Firmware", file_type_arg: "vendor:arg")
    {:ok, body} = RequestDownload.encode(r)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "RD1"})
    {:ok, %{body: %{rpc: "RequestDownload", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %RequestDownload{file_type: "1 Firmware", file_type_arg: "vendor:arg"}} = RequestDownload.decode(xml)

    {:ok, body2} = RequestDownloadResponse.encode(%RequestDownloadResponse{status: 1})
    {:ok, env2} = SOAP.encode_envelope(body2, %{id: "RD2"})
    {:ok, %{body: %{rpc: "RequestDownloadResponse", xml: xml2}}} = SOAP.decode_envelope(IO.iodata_to_binary(env2))
    assert {:ok, %RequestDownloadResponse{status: 1}} = RequestDownloadResponse.decode(xml2)
  end
end