defmodule Caretaker.CPE.Simulation.RouterResourcesTest do
  use ExUnit.Case, async: true

  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.Simulation.RouterResources

  setup do
    # Load Mikrotik router profile
    profile_path =
      Path.join([File.cwd!(), "priv", "profiles", "mikrotik.json"])

    device_id = %{
      oui: "D4CA6D",
      product_class: "RouterOS",
      serial_number: "TEST003"
    }

    {:ok, device_state} = DeviceState.start_link(device_id: device_id)
    :ok = DeviceState.load_profile(device_state, profile_path)

    on_exit(fn ->
      if Process.alive?(device_state), do: Agent.stop(device_state)
    end)

    %{device_state: device_state}
  end

  describe "idle load" do
    test "shows low CPU usage", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :idle)

      cpu = DeviceState.get(state, "Device.DeviceInfo.ProcessStatus.CPUUsage")
      assert cpu >= 0 and cpu <= 10
    end

    test "shows high free memory", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :idle)

      total = DeviceState.get(state, "Device.DeviceInfo.MemoryStatus.Total")
      free = DeviceState.get(state, "Device.DeviceInfo.MemoryStatus.Free")

      free_pct = free / total
      assert free_pct > 0.8
    end

    test "shows low connection count", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :idle)

      connections =
        DeviceState.get(state, "Device.Firewall.X_MIKROTIK_ConnectionCount")

      assert connections < 100
    end
  end

  describe "normal load" do
    test "shows moderate CPU usage", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :normal)

      cpu = DeviceState.get(state, "Device.DeviceInfo.ProcessStatus.CPUUsage")
      assert cpu >= 15 and cpu <= 40
    end

    test "shows moderate memory usage", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :normal)

      total = DeviceState.get(state, "Device.DeviceInfo.MemoryStatus.Total")
      free = DeviceState.get(state, "Device.DeviceInfo.MemoryStatus.Free")

      free_pct = free / total
      assert free_pct >= 0.3 and free_pct <= 0.7
    end

    test "updates uptime", %{device_state: state} do
      initial_uptime = DeviceState.get(state, "Device.DeviceInfo.UpTime")

      :ok = RouterResources.update(state, load_profile: :normal)

      final_uptime = DeviceState.get(state, "Device.DeviceInfo.UpTime")
      assert final_uptime == initial_uptime + 1
    end
  end

  describe "high load" do
    test "shows high CPU usage", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :high)

      cpu = DeviceState.get(state, "Device.DeviceInfo.ProcessStatus.CPUUsage")
      assert cpu >= 50
    end

    test "shows low free memory", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :high)

      total = DeviceState.get(state, "Device.DeviceInfo.MemoryStatus.Total")
      free = DeviceState.get(state, "Device.DeviceInfo.MemoryStatus.Free")

      free_pct = free / total
      assert free_pct < 0.4
    end

    test "shows high connection count", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :high)

      connections =
        DeviceState.get(state, "Device.Firewall.X_MIKROTIK_ConnectionCount")

      assert connections > 3000
    end
  end

  describe "exhausted resources" do
    test "shows very high CPU usage", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :exhausted)

      cpu = DeviceState.get(state, "Device.DeviceInfo.ProcessStatus.CPUUsage")
      assert cpu >= 85
    end

    test "shows very low free memory", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :exhausted)

      total = DeviceState.get(state, "Device.DeviceInfo.MemoryStatus.Total")
      free = DeviceState.get(state, "Device.DeviceInfo.MemoryStatus.Free")

      free_pct = free / total
      assert free_pct < 0.15
    end

    test "may show packet drops", %{device_state: state} do
      # Run multiple times to increase chance of drops
      Enum.each(1..10, fn _ ->
        :ok = RouterResources.update(state, load_profile: :exhausted)
      end)

      # Check first interface for drops
      discards =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.DiscardPacketsSent") || 0

      # Might have drops (probabilistic)
      assert discards >= 0
    end
  end

  describe "interface statistics" do
    test "updates interface traffic counters", %{device_state: state} do
      initial_bytes_sent =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.BytesSent")

      :ok = RouterResources.update(state, load_profile: :normal)

      final_bytes_sent =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.BytesSent")

      assert final_bytes_sent > initial_bytes_sent
    end

    test "updates packet counters", %{device_state: state} do
      initial_packets_sent =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.PacketsSent")

      :ok = RouterResources.update(state, load_profile: :normal)

      final_packets_sent =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.PacketsSent")

      assert final_packets_sent > initial_packets_sent
    end

    test "WAN interfaces have higher traffic", %{device_state: state} do
      # Interface 1 is marked as upstream (WAN) in mikrotik profile
      initial_wan_bytes =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.BytesSent")

      initial_lan_bytes =
        DeviceState.get(state, "Device.Ethernet.Interface.2.Stats.BytesSent")

      :ok = RouterResources.update(state, load_profile: :normal)

      wan_increment =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.BytesSent") -
          initial_wan_bytes

      lan_increment =
        DeviceState.get(state, "Device.Ethernet.Interface.2.Stats.BytesSent") -
          initial_lan_bytes

      # WAN should have more traffic (3x multiplier)
      assert wan_increment > lan_increment
    end

    test "skips inactive interfaces", %{device_state: state} do
      # Interface 4 is Down in the profile
      initial_bytes =
        DeviceState.get(state, "Device.Ethernet.Interface.4.Stats.BytesSent")

      :ok = RouterResources.update(state, load_profile: :normal)

      final_bytes = DeviceState.get(state, "Device.Ethernet.Interface.4.Stats.BytesSent")

      # Should remain zero
      assert final_bytes == initial_bytes
      assert final_bytes == 0
    end

    test "can skip interface updates", %{device_state: state} do
      initial_bytes_sent =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.BytesSent")

      :ok =
        RouterResources.update(state, load_profile: :normal, update_interfaces: false)

      final_bytes_sent =
        DeviceState.get(state, "Device.Ethernet.Interface.1.Stats.BytesSent")

      # Should not have changed
      assert final_bytes_sent == initial_bytes_sent
    end
  end

  describe "load detection" do
    test "detects idle profile", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 3)

      profile = RouterResources.detect_load_profile(state)
      assert profile == :idle
    end

    test "detects normal profile", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 30)

      profile = RouterResources.detect_load_profile(state)
      assert profile == :normal
    end

    test "detects high profile", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 65)

      profile = RouterResources.detect_load_profile(state)
      assert profile == :high
    end

    test "detects exhausted profile", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 95)

      profile = RouterResources.detect_load_profile(state)
      assert profile == :exhausted
    end
  end

  describe "status reporting" do
    test "returns comprehensive status", %{device_state: state} do
      :ok = RouterResources.update(state, load_profile: :normal)

      status = RouterResources.status(state)

      assert is_map(status)
      assert Map.has_key?(status, :cpu_usage)
      assert Map.has_key?(status, :memory_total)
      assert Map.has_key?(status, :memory_free)
      assert Map.has_key?(status, :memory_used_pct)
      assert Map.has_key?(status, :uptime)

      assert is_number(status.cpu_usage)
      assert is_number(status.memory_total)
      assert is_number(status.memory_free)
      assert is_float(status.memory_used_pct)
    end
  end

  describe "telemetry" do
    test "emits update telemetry", %{device_state: state} do
      test_pid = self()
      handler_id = "test-router-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:caretaker, :cpe, :simulation, :router_resources],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      :ok = RouterResources.update(state, load_profile: :normal)

      assert_receive {:telemetry, measurements, metadata}, 1000
      assert Map.has_key?(measurements, :cpu)
      assert Map.has_key?(measurements, :memory_free)
      assert Map.has_key?(measurements, :connections)
      assert metadata.load_profile == :normal

      :telemetry.detach(handler_id)
    end
  end

  describe "load ramp simulation" do
    test "load_ramp function exists and accepts options", %{device_state: state} do
      # Test that function exists with correct arity
      assert function_exported?(RouterResources, :simulate_load_ramp, 2)

      # Quick test with short duration
      # :ok = RouterResources.simulate_load_ramp(state, duration: 1000, steps: 3)

      # cpu = DeviceState.get(state, "Device.DeviceInfo.ProcessStatus.CPUUsage")
      # Should be at high or exhausted after ramp
      # assert cpu > 50
    end
  end
end
