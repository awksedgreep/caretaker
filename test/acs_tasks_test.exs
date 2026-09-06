defmodule Caretaker.ACS.TasksTest do
  use ExUnit.Case, async: false

  alias Caretaker.ACS.{Session, Tasks}

  @device %{oui: "AABBCC", product_class: "Router", serial_number: "SN-1"}
  @dev_key {"AABBCC", "Router", "SN-1"}

  setup do
    start_supervised!(Caretaker.PubSub)
    start_supervised!(Session)
    start_supervised!(Tasks)
    :ok
  end

  test "submit_set queues a task and a correlated command" do
    {:ok, task_id} = Tasks.submit_set(@device, [%{path: "Device.WiFi.SSID.1.SSID", value: "net"}])
    {:ok, task} = Tasks.get(task_id)

    assert task.state == :queued
    assert task.type == :set
    # the command is in the device's queue, tagged with the task's cwmp id
    assert {:ok, _cmd, %{id: cwmp_id}} = Session.next_command(@dev_key)
    assert cwmp_id == task.cwmp_id
  end

  test "get task lifecycle: queued -> delivered -> applied with results" do
    {:ok, task_id} = Tasks.submit_get(@device, ["Device.DeviceInfo."])
    {:ok, task} = Tasks.get(task_id)
    cid = task.cwmp_id

    Tasks.mark_delivered(cid)
    assert eventually(fn -> state(task_id) == :delivered end)

    Tasks.complete(cid, %{parameters: [%{name: "Device.DeviceInfo.Manufacturer", value: "Acme"}]})
    assert eventually(fn -> state(task_id) == :applied end)

    {:ok, done} = Tasks.get(task_id)
    assert done.result == %{"parameters" => %{"Device.DeviceInfo.Manufacturer" => "Acme"}}
    assert done.completed_at
  end

  test "a CPE fault drives the task to faulted with the raw code" do
    {:ok, task_id} = Tasks.submit_set(@device, [%{path: "Device.X", value: "1"}])
    {:ok, %{cwmp_id: cid}} = Tasks.get(task_id)

    Tasks.mark_delivered(cid)
    Tasks.fault(cid, %{code: "9006", message: "Invalid parameter type"})

    assert eventually(fn -> state(task_id) == :faulted end)
    {:ok, task} = Tasks.get(task_id)
    assert task.fault == %{code: "9006", message: "Invalid parameter type"}
  end

  test "cancel removes a queued task; a delivered one conflicts" do
    {:ok, a} = Tasks.submit_get(@device, ["Device."])
    assert {:ok, :cancelled} = Tasks.cancel(a)
    assert state(a) == :cancelled

    {:ok, b} = Tasks.submit_get(@device, ["Device."])
    {:ok, %{cwmp_id: cid}} = Tasks.get(b)
    Tasks.mark_delivered(cid)
    assert eventually(fn -> state(b) == :delivered end)
    assert {:error, {:already, :delivered}} = Tasks.cancel(b)
  end

  test "cancel_by_tag cancels every queued task with the tag" do
    {:ok, a} = Tasks.submit_get(@device, ["Device."], tag: "pass-9")
    {:ok, b} = Tasks.submit_get(@device, ["Device."], tag: "pass-9")
    {:ok, c} = Tasks.submit_get(@device, ["Device."], tag: "other")

    assert {:ok, 2} = Tasks.cancel_by_tag("pass-9")
    assert state(a) == :cancelled
    assert state(b) == :cancelled
    assert state(c) == :queued
  end

  test "idempotency: same key+payload returns the same task; different payload conflicts" do
    p = [%{path: "Device.X", value: "1"}]
    {:ok, id1} = Tasks.submit_set(@device, p, idempotency_key: "k1")
    {:ok, id2} = Tasks.submit_set(@device, p, idempotency_key: "k1")
    assert id1 == id2

    assert {:error, :idempotency_conflict} =
             Tasks.submit_set(@device, [%{path: "Device.Y", value: "2"}], idempotency_key: "k1")
  end

  test "a task past its TTL is swept to expired" do
    stop_supervised(Tasks)
    # tiny sweep-independent TTL: submit with ttl_ms 0, then the sweep marks it expired
    start_supervised!(Tasks)
    {:ok, id} = Tasks.submit_get(@device, ["Device."], ttl_ms: 0)
    send(Process.whereis(Tasks), :sweep)
    assert eventually(fn -> state(id) == :expired end)
  end

  test "submit without a running Session fails cleanly" do
    stop_supervised(Tasks)
    stop_supervised(Session)
    start_supervised!(Tasks)
    assert {:error, :session_unavailable} = Tasks.submit_get(@device, ["Device."])
  end

  test "device id string round-trips, tolerating dashes in the serial" do
    d = %{oui: "AABBCC", product_class: "Router", serial_number: "SN-12-34"}
    str = Tasks.device_id_string(d)
    assert {:ok, ^d} = Tasks.parse_device_id(str)
  end

  defp state(task_id) do
    case Tasks.get(task_id) do
      {:ok, t} -> t.state
      _ -> nil
    end
  end

  defp eventually(fun, retries \\ 50) do
    cond do
      fun.() -> true
      retries == 0 -> false
      true -> Process.sleep(10); eventually(fun, retries - 1)
    end
  end
end
