defmodule Caretaker.TR069.DownloadRoundtripTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{Download, DownloadResponse}

  test "Download encode/decode round-trip" do
    d =
      Download.new(
        command_key: "FW-123",
        file_type: "1 Firmware",
        url: "http://example/fw.bin",
        username: "u",
        password: "p",
        file_size: 1024,
        target_file_name: "fw.bin",
        delay_seconds: 5,
        success_url: "http://ok",
        failure_url: "http://bad"
      )

    {:ok, body} = Download.encode(d)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "X", cwmp_ns: "urn:dslforum-org:cwmp-1-0"})

    {:ok, %{body: %{rpc: "Download", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %Download{} = back} = Download.decode(xml)
    assert back.command_key == "FW-123"
    assert back.file_size == 1024
    assert back.delay_seconds == 5
  end

  test "DownloadResponse encode/decode" do
    r = DownloadResponse.new(status: 1, start_time: "2020-01-01T00:00:00Z", complete_time: "2020-01-01T00:05:00Z")
    {:ok, body} = DownloadResponse.encode(r)
    {:ok, %{body: %{rpc: "DownloadResponse", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(elem(SOAP.encode_envelope(body, %{id: "Y"}), 1)))
    assert {:ok, %DownloadResponse{} = back} = DownloadResponse.decode(xml)
    assert back.status == 1
  end
end