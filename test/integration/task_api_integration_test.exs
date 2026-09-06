defmodule Caretaker.Integration.TaskAPITest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias Caretaker.ACS.{API, Tasks}

  @device_id "AABBCC-Router-SN-100"

  setup do
    start_supervised!(Caretaker.PubSub)
    start_supervised!(Caretaker.ACS.Session)
    start_supervised!(Caretaker.ACS.Tasks)
    :ok
  end

  defp call(method, path, body \\ nil) do
    conn =
      if body do
        conn(method, path, Jason.encode!(body)) |> Plug.Conn.put_req_header("content-type", "application/json")
      else
        conn(method, path)
      end

    API.call(conn, API.init([]))
  end

  defp body(conn), do: Jason.decode!(conn.resp_body)

  test "submit set-parameters returns 202 and a queued task_id" do
    conn =
      call(:post, "/api/v1/devices/#{@device_id}/tasks/set-parameters", %{
        "parameters" => [%{"path" => "Device.WiFi.SSID.1.SSID", "value" => "net"}],
        "ttl_seconds" => 3600,
        "tag" => "pass-1"
      })

    assert conn.status == 202
    assert %{"task_id" => task_id, "state" => "queued"} = body(conn)

    # status endpoint reflects it
    status = call(:get, "/api/v1/tasks/#{task_id}") |> body()
    assert status["state"] == "queued"
    assert status["type"] == "set"
    assert status["device_id"] == @device_id
  end

  test "get-parameters, status, and cancel round-trip over HTTP" do
    conn = call(:post, "/api/v1/devices/#{@device_id}/tasks/get-parameters", %{"paths" => ["Device.DeviceInfo."]})
    assert conn.status == 202
    task_id = body(conn)["task_id"]

    del = call(:delete, "/api/v1/tasks/#{task_id}")
    assert del.status == 200
    assert body(del)["state"] == "cancelled"

    assert call(:get, "/api/v1/tasks/#{task_id}") |> body() |> Map.get("state") == "cancelled"
  end

  test "unknown task is 404" do
    assert call(:get, "/api/v1/tasks/tsk_nope").status == 404
  end

  test "bad device id is 400" do
    conn = call(:post, "/api/v1/devices/bogus/tasks/get-parameters", %{"paths" => ["Device."]})
    assert conn.status == 400
    assert body(conn)["error"] == "invalid_device_id"
  end

  test "idempotency: repeat returns same id, conflicting payload is 409" do
    p = %{"parameters" => [%{"path" => "Device.X", "value" => "1"}], "idempotency_key" => "k9"}
    id1 = call(:post, "/api/v1/devices/#{@device_id}/tasks/set-parameters", p) |> body() |> Map.get("task_id")
    id2 = call(:post, "/api/v1/devices/#{@device_id}/tasks/set-parameters", p) |> body() |> Map.get("task_id")
    assert id1 == id2

    conflict =
      call(:post, "/api/v1/devices/#{@device_id}/tasks/set-parameters", %{
        "parameters" => [%{"path" => "Device.Y", "value" => "2"}],
        "idempotency_key" => "k9"
      })

    assert conflict.status == 409
  end

  test "batch submit reports per-device task ids and partial failures" do
    conn =
      call(:post, "/api/v1/tasks/batch", %{
        "tag" => "pass-batch",
        "tasks" => [
          %{"device_id" => @device_id, "paths" => ["Device.DeviceInfo."]},
          %{"device_id" => "AABBCC-Router-SN-101", "parameters" => [%{"path" => "Device.X", "value" => "1"}]},
          %{"device_id" => "bogus", "paths" => ["Device."]}
        ]
      })

    assert conn.status == 202
    b = body(conn)
    assert b["accepted"] == 2
    assert b["rejected"] == 1

    # the kill switch cancels the whole batch by tag
    cancel = call(:post, "/api/v1/tasks/cancel", %{"tag" => "pass-batch"}) |> body()
    assert cancel["cancelled"] == 2
  end

  test "presence for an unseen device is not reachable; limits are documented" do
    presence = call(:get, "/api/v1/devices/#{@device_id}/presence") |> body()
    assert presence["reachable"] == false
    assert presence["last_inform"] == nil

    limits = call(:get, "/api/v1/limits") |> body()
    assert is_integer(limits["tasks_per_second"])
    assert is_integer(limits["default_ttl_seconds"])
  end

  test "rate limit returns 429 with Retry-After" do
    stop_supervised(Caretaker.ACS.Tasks)
    start_supervised!({Caretaker.ACS.Tasks, rate_limit: 1})

    ok = call(:post, "/api/v1/devices/#{@device_id}/tasks/get-parameters", %{"paths" => ["Device."]})
    assert ok.status == 202

    limited = call(:post, "/api/v1/devices/#{@device_id}/tasks/get-parameters", %{"paths" => ["Device."]})
    assert limited.status == 429
    assert [_ | _] = Plug.Conn.get_resp_header(limited, "retry-after")
  end
end
