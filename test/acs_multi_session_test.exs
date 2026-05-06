defmodule Caretaker.ACS.MultiSessionTest do
  use ExUnit.Case, async: false
  import Plug.Test

  test "separate IP sessions dequeue independently" do
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)

    xml1 = File.read!("test/fixtures/tr069/inform.xml")
    xml2 = File.read!("test/fixtures/tr069/inform2.xml")

    # IP1 Inform
    conn1 = conn(:post, "/cwmp", xml1)
    conn1 = %{conn1 | remote_ip: {10, 0, 0, 1}}
    conn1 = Caretaker.ACS.Server.call(conn1, Caretaker.ACS.Server.init([]))
    assert conn1.status == 200

    # IP2 Inform
    conn2 = conn(:post, "/cwmp", xml2)
    conn2 = %{conn2 | remote_ip: {10, 0, 0, 2}}
    conn2 = Caretaker.ACS.Server.call(conn2, Caretaker.ACS.Server.init([]))
    assert conn2.status == 200

    # Empty for IP1 -> GPV
    e1 = conn(:post, "/cwmp", "")
    e1 = %{e1 | remote_ip: {10, 0, 0, 1}}
    e1 = Caretaker.ACS.Server.call(e1, Caretaker.ACS.Server.init([]))
    assert e1.status == 200
    assert e1.resp_body =~ "<cwmp:GetParameterValues>"

    # Empty again for IP1 -> 204
    e1b = conn(:post, "/cwmp", "")
    e1b = %{e1b | remote_ip: {10, 0, 0, 1}}
    e1b = Caretaker.ACS.Server.call(e1b, Caretaker.ACS.Server.init([]))
    assert e1b.status == 204

    # Empty for IP2 -> GPV
    e2 = conn(:post, "/cwmp", "")
    e2 = %{e2 | remote_ip: {10, 0, 0, 2}}
    e2 = Caretaker.ACS.Server.call(e2, Caretaker.ACS.Server.init([]))
    assert e2.status == 200
    assert e2.resp_body =~ "<cwmp:GetParameterValues>"
  end

  test "same IP sessions dequeue independently when peer ports differ" do
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)

    shared_ip = {10, 0, 0, 1}
    xml1 = File.read!("test/fixtures/tr069/inform.xml")
    xml2 = File.read!("test/fixtures/tr069/inform2.xml")

    conn1 =
      conn(:post, "/cwmp", xml1)
      |> Map.put(:remote_ip, shared_ip)
      |> put_peer_data(%{address: shared_ip, port: 50_001, ssl_cert: nil})

    conn1 = Caretaker.ACS.Server.call(conn1, Caretaker.ACS.Server.init([]))
    assert conn1.status == 200

    conn2 =
      conn(:post, "/cwmp", xml2)
      |> Map.put(:remote_ip, shared_ip)
      |> put_peer_data(%{address: shared_ip, port: 50_002, ssl_cert: nil})

    conn2 = Caretaker.ACS.Server.call(conn2, Caretaker.ACS.Server.init([]))
    assert conn2.status == 200

    empty1 =
      conn(:post, "/cwmp", "")
      |> Map.put(:remote_ip, shared_ip)
      |> put_peer_data(%{address: shared_ip, port: 50_001, ssl_cert: nil})

    empty1 = Caretaker.ACS.Server.call(empty1, Caretaker.ACS.Server.init([]))
    assert empty1.status == 200
    assert empty1.resp_body =~ "<cwmp:GetParameterValues>"

    empty2 =
      conn(:post, "/cwmp", "")
      |> Map.put(:remote_ip, shared_ip)
      |> put_peer_data(%{address: shared_ip, port: 50_002, ssl_cert: nil})

    empty2 = Caretaker.ACS.Server.call(empty2, Caretaker.ACS.Server.init([]))
    assert empty2.status == 200
    assert empty2.resp_body =~ "<cwmp:GetParameterValues>"
  end
end
