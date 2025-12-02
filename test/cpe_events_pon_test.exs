defmodule Caretaker.CPE.Events.PONTest do
  use ExUnit.Case, async: true

  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.Events.PON

  setup do
    device_id = "00140A-FiberONT-12345678"
    {:ok, state} = DeviceState.start_link(device_id: device_id, profile: :fiber_ont_full)
    %{device_state: state}
  end

  describe "supported_events/0" do
    test "returns list of standard and PON events" do
      events = PON.supported_events()

      assert "1 BOOT" in events
      assert "2 PERIODIC" in events
      assert "X_OPTICAL_ALARM" in events
      assert "X_DYING_GASP" in events
      assert "X_ONU_REGISTRATION" in events
    end
  end

  describe "check_optical_alarms/1" do
    test "detects low RX power alarm", %{device_state: state} do
      # Set RX power below threshold
      DeviceState.set(state, "Device.Optical.Interface.1.OpticalSignalLevel", -28.0)
      DeviceState.set(state, "Device.Optical.Interface.1.LowerOpticalThreshold", -27.0)

      events = PON.check_optical_alarms(state)

      assert length(events) > 0
      assert Enum.any?(events, fn e -> e.event_code == "X_OPTICAL_ALARM" end)
      assert Enum.any?(events, fn e -> e.event_type == "low-rx-power" end)
    end

    test "detects high RX power alarm", %{device_state: state} do
      # Set RX power above threshold
      DeviceState.set(state, "Device.Optical.Interface.1.OpticalSignalLevel", -7.0)
      DeviceState.set(state, "Device.Optical.Interface.1.UpperOpticalThreshold", -8.0)

      events = PON.check_optical_alarms(state)

      assert length(events) > 0
      assert Enum.any?(events, fn e -> e.event_type == "high-rx-power" end)
    end

    test "returns empty when power is within thresholds", %{device_state: state} do
      DeviceState.set(state, "Device.Optical.Interface.1.OpticalSignalLevel", -18.5)
      DeviceState.set(state, "Device.Optical.Interface.1.LowerOpticalThreshold", -27.0)
      DeviceState.set(state, "Device.Optical.Interface.1.UpperOpticalThreshold", -8.0)

      events = PON.check_optical_alarms(state)

      rx_alarms = Enum.filter(events, fn e -> String.contains?(e.event_type, "rx-power") end)
      assert rx_alarms == []
    end

    test "detects TX power alarms", %{device_state: state} do
      # Low TX power
      DeviceState.set(state, "Device.Optical.Interface.1.TransmitOpticalLevel", -4.0)

      events = PON.check_optical_alarms(state)

      assert Enum.any?(events, fn e -> e.event_type == "low-tx-power" end)
    end
  end

  describe "check_temperature_alarm/1" do
    test "detects critical temperature", %{device_state: state} do
      DeviceState.set(state, "Device.Optical.Interface.1.Temperature", 82)

      events = PON.check_temperature_alarm(state)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_TEMPERATURE_ALARM"
      assert event.event_type == "critical"
    end

    test "detects high temperature warning", %{device_state: state} do
      DeviceState.set(state, "Device.Optical.Interface.1.Temperature", 72)

      events = PON.check_temperature_alarm(state)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "warning"
    end

    test "detects low temperature", %{device_state: state} do
      DeviceState.set(state, "Device.Optical.Interface.1.Temperature", -35)

      events = PON.check_temperature_alarm(state)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "low"
    end

    test "returns empty when temperature is normal", %{device_state: state} do
      DeviceState.set(state, "Device.Optical.Interface.1.Temperature", 45)

      events = PON.check_temperature_alarm(state)

      assert events == []
    end
  end

  describe "check_voltage_alarm/1" do
    test "detects critical low voltage", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.X_VENDOR_SupplyVoltage", 10.0)

      events = PON.check_voltage_alarm(state)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_VOLTAGE_ALARM"
      assert event.event_type == "critical-low"
    end

    test "detects low voltage warning", %{device_state: state} do
      DeviceState.set(state, "Device.DeviceInfo.X_VENDOR_SupplyVoltage", 10.8)

      events = PON.check_voltage_alarm(state)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "low"
    end

    test "returns empty when voltage not available", %{device_state: state} do
      # Voltage parameter doesn't exist
      events = PON.check_voltage_alarm(state)

      assert events == []
    end
  end

  describe "simulate_dying_gasp/1" do
    test "generates dying gasp event", %{device_state: state} do
      events = PON.simulate_dying_gasp(state)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_DYING_GASP"
      assert event.event_type == "power-loss"
    end

    test "updates power status parameter", %{device_state: state} do
      PON.simulate_dying_gasp(state)

      status = DeviceState.get(state, "Device.DeviceInfo.X_VENDOR_PowerStatus")
      assert status == "power-loss"
    end
  end

  describe "simulate_onu_registration/2" do
    test "simulates full registration sequence", %{device_state: state} do
      DeviceState.set(state, "Device.X_VENDOR_PON.Status", "unregistered")

      events = PON.simulate_onu_registration(state, :operational)

      assert length(events) == 3
      assert Enum.any?(events, fn e -> e.metadata.state == "ranging" end)
      assert Enum.any?(events, fn e -> e.metadata.state == "authenticating" end)
      assert Enum.any?(events, fn e -> e.metadata.state == "operational" end)
    end

    test "updates PON status to operational", %{device_state: state} do
      DeviceState.set(state, "Device.X_VENDOR_PON.Status", "unregistered")

      PON.simulate_onu_registration(state, :operational)

      status = DeviceState.get(state, "Device.X_VENDOR_PON.Status")
      assert status == "operational"
    end

    test "simulates deregistration", %{device_state: state} do
      DeviceState.set(state, "Device.X_VENDOR_PON.Status", "operational")

      events = PON.simulate_onu_registration(state, :unregistered)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "deregistered"

      status = DeviceState.get(state, "Device.X_VENDOR_PON.Status")
      assert status == "unregistered"
    end
  end

  describe "simulate_link_state_change/2" do
    test "simulates link up event", %{device_state: state} do
      DeviceState.set(state, "Device.Optical.Interface.1.Status", "Down")

      events = PON.simulate_link_state_change(state, :up)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_LINK_UP"
      assert event.event_type == "link-restored"

      status = DeviceState.get(state, "Device.Optical.Interface.1.Status")
      assert status == "Up"
    end

    test "simulates link down event", %{device_state: state} do
      DeviceState.set(state, "Device.Optical.Interface.1.Status", "Up")

      events = PON.simulate_link_state_change(state, :down)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_LINK_DOWN"
      assert event.event_type == "link-lost"

      status = DeviceState.get(state, "Device.Optical.Interface.1.Status")
      assert status == "Down"
    end

    test "returns empty if state unchanged", %{device_state: state} do
      DeviceState.set(state, "Device.Optical.Interface.1.Status", "Up")

      events = PON.simulate_link_state_change(state, :up)

      assert events == []
    end
  end

  describe "simulate_fiber_cut/1" do
    test "generates multiple cascading events", %{device_state: state} do
      DeviceState.set(state, "Device.X_VENDOR_PON.Status", "operational")
      DeviceState.set(state, "Device.Optical.Interface.1.Status", "Up")
      DeviceState.set(state, "Device.Optical.Interface.1.LowerOpticalThreshold", -27.0)
      DeviceState.set(state, "Device.Optical.Interface.1.UpperOpticalThreshold", -8.0)

      events = PON.simulate_fiber_cut(state)

      # Should have optical alarm + link down + deregistration
      assert length(events) >= 2
      assert Enum.any?(events, fn e -> e.event_code == "X_OPTICAL_ALARM" end)
      assert Enum.any?(events, fn e -> e.event_code == "X_LINK_DOWN" end)
    end

    test "drops RX power significantly", %{device_state: state} do
      PON.simulate_fiber_cut(state)

      rx_power = DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")
      assert rx_power == -40.0
    end
  end

  describe "simulate_fiber_restore/2" do
    test "restores optical signal and registration", %{device_state: state} do
      # Initialize status
      DeviceState.set(state, "Device.Optical.Interface.1.Status", "Up")

      # First simulate cut
      PON.simulate_fiber_cut(state)

      # Then restore
      events = PON.simulate_fiber_restore(state, -18.5)

      assert length(events) >= 2
      assert Enum.any?(events, fn e -> e.event_code == "X_ONU_REGISTRATION" end)
      assert Enum.any?(events, fn e -> e.event_code == "X_LINK_UP" end)
    end

    test "restores RX power to target level", %{device_state: state} do
      PON.simulate_fiber_restore(state, -17.0)

      rx_power = DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")
      assert rx_power == -17.0
    end
  end

  describe "periodic_alarm_check/1" do
    test "checks all alarm conditions", %{device_state: state} do
      # Set thresholds
      DeviceState.set(state, "Device.Optical.Interface.1.LowerOpticalThreshold", -27.0)

      # Set some alarm conditions
      DeviceState.set(state, "Device.Optical.Interface.1.OpticalSignalLevel", -28.0)
      DeviceState.set(state, "Device.Optical.Interface.1.Temperature", 75)

      events = PON.periodic_alarm_check(state)

      # Should find at least optical and temperature alarms
      assert length(events) >= 2
      assert Enum.any?(events, fn e -> e.event_code == "X_OPTICAL_ALARM" end)
      assert Enum.any?(events, fn e -> e.event_code == "X_TEMPERATURE_ALARM" end)
    end

    test "returns empty when no alarms", %{device_state: state} do
      # Set thresholds
      DeviceState.set(state, "Device.Optical.Interface.1.LowerOpticalThreshold", -27.0)
      DeviceState.set(state, "Device.Optical.Interface.1.UpperOpticalThreshold", -8.0)

      # Set normal values
      DeviceState.set(state, "Device.Optical.Interface.1.OpticalSignalLevel", -18.5)
      DeviceState.set(state, "Device.Optical.Interface.1.Temperature", 45)

      events = PON.periodic_alarm_check(state)

      assert events == []
    end
  end
end
