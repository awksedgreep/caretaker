defmodule Caretaker.ACS.ServerFlowTest do
  use ExUnit.Case, async: false
  import Plug.Test

  test "Inform then empty POST returns queued GetParameterValues then 204" do
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)

    inform_xml = File.read!("test/fixtures/tr069/inform.xml")

    # 1) Inform request
    conn1 = conn(:post, "/cwmp", inform_xml)
    conn1 = Caretaker.ACS.Server.call(conn1, Caretaker.ACS.Server.init([]))
    assert conn1.status == 200
    assert conn1.resp_body =~ "<cwmp:InformResponse>"

    # 2) Empty POST should pop queued GPV
    conn2 = conn(:post, "/cwmp", "")
    conn2 = Caretaker.ACS.Server.call(conn2, Caretaker.ACS.Server.init([]))
    assert conn2.status == 200
    assert conn2.resp_body =~ "<cwmp:GetParameterValues>"
    assert conn2.resp_body =~ "Device.DeviceInfo."

    # 3) Next empty POST should be 204
    conn3 = conn(:post, "/cwmp", "")
    conn3 = Caretaker.ACS.Server.call(conn3, Caretaker.ACS.Server.init([]))
    assert conn3.status == 204
  end
end
