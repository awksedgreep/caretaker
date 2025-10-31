defmodule Caretaker.TR069.ScheduleDownloadTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{ScheduleDownload, ScheduleDownloadResponse}

  test "ScheduleDownload encode/decode with time windows and response" do
    s =
      ScheduleDownload.new(
        command_key: "CKSD",
        file_type: "1 Firmware",
        url: "http://host/fw.bin",
        username: "u",
        password: "p",
        file_size: 2048,
        target_file_name: "fw.bin",
        time_windows: [
          %{start_time: "2020-01-01T00:00:00Z", end_time: "2020-01-01T02:00:00Z", window_mode: "Normal"}
        ]
      )

    {:ok, body} = ScheduleDownload.encode(s)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "SD1"})
    {:ok, %{body: %{rpc: "ScheduleDownload", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %ScheduleDownload{} = back} = ScheduleDownload.decode(xml)
    assert back.command_key == "CKSD"
    assert length(back.time_windows) >= 1
    [tw | _] = back.time_windows
    assert tw.start_time == "2020-01-01T00:00:00Z"
    assert tw.window_mode == "Normal"

    r = ScheduleDownloadResponse.new(status: 1, start_time: "", complete_time: "")
    {:ok, body2} = ScheduleDownloadResponse.encode(r)
    {:ok, env2} = SOAP.encode_envelope(body2, %{id: "SD2"})
    {:ok, %{body: %{rpc: "ScheduleDownloadResponse", xml: xml2}}} = SOAP.decode_envelope(IO.iodata_to_binary(env2))
    assert {:ok, %ScheduleDownloadResponse{status: 1}} = ScheduleDownloadResponse.decode(xml2)
  end
end