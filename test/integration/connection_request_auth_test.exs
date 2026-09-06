defmodule Caretaker.Integration.ConnectionRequestAuthTest do
  @moduledoc "Tasks.connection_request answering a digest-protected CPE (#41)."
  use ExUnit.Case, async: false

  alias Caretaker.ACS.{Auth, Tasks}

  @device %{oui: "AABBCC", product_class: "Router", serial_number: "SN-CR"}

  # A CPE stub whose ConnectionRequestURL requires digest auth.
  defmodule CPE do
    import Plug.Conn

    def init(config), do: config

    def call(conn, config) do
      header =
        case get_req_header(conn, "authorization") do
          [v | _] -> v
          [] -> nil
        end

      if Auth.verify(header, "GET", conn.request_path, config) do
        send_resp(conn, 200, "ok")
      else
        conn
        |> put_resp_header("www-authenticate", Auth.challenge(config))
        |> send_resp(401, "unauthorized")
      end
    end
  end

  setup do
    port = 7600 + rem(System.unique_integer([:positive]), 300)
    config = Auth.prepare(%{scheme: :digest, realm: "cpe", username: "acs", password: "pw"})

    start_supervised!(Caretaker.PubSub)
    start_supervised!(Caretaker.ACS.Session)
    start_supervised!(Caretaker.ACS.Tasks)
    _ = start_supervised({Finch, name: Caretaker.Finch})
    start_supervised!({Bandit, plug: {CPE, config}, port: port})

    # Teach the ACS the device's ConnectionRequestURL via an Inform.
    inform = %Caretaker.TR069.RPC.Inform{
      device_id: @device,
      events: ["1 BOOT"],
      max_envelopes: 1,
      current_time: "",
      retry_count: 0,
      parameter_list: [
        %{
          name: "Device.ManagementServer.ConnectionRequestURL",
          value: "http://127.0.0.1:#{port}/cr",
          type: "xsd:string"
        }
      ]
    }

    Caretaker.PubSub.broadcast(Caretaker.PubSub.topic_tr069_inform(), inform)
    assert eventually(fn -> Tasks.presence(@device)["connection_request_url"] != nil end)
    :ok
  end

  test "with correct digest credentials the session is established" do
    result = Tasks.connection_request(@device, username: "acs", password: "pw", scheme: :digest)
    assert result == %{"requested" => true, "session_established" => true}
  end

  test "with no credentials the digest-protected CPE reports auth_required" do
    result = Tasks.connection_request(@device)
    assert result["requested"] == true
    assert result["session_established"] == false
    assert result["reason"] == "auth_required"
  end

  test "with wrong credentials the session is not established" do
    result = Tasks.connection_request(@device, username: "acs", password: "wrong", scheme: :digest)
    assert result["session_established"] == false
  end

  defp eventually(fun, retries \\ 50) do
    cond do
      fun.() -> true
      retries == 0 -> false
      true -> Process.sleep(20); eventually(fun, retries - 1)
    end
  end
end
