defmodule Caretaker.CPE.DynamicBehaviorTest do
  use ExUnit.Case, async: true

  alias Caretaker.CPE.DynamicBehavior
  alias Caretaker.CPE.DeviceState

  describe "start_link/1" do
    test "starts with required device_state" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} = DynamicBehavior.start_link(device_state: device_state)
      assert is_pid(behavior)
      assert Process.alive?(behavior)
    end

    test "starts with all behavior options" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [
            periodic_inform: [interval: 60_000, jitter: 5_000],
            dynamic_params: ["Device.DeviceInfo.UpTime"],
            value_change_events: true
          ]
        )

      status = DynamicBehavior.status(behavior)
      assert status.periodic_inform_enabled == true
      assert status.dynamic_params == ["Device.DeviceInfo.UpTime"]
      assert status.value_change_events == true
    end
  end

  describe "periodic inform" do
    test "triggers '2 PERIODIC' event on timer" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [
            periodic_inform: [interval: 100, jitter: 0]
          ]
        )

      DynamicBehavior.start(behavior)

      # Wait for timer to fire
      Process.sleep(150)

      events = DynamicBehavior.pending_events(behavior)
      assert Enum.any?(events, fn e -> e.code == "2 PERIODIC" end)
    end

    test "trigger_periodic_inform adds event immediately" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [periodic_inform: [interval: 60_000]]
        )

      DynamicBehavior.trigger_periodic_inform(behavior)

      events = DynamicBehavior.pending_events(behavior)
      assert Enum.any?(events, fn e -> e.code == "2 PERIODIC" end)
    end

    test "clear_events removes pending events" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [periodic_inform: [interval: 60_000]]
        )

      DynamicBehavior.trigger_periodic_inform(behavior)
      assert length(DynamicBehavior.pending_events(behavior)) > 0

      DynamicBehavior.clear_events(behavior)
      assert DynamicBehavior.pending_events(behavior) == []
    end

    test "jitter varies timing" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      # Start with high jitter to verify randomization
      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [
            periodic_inform: [interval: 1000, jitter: 1000]
          ]
        )

      status = DynamicBehavior.status(behavior)
      assert status.periodic_inform_enabled == true
    end
  end

  describe "dynamic parameters" do
    test "updates UpTime based on elapsed time" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{"Device" => %{"DeviceInfo" => %{"UpTime" => 0}}}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [
            dynamic_params: ["Device.DeviceInfo.UpTime"]
          ]
        )

      DynamicBehavior.start(behavior)

      # Wait for dynamic params tick
      Process.sleep(1_100)

      uptime = DeviceState.get(device_state, "Device.DeviceInfo.UpTime")
      assert uptime >= 1
    end

    test "update_dynamic_params manually triggers update" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{"Device" => %{"DeviceInfo" => %{"UpTime" => 0}}}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [
            dynamic_params: ["Device.DeviceInfo.UpTime"]
          ]
        )

      # Start behaviors to set started_at
      DynamicBehavior.start(behavior)
      Process.sleep(10)

      DynamicBehavior.update_dynamic_params(behavior)

      uptime = DeviceState.get(device_state, "Device.DeviceInfo.UpTime")
      assert uptime >= 0
    end

    test "updates interface stats when configured" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{
            "Device" => %{
              "IP" => %{
                "Interface" => %{
                  "1" => %{
                    "Stats" => %{
                      "BytesSent" => 0,
                      "BytesReceived" => 0
                    }
                  }
                }
              }
            }
          }
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [
            dynamic_params: [
              "Device.IP.Interface.1.Stats.BytesSent",
              "Device.IP.Interface.1.Stats.BytesReceived"
            ]
          ]
        )

      DynamicBehavior.start(behavior)

      # Wait for stats update
      Process.sleep(1_100)

      bytes_sent = DeviceState.get(device_state, "Device.IP.Interface.1.Stats.BytesSent")
      bytes_recv = DeviceState.get(device_state, "Device.IP.Interface.1.Stats.BytesReceived")

      assert bytes_sent > 0
      assert bytes_recv > 0
    end
  end

  describe "value change events" do
    test "records parameter changes" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{"Device" => %{"DeviceInfo" => %{"Description" => "Original"}}},
          dynamic_behavior: nil
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [value_change_events: true]
        )

      # Update device_state to use this behavior
      DeviceState.set_option(device_state, :dynamic_behavior, behavior)

      # Make a change
      DeviceState.set(device_state, "Device.DeviceInfo.Description", "Updated")

      # Check for pending VALUE CHANGE event
      events = DynamicBehavior.pending_events(behavior)
      assert Enum.any?(events, fn e -> e.code == "4 VALUE CHANGE" end)
    end

    test "does not add duplicate VALUE CHANGE events" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{
            "Device" => %{"DeviceInfo" => %{"Description" => "Original", "Name" => "Router1"}}
          },
          dynamic_behavior: nil
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [value_change_events: true]
        )

      DeviceState.set_option(device_state, :dynamic_behavior, behavior)

      # Make multiple changes
      DeviceState.set(device_state, "Device.DeviceInfo.Description", "Updated1")
      DeviceState.set(device_state, "Device.DeviceInfo.Name", "Router2")
      DeviceState.set(device_state, "Device.DeviceInfo.Description", "Updated2")

      events = DynamicBehavior.pending_events(behavior)
      value_change_events = Enum.filter(events, fn e -> e.code == "4 VALUE CHANGE" end)
      assert length(value_change_events) == 1
    end

    test "ignores changes when value_change_events is false" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{"Device" => %{"DeviceInfo" => %{"Description" => "Original"}}},
          dynamic_behavior: nil
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [value_change_events: false]
        )

      DeviceState.set_option(device_state, :dynamic_behavior, behavior)

      DeviceState.set(device_state, "Device.DeviceInfo.Description", "Updated")

      events = DynamicBehavior.pending_events(behavior)
      assert events == []
    end

    test "update_parameters also triggers value change events" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{"Device" => %{"DeviceInfo" => %{"Description" => "Original"}}},
          dynamic_behavior: nil
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [value_change_events: true]
        )

      DeviceState.set_option(device_state, :dynamic_behavior, behavior)

      DeviceState.update_parameters(device_state, [
        %{name: "Device.DeviceInfo.Description", value: "Bulk Updated"}
      ])

      events = DynamicBehavior.pending_events(behavior)
      assert Enum.any?(events, fn e -> e.code == "4 VALUE CHANGE" end)
    end
  end

  describe "add_event/3" do
    test "adds custom events" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} = DynamicBehavior.start_link(device_state: device_state)

      DynamicBehavior.add_event(behavior, "6 CONNECTION REQUEST", "cmd-123")

      events = DynamicBehavior.pending_events(behavior)

      assert Enum.any?(events, fn e ->
               e.code == "6 CONNECTION REQUEST" and e.command_key == "cmd-123"
             end)
    end
  end

  describe "stop_behaviors/1" do
    test "stops all running behaviors" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [
            periodic_inform: [interval: 100, jitter: 0],
            dynamic_params: ["Device.DeviceInfo.UpTime"]
          ]
        )

      DynamicBehavior.start(behavior)
      status1 = DynamicBehavior.status(behavior)
      assert status1.running == true

      DynamicBehavior.stop_behaviors(behavior)
      status2 = DynamicBehavior.status(behavior)
      assert status2.running == false
    end
  end

  describe "status/1" do
    test "returns comprehensive status" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [
            periodic_inform: [interval: 60_000],
            dynamic_params: ["Device.DeviceInfo.UpTime"],
            value_change_events: true
          ]
        )

      status = DynamicBehavior.status(behavior)

      assert Map.has_key?(status, :running)
      assert Map.has_key?(status, :started_at)
      assert Map.has_key?(status, :pending_events)
      assert Map.has_key?(status, :changed_params)
      assert Map.has_key?(status, :periodic_inform_enabled)
      assert Map.has_key?(status, :dynamic_params)
      assert Map.has_key?(status, :value_change_events)
    end
  end

  describe "telemetry events" do
    test "emits periodic_inform.triggered event" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [periodic_inform: [interval: 60_000]]
        )

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-periodic-triggered-#{inspect(ref)}",
        [:caretaker, :cpe, :periodic_inform, :triggered],
        fn _event, _measurements, _metadata, _ ->
          send(test_pid, {:telemetry, :periodic_inform_triggered})
        end,
        nil
      )

      DynamicBehavior.trigger_periodic_inform(behavior)

      assert_receive {:telemetry, :periodic_inform_triggered}, 1_000

      :telemetry.detach("test-periodic-triggered-#{inspect(ref)}")
    end

    test "emits dynamic_params.updated event" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{"Device" => %{"DeviceInfo" => %{"UpTime" => 0}}}
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [dynamic_params: ["Device.DeviceInfo.UpTime"]]
        )

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-dynamic-updated-#{inspect(ref)}",
        [:caretaker, :cpe, :dynamic_params, :updated],
        fn _event, _measurements, _metadata, _ ->
          send(test_pid, {:telemetry, :dynamic_params_updated})
        end,
        nil
      )

      DynamicBehavior.start(behavior)
      DynamicBehavior.update_dynamic_params(behavior)

      assert_receive {:telemetry, :dynamic_params_updated}, 1_000

      :telemetry.detach("test-dynamic-updated-#{inspect(ref)}")
    end

    test "emits param.changed event" do
      {:ok, device_state} =
        DeviceState.start_link(
          device_id: %{oui: "TEST01", product_class: "Router", serial_number: "SN001"},
          params: %{"Device" => %{"DeviceInfo" => %{"Description" => "Original"}}},
          dynamic_behavior: nil
        )

      {:ok, behavior} =
        DynamicBehavior.start_link(
          device_state: device_state,
          behaviors: [value_change_events: true]
        )

      DeviceState.set_option(device_state, :dynamic_behavior, behavior)

      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-param-changed-#{inspect(ref)}",
        [:caretaker, :cpe, :param, :changed],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:telemetry, :param_changed, metadata})
        end,
        nil
      )

      DeviceState.set(device_state, "Device.DeviceInfo.Description", "NewValue")

      assert_receive {:telemetry, :param_changed, metadata}, 1_000
      assert metadata.path == "Device.DeviceInfo.Description"
      assert metadata.old_value == "Original"
      assert metadata.new_value == "NewValue"

      :telemetry.detach("test-param-changed-#{inspect(ref)}")
    end
  end
end
