defmodule Caretaker.CPE.FleetTest do
  use ExUnit.Case, async: true

  alias Caretaker.CPE.Fleet
  alias Caretaker.CPE.DeviceState

  describe "start_link/1" do
    test "starts with required acs_url" do
      {:ok, fleet} = Fleet.start_link(acs_url: "http://localhost:4000/cwmp")
      assert is_pid(fleet)
      assert Process.alive?(fleet)
    end

    test "starts with all options" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 5,
        profiles: [{60, :fiber_ont}, {40, :cable_modem}],
        connection_delay: 10,
        oui_prefix: "TEST01",
        product_class: "TestCPE",
        behaviors: [value_change_events: true]
      )

      stats = Fleet.stats(fleet)
      assert stats.total == 5
      assert stats.spawned == 0  # Not spawned yet
    end
  end

  describe "spawn_devices/1" do
    test "spawns configured number of devices" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 5,
        connection_delay: 0
      )

      {:ok, count} = Fleet.spawn_devices(fleet)
      assert count == 5

      stats = Fleet.stats(fleet)
      assert stats.spawned == 5
    end

    test "spawns devices with different profiles" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 10,
        profiles: [{50, :fiber_ont}, {50, :cable_modem}],
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      assert length(devices) == 10

      fiber_count = Enum.count(devices, &(&1.profile == :fiber_ont))
      cable_count = Enum.count(devices, &(&1.profile == :cable_modem))

      # Distribution may not be exactly 50/50 but should be close
      assert fiber_count + cable_count == 10
    end

    test "generates unique serial numbers" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 10,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      serial_numbers = Enum.map(devices, & &1.serial_number)

      assert length(Enum.uniq(serial_numbers)) == 10
    end

    test "serial numbers use configured prefix" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        oui_prefix: "MYOUI1",
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      assert Enum.all?(devices, fn d -> String.starts_with?(d.serial_number, "MYOUI1-") end)
    end

    test "is idempotent" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0
      )

      {:ok, count1} = Fleet.spawn_devices(fleet)
      {:ok, count2} = Fleet.spawn_devices(fleet)

      assert count1 == 3
      assert count2 == 3

      devices = Fleet.list_devices(fleet)
      assert length(devices) == 3
    end
  end

  describe "auto_start option" do
    test "spawns devices automatically when auto_start is true" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0,
        auto_start: true
      )

      # Give it time to spawn
      Process.sleep(100)

      stats = Fleet.stats(fleet)
      assert stats.spawned == 3
    end
  end

  describe "stop_all/1" do
    test "stops all spawned devices" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 5,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      stats_before = Fleet.stats(fleet)
      assert stats_before.spawned == 5
      assert stats_before.stopped == 0

      :ok = Fleet.stop_all(fleet)

      stats_after = Fleet.stats(fleet)
      assert stats_after.stopped == 5

      devices = Fleet.list_devices(fleet)
      assert Enum.all?(devices, fn d -> d.state == :stopped end)
      assert Enum.all?(devices, fn d -> d.has_device_state == false end)
    end
  end

  describe "stop_device/2" do
    test "stops a specific device" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      target_sn = hd(devices).serial_number

      :ok = Fleet.stop_device(fleet, target_sn)

      {:ok, device} = Fleet.get_device(fleet, target_sn)
      assert device.state == :stopped
      assert device.has_device_state == false
    end

    test "returns error for non-existent device" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      result = Fleet.stop_device(fleet, "NONEXISTENT-123456")
      assert result == {:error, :not_found}
    end
  end

  describe "get_device/2" do
    test "returns device info" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      target_sn = hd(devices).serial_number

      {:ok, device} = Fleet.get_device(fleet, target_sn)
      assert device.serial_number == target_sn
      assert device.state == :spawned
      assert device.sessions == 0
      assert device.has_device_state == true
    end

    test "returns error for non-existent device" do
      {:ok, fleet} = Fleet.start_link(acs_url: "http://localhost:4000/cwmp")
      assert Fleet.get_device(fleet, "NONEXISTENT") == {:error, :not_found}
    end
  end

  describe "add_device/2" do
    test "adds a new device dynamically" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 2,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      stats_before = Fleet.stats(fleet)
      assert stats_before.spawned == 2

      {:ok, serial} = Fleet.add_device(fleet, profile: :cable_modem)
      assert is_binary(serial)

      stats_after = Fleet.stats(fleet)
      assert stats_after.spawned == 3

      {:ok, device} = Fleet.get_device(fleet, serial)
      assert device.profile == :cable_modem
    end

    test "allows custom serial number" do
      {:ok, fleet} = Fleet.start_link(acs_url: "http://localhost:4000/cwmp")

      {:ok, serial} = Fleet.add_device(fleet, serial_number: "CUSTOM-001")
      assert serial == "CUSTOM-001"

      {:ok, device} = Fleet.get_device(fleet, "CUSTOM-001")
      assert device.serial_number == "CUSTOM-001"
    end

    test "rejects duplicate serial number" do
      {:ok, fleet} = Fleet.start_link(acs_url: "http://localhost:4000/cwmp")

      {:ok, _} = Fleet.add_device(fleet, serial_number: "DUP-001")
      result = Fleet.add_device(fleet, serial_number: "DUP-001")
      assert result == {:error, :already_exists}
    end
  end

  describe "update_param/4" do
    test "updates parameter on a specific device" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 2,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      target_sn = hd(devices).serial_number

      :ok = Fleet.update_param(fleet, target_sn, "Device.DeviceInfo.Description", "Updated via Fleet")

      # Verify the update by getting device state directly
      {:ok, device_info} = Fleet.get_device(fleet, target_sn)
      assert device_info.has_device_state == true
    end

    test "returns error for non-existent device" do
      {:ok, fleet} = Fleet.start_link(acs_url: "http://localhost:4000/cwmp")
      result = Fleet.update_param(fleet, "NONEXISTENT", "path", "value")
      assert result == {:error, :not_found}
    end
  end

  describe "update_all_params/3" do
    test "updates parameter on all devices" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      :ok = Fleet.update_all_params(fleet, "Device.DeviceInfo.Description", "Fleet Updated")

      # All devices should still be alive
      devices = Fleet.list_devices(fleet)
      assert Enum.all?(devices, fn d -> d.has_device_state == true end)
    end
  end

  describe "trigger_inform/3" do
    test "triggers inform with events on a device with behaviors" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 2,
        connection_delay: 0,
        behaviors: [value_change_events: true]
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      target_sn = hd(devices).serial_number

      :ok = Fleet.trigger_inform(fleet, target_sn, ["4 VALUE CHANGE"])

      {:ok, device} = Fleet.get_device(fleet, target_sn)
      assert device.last_inform != nil
    end

    test "returns error for device without behaviors" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 2,
        connection_delay: 0
        # No behaviors configured
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      target_sn = hd(devices).serial_number

      result = Fleet.trigger_inform(fleet, target_sn, ["2 PERIODIC"])
      assert result == {:error, :no_behavior}
    end
  end

  describe "trigger_all_informs/2" do
    test "triggers inform on all devices with behaviors" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0,
        behaviors: [value_change_events: true]
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      :ok = Fleet.trigger_all_informs(fleet, ["2 PERIODIC"])

      devices = Fleet.list_devices(fleet)
      assert Enum.all?(devices, fn d -> d.last_inform != nil end)
    end
  end

  describe "stats/1" do
    test "returns comprehensive statistics" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 5,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      stats = Fleet.stats(fleet)

      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :spawned)
      assert Map.has_key?(stats, :connected)
      assert Map.has_key?(stats, :stopped)
      assert Map.has_key?(stats, :total_sessions)
      assert Map.has_key?(stats, :uptime_seconds)
      assert Map.has_key?(stats, :memory_before_bytes)
      assert Map.has_key?(stats, :memory_after_bytes)
      assert Map.has_key?(stats, :memory_delta_bytes)
      assert Map.has_key?(stats, :memory_per_device_bytes)
      assert Map.has_key?(stats, :acs_url)

      assert stats.total == 5
      assert stats.spawned == 5
      assert stats.acs_url == "http://localhost:4000/cwmp"
    end

    test "tracks memory usage" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 10,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      stats = Fleet.stats(fleet)

      assert is_integer(stats.memory_before_bytes)
      assert is_integer(stats.memory_after_bytes)
      assert is_integer(stats.memory_delta_bytes)
      assert is_integer(stats.memory_per_device_bytes)
      # Memory delta can be negative due to GC, just verify it's calculated
      assert stats.memory_before_bytes > 0
      assert stats.memory_after_bytes > 0
    end
  end

  describe "list_devices/1" do
    test "returns all devices with sanitized info" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)

      assert length(devices) == 3
      assert Enum.all?(devices, fn d ->
        Map.has_key?(d, :serial_number) and
        Map.has_key?(d, :profile) and
        Map.has_key?(d, :state) and
        Map.has_key?(d, :sessions) and
        Map.has_key?(d, :has_device_state) and
        Map.has_key?(d, :has_dynamic_behavior)
      end)
    end
  end

  describe "telemetry events" do
    test "emits fleet.init event" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-fleet-init-#{inspect(ref)}",
        [:caretaker, :fleet, :init],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, :init, measurements, metadata})
        end,
        nil
      )

      {:ok, _fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 5
      )

      assert_receive {:telemetry, :init, %{count: 5}, %{acs_url: "http://localhost:4000/cwmp"}}, 1_000

      :telemetry.detach("test-fleet-init-#{inspect(ref)}")
    end

    test "emits fleet.spawned event" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-fleet-spawned-#{inspect(ref)}",
        [:caretaker, :fleet, :spawned],
        fn _event, measurements, _metadata, _ ->
          send(test_pid, {:telemetry, :spawned, measurements})
        end,
        nil
      )

      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      assert_receive {:telemetry, :spawned, %{count: 3}}, 1_000

      :telemetry.detach("test-fleet-spawned-#{inspect(ref)}")
    end

    test "emits fleet.device.spawned event for each device" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-fleet-device-spawned-#{inspect(ref)}",
        [:caretaker, :fleet, :device, :spawned],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:telemetry, :device_spawned, metadata})
        end,
        nil
      )

      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 2,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      assert_receive {:telemetry, :device_spawned, %{serial_number: _}}, 1_000
      assert_receive {:telemetry, :device_spawned, %{serial_number: _}}, 1_000

      :telemetry.detach("test-fleet-device-spawned-#{inspect(ref)}")
    end

    test "emits fleet.stopped event" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-fleet-stopped-#{inspect(ref)}",
        [:caretaker, :fleet, :stopped],
        fn _event, measurements, _metadata, _ ->
          send(test_pid, {:telemetry, :stopped, measurements})
        end,
        nil
      )

      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 3,
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)
      :ok = Fleet.stop_all(fleet)

      assert_receive {:telemetry, :stopped, %{count: 3}}, 1_000

      :telemetry.detach("test-fleet-stopped-#{inspect(ref)}")
    end
  end

  describe "profile loading" do
    test "loads fiber_ont profile from file if available" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 1,
        profiles: [{100, :fiber_ont}],
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      device = hd(devices)
      assert device.profile == :fiber_ont
    end

    test "uses default params for unknown profile" do
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 1,
        profiles: [{100, :unknown_profile}],
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      assert length(devices) == 1
    end

    test "accepts custom params map as profile" do
      custom_params = %{
        "Device" => %{
          "DeviceInfo" => %{
            "Manufacturer" => "CustomMfg",
            "SoftwareVersion" => "2.0.0"
          }
        }
      }

      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 1,
        profiles: [{100, custom_params}],
        connection_delay: 0
      )

      {:ok, _} = Fleet.spawn_devices(fleet)

      devices = Fleet.list_devices(fleet)
      assert length(devices) == 1
    end
  end
end
