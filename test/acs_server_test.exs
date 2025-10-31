defmodule Caretaker.ACS.ServerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  # import Plug.Conn

  test "POST /cwmp with empty body responds 204 and text/plain" do
    _ = start_supervised(Caretaker.ACS.Session)
    conn = conn(:post, "/cwmp", "")

    conn = Caretaker.ACS.Server.call(conn, Caretaker.ACS.Server.init([]))

    assert conn.status == 204
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/plain"]
    assert conn.resp_body == ""
  end

  test "POST /cwmp with Inform returns 200 and SOAP InformResponse and publishes inform" do
    _ = start_supervised(Caretaker.PubSub)

    xml = File.read!("test/fixtures/tr069/inform.xml")

    # Subscribe before request to capture broadcast
    Caretaker.PubSub.subscribe(Caretaker.PubSub.topic_tr069_inform())

    conn = conn(:post, "/cwmp", xml)
    conn = Caretaker.ACS.Server.call(conn, Caretaker.ACS.Server.init([]))

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == [Caretaker.CWMP.SOAP.content_type()]
    assert conn.resp_body =~ "<cwmp:InformResponse>"
    assert_receive {:pubsub, :tr069_inform, _inform}, 200
  end

  test "malformed SOAP returns 400" do
    _ = start_supervised(Caretaker.PubSub)
    xml = """
    <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
      <soapenv:Body>
        <bad/>
      </soapenv:Body>
    </soapenv:Envelope>
    """
    conn = conn(:post, "/cwmp", xml)
    conn = Caretaker.ACS.Server.call(conn, Caretaker.ACS.Server.init([]))
    assert conn.status == 400
  end

  test "unsupported content-type returns 415" do
    try do
      conn =
        conn(:post, "/cwmp", "<xml/>")
        |> Plug.Conn.put_req_header("content-type", "application/json")

      conn = Caretaker.ACS.Server.call(conn, Caretaker.ACS.Server.init([]))
      assert conn.status == 415
    catch
      {:halt, conn} -> assert conn.status == 415
    end
  end

  test "unknown RPC returns 400" do
    _ = start_supervised(Caretaker.PubSub)
    body = "<cwmp:UnknownFoo/>"

    {:ok, env} =
      Caretaker.CWMP.SOAP.encode_envelope(body, %{id: "X", cwmp_ns: "urn:dslforum-org:cwmp-1-0"})

    conn = conn(:post, "/cwmp", IO.iodata_to_binary(env))
    conn = Caretaker.ACS.Server.call(conn, Caretaker.ACS.Server.init([]))
    assert conn.status == 400
  end

  test "child_spec returns Bandit with proper defaults and overrides" do
    # Defaults
    assert {Bandit, opts} = Caretaker.ACS.Server.child_spec()
    assert Keyword.get(opts, :plug) == Caretaker.ACS.Server
    assert Keyword.get(opts, :port) == 4000
    assert Keyword.get(opts, :scheme) == :http

    # Overrides
    assert {Bandit, opts2} = Caretaker.ACS.Server.child_spec(port: 1234, scheme: :https)
    assert Keyword.get(opts2, :plug) == Caretaker.ACS.Server
    assert Keyword.get(opts2, :port) == 1234
    assert Keyword.get(opts2, :scheme) == :https
  end
end
