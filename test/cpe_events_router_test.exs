defmodule Caretaker.CPE.Events.RouterTest do
  use ExUnit.Case, async: true

  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.Events.Router

  setup do
    device_id = "D4CA6D-Mikrotik-RB4011"
    {:ok, state} = DeviceState.start_link(device_id: device_id, profile: :mikrotik)
    %{device_state: state}
  end

  describe "supported_events/0" do
    test "returns list of standard and router events" do
      events = Router.supported_events()

      assert "1 BOOT" in events
      assert "X_FIRMWARE_UPGRADE" in events
      assert "X_WAN_LINK_UP" in events
      assert "X_DHCP_LEASE_ACQUIRED" in events
      assert "X_HIGH_CPU_USAGE" in events
    end
  end

  describe "simulate_firmware_upgrade/2" do
    test "generates upgrade event sequence", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.SoftwareVersion", "7.10")

      events = Router.simulate_firmware_upgrade(state, "7.12")

      assert length(events) >= 4
      assert Enum.any?(events, fn e -> e.event_type == "download-started" end)
      assert Enum.any?(events, fn e -> e.event_type == "installing" end)
      assert Enum.any?(events, fn e -> e.event_code == "1 BOOT" end)
    end

    test "updates software version", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.SoftwareVersion", "7.10")

      Router.simulate_firmware_upgrade(state, "7.12")

      version = DeviceState.get(state, "Device.DeviceInfo.SoftwareVersion")
      assert version == "7.12"
    end
  end

  describe "simulate_config_change/2" do
    test "generates config change event", %{device_state: state} do
      changed_params = ["Device.WiFi.SSID.1.SSID", "Device.WiFi.SSID.1.Enable"]

      events = Router.simulate_config_change(state, changed_params)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_CONFIG_CHANGE"
      assert event.metadata.parameter_count == 2
    end
  end

  describe "simulate_wan_link_change/2" do
    test "generates WAN link up event", %{device_state: state} do
      DeviceState.set(state, "Device.IP.Interface.1.Status", "Down")

      events = Router.simulate_wan_link_change(state, :up)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_WAN_LINK_UP"
      assert event.event_type == "link-restored"

      status = DeviceState.get(state, "Device.IP.Interface.1.Status")
      assert status == "Up"
    end

    test "generates WAN link down event", %{device_state: state} do
      DeviceState.set(state, "Device.IP.Interface.1.Status", "Up")

      events = Router.simulate_wan_link_change(state, :down)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_WAN_LINK_DOWN"
    end

    test "returns empty if state unchanged", %{device_state: state} do
      DeviceState.set(state, "Device.IP.Interface.1.Status", "Up")

      events = Router.simulate_wan_link_change(state, :up)

      assert events == []
    end
  end

  describe "simulate_lan_link_change/3" do
    test "generates LAN link up event", %{device_state: state} do
      DeviceState.set(state, "Device.Ethernet.Interface.2.Status", "Down")

      events = Router.simulate_lan_link_change(state, 2, :up)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_LAN_LINK_UP"
      assert event.metadata.interface_num == 2
    end

    test "generates LAN link down event", %{device_state: state} do
      DeviceState.set(state, "Device.Ethernet.Interface.3.Status", "Up")

      events = Router.simulate_lan_link_change(state, 3, :down)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_LAN_LINK_DOWN"
    end
  end

  describe "simulate_dhcp_lease_acquired/3" do
    test "generates lease acquired event", %{device_state: state} do
      events = Router.simulate_dhcp_lease_acquired(state, "192.168.1.100", 86400)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_DHCP_LEASE_ACQUIRED"
      assert event.metadata.ip_address == "192.168.1.100"
      assert event.metadata.lease_time == 86400
    end

    test "updates IP address", %{device_state: state} do
      Router.simulate_dhcp_lease_acquired(state, "192.168.1.100", 86400)

      ip = DeviceState.get(state, "Device.IP.Interface.1.IPv4Address.1.IPAddress")
      assert ip == "192.168.1.100"
    end
  end

  describe "simulate_dhcp_lease_renewed/2" do
    test "generates renewal event", %{device_state: state} do
      events = Router.simulate_dhcp_lease_renewed(state, "192.168.1.100")

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_DHCP_LEASE_RENEWED"
    end
  end

  describe "simulate_dhcp_lease_expired/1" do
    test "generates expiration event", %{device_state: state} do
      DeviceState.set(state, "Device.IP.Interface.1.IPv4Address.1.IPAddress", "192.168.1.100")

      events = Router.simulate_dhcp_lease_expired(state)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_DHCP_LEASE_EXPIRED"
      assert event.metadata.previous_ip == "192.168.1.100"
    end

    test "clears IP address", %{device_state: state} do
      DeviceState.set(state, "Device.IP.Interface.1.IPv4Address.1.IPAddress", "192.168.1.100")

      Router.simulate_dhcp_lease_expired(state)

      ip = DeviceState.get(state, "Device.IP.Interface.1.IPv4Address.1.IPAddress")
      assert ip == "0.0.0.0"
    end
  end

  describe "simulate_route_added/4" do
    test "generates route added event", %{device_state: state} do
      events = Router.simulate_route_added(state, "10.0.0.0/8", "192.168.1.1", 10)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_ROUTE_ADDED"
      assert event.metadata.destination == "10.0.0.0/8"
      assert event.metadata.gateway == "192.168.1.1"
    end
  end

  describe "simulate_route_deleted/2" do
    test "generates route deleted event", %{device_state: state} do
      events = Router.simulate_route_deleted(state, "10.0.0.0/8")

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_ROUTE_DELETED"
    end
  end

  describe "check_cpu_usage/1" do
    test "detects critical CPU usage", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 96)

      events = Router.check_cpu_usage(state)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_HIGH_CPU_USAGE"
      assert event.event_type == "critical"
    end

    test "detects high CPU warning", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 85)

      events = Router.check_cpu_usage(state)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "warning"
    end

    test "returns empty when CPU is normal", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 25)

      events = Router.check_cpu_usage(state)

      assert events == []
    end
  end

  describe "check_memory_usage/1" do
    test "detects critical memory usage", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.MemoryStatus.Total", 1000)
      DeviceState.set(state, "Device.DeviceInfo.MemoryStatus.Free", 30)

      events = Router.check_memory_usage(state)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_HIGH_MEMORY_USAGE"
      assert event.event_type == "critical"
    end

    test "detects high memory warning", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.MemoryStatus.Total", 1000)
      DeviceState.set(state, "Device.DeviceInfo.MemoryStatus.Free", 120)

      events = Router.check_memory_usage(state)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "warning"
    end
  end

  describe "check_connection_limit/2" do
    test "detects critical connection count", %{device_state: state} do
      DeviceState.set(state, "Device.X_VENDOR_ConnectionTracking.Current", 63000)

      events = Router.check_connection_limit(state, 65536)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_CONNECTION_LIMIT"
      assert event.event_type == "critical"
    end

    test "detects high connection warning", %{device_state: state} do
      DeviceState.set(state, "Device.X_VENDOR_ConnectionTracking.Current", 58000)

      events = Router.check_connection_limit(state, 65536)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "warning"
    end
  end

  describe "simulate_isp_outage/1" do
    test "generates multiple outage events", %{device_state: state} do
      DeviceState.set(state, "Device.IP.Interface.1.Status", "Up")
      DeviceState.set(state, "Device.IP.Interface.1.IPv4Address.1.IPAddress", "192.168.1.100")

      events = Router.simulate_isp_outage(state)

      assert length(events) >= 2
      assert Enum.any?(events, fn e -> e.event_code == "X_WAN_LINK_DOWN" end)
      assert Enum.any?(events, fn e -> e.event_code == "X_DHCP_LEASE_EXPIRED" end)
    end
  end

  describe "simulate_isp_restore/2" do
    test "generates restore events", %{device_state: state} do
      DeviceState.set(state, "Device.IP.Interface.1.Status", "Down")

      events = Router.simulate_isp_restore(state, "192.168.1.100")

      assert length(events) >= 2
      assert Enum.any?(events, fn e -> e.event_code == "X_WAN_LINK_UP" end)
      assert Enum.any?(events, fn e -> e.event_code == "X_DHCP_LEASE_ACQUIRED" end)
    end
  end

  describe "periodic_health_check/1" do
    test "checks all resource metrics", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 92)
      DeviceState.set(state, "Device.DeviceInfo.MemoryStatus.Total", 1000)
      DeviceState.set(state, "Device.DeviceInfo.MemoryStatus.Free", 40)

      events = Router.periodic_health_check(state)

      assert length(events) >= 2
    end

    test "returns empty when healthy", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.ProcessStatus.CPUUsage", 25)
      DeviceState.set(state, "Device.DeviceInfo.MemoryStatus.Total", 1000)
      DeviceState.set(state, "Device.DeviceInfo.MemoryStatus.Free", 700)
      DeviceState.set(state, "Device.X_VENDOR_ConnectionTracking.Current", 5000)

      events = Router.periodic_health_check(state)

      assert events == []
    end
  end
end
