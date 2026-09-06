defmodule Caretaker.Integration.ACSInboundAuthTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias Caretaker.ACS.Server
  alias Caretaker.HTTP.Auth, as: Client

  @inform File.read!("test/fixtures/tr069/inform.xml")

  setup do
    start_supervised!(Caretaker.PubSub)
    :ok
  end

  defp post(body, headers, opts) do
    conn =
      conn(:post, "/cwmp", body)
      |> Plug.Conn.put_req_header("content-type", "text/xml")

    conn = Enum.reduce(headers, conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
    Server.call(conn, Server.init(opts))
  end

  test "no auth configured: Informs are accepted unauthenticated (default)" do
    conn = post(@inform, [], [])
    assert conn.status == 200
  end

  test "basic auth: unauthenticated Inform is challenged with 401" do
    conn = post(@inform, [], auth: %{scheme: :basic, realm: "acs", username: "u", password: "p"})

    assert conn.status == 401
    assert ["Basic realm=\"acs\""] = Plug.Conn.get_resp_header(conn, "www-authenticate")
  end

  test "basic auth: correct credentials are accepted" do
    conn =
      post(@inform, [{"authorization", Client.basic("u", "p")}],
        auth: %{scheme: :basic, realm: "acs", username: "u", password: "p"}
      )

    assert conn.status == 200
  end

  test "digest auth: challenge then a valid response is accepted" do
    # Prepare once (a single mount): the stateless nonce secret must be stable
    # between issuing the challenge and verifying the response.
    config = Caretaker.ACS.Auth.prepare(%{scheme: :digest, realm: "acs", username: "u", password: "p"})

    challenged = post(@inform, [], auth: config)
    assert challenged.status == 401
    [challenge] = Plug.Conn.get_resp_header(challenged, "www-authenticate")
    assert challenge =~ "Digest"

    auth = Client.authorization(challenge, %{username: "u", password: "p"}, :post, "/cwmp")
    conn = post(@inform, [{"authorization", auth}], auth: config)
    assert conn.status == 200
  end

  test "the broadcast Inform carries the CPE source IP" do
    Caretaker.ACS.subscribe_informs()
    conn = post(@inform, [], [])
    assert conn.status == 200

    assert_receive {:caretaker_inform, inform}, 500
    assert inform.source_ip == "127.0.0.1"
  end
end
