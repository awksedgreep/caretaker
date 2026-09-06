defmodule Caretaker.Integration.TaskLifecycleTest do
  @moduledoc """
  End-to-end: a task submitted to the registry is delivered to a device through
  a real CWMP session (ACS.Server + CPE.Client) and driven to a terminal state
  with the CPE's results, proving cwmp:ID correlation across the session.
  """
  use ExUnit.Case, async: false

  alias Caretaker.ACS.Tasks
  alias Caretaker.CPE.{Client, DeviceState}

  @device_id %{oui: "AABBCC", product_class: "Router", serial_number: "SN-E2E"}

  setup do
    port = 4000 + rem(System.unique_integer([:positive]), 1000)
    start_supervised!(Caretaker.PubSub)
    start_supervised!(Caretaker.ACS.Session)
    start_supervised!(Caretaker.ACS.Tasks)
    start_supervised!(Caretaker.TR181.Store)
    _ = start_supervised({Finch, name: Caretaker.Finch})
    start_supervised!({Bandit, plug: Caretaker.ACS.Server, port: port})
    %{acs_url: "http://127.0.0.1:#{port}/cwmp"}
  end

  defp device_state do
    {:ok, state} =
      DeviceState.start_link(
        device_id: @device_id,
        params: %{
          "Device" => %{
            "DeviceInfo" => %{
              "Manufacturer" => "Acme",
              "ModelName" => "RB1",
              "SerialNumber" => "SN-E2E",
              "SoftwareVersion" => "1.0.0"
            }
          }
        }
      )

    state
  end

  defp run_session(acs_url, state) do
    Client.run_session(acs_url,
      device_id: Map.put(@device_id, :manufacturer, "Acme"),
      device_state: state
    )
  end

  test "a get task is delivered and applied with the device's values", %{acs_url: acs_url} do
    {:ok, task_id} = Tasks.submit_get(@device_id, ["Device.DeviceInfo."])

    {:ok, _} = run_session(acs_url, device_state())

    assert eventually(fn -> state(task_id) == :applied end),
           "task did not reach :applied (was #{inspect(state(task_id))})"

    {:ok, task} = Tasks.get(task_id)
    params = task.result["parameters"]
    assert params["Device.DeviceInfo.Manufacturer"] == "Acme"
    assert task.delivered_at
    assert task.completed_at
  end

  test "a set task is delivered and applied", %{acs_url: acs_url} do
    {:ok, task_id} =
      Tasks.submit_set(@device_id, [%{path: "Device.DeviceInfo.SoftwareVersion", value: "2.0.0"}])

    state = device_state()
    {:ok, _} = run_session(acs_url, state)

    assert eventually(fn -> state(task_id) == :applied end)
    # the CPE applied the set to its own state
    assert DeviceState.get(state, "Device.DeviceInfo.SoftwareVersion") == "2.0.0"
  end

  test "a cancelled task is never delivered", %{acs_url: acs_url} do
    {:ok, task_id} = Tasks.submit_get(@device_id, ["Device.DeviceInfo."])
    {:ok, :cancelled} = Tasks.cancel(task_id)

    {:ok, _} = run_session(acs_url, device_state())

    # give any stray delivery a chance, then confirm it stayed cancelled
    Process.sleep(100)
    assert state(task_id) == :cancelled
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
      true -> Process.sleep(20); eventually(fun, retries - 1)
    end
  end
end
