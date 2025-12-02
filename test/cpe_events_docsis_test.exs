defmodule Caretaker.CPE.Events.DOCSISTest do
  use ExUnit.Case, async: true

  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.Events.DOCSIS

  setup do
    device_id = "001A2B-CableModem-87654321"
    {:ok, state} = DeviceState.start_link(device_id: device_id, profile: :cable_modem_full)
    %{device_state: state}
  end

  describe "supported_events/0" do
    test "returns list of standard and DOCSIS events" do
      events = DOCSIS.supported_events()

      assert "1 BOOT" in events
      assert "X_CM_REGISTRATION" in events
      assert "X_T3_TIMEOUT" in events
      assert "X_T4_TIMEOUT" in events
      assert "X_SNR_DEGRADATION" in events
    end
  end

  describe "registration_states/0" do
    test "returns all valid registration states" do
      states = DOCSIS.registration_states()

      assert "operational" in states
      assert "rangingComplete" in states
      assert "registrationComplete" in states
      assert length(states) > 10
    end
  end

  describe "simulate_registration_flow/1" do
    test "generates events for all registration states", %{device_state: state} do
      events = DOCSIS.simulate_registration_flow(state)

      assert length(events) > 10
      assert Enum.any?(events, fn e -> e.event_code == "X_CM_REGISTRATION" end)
    end

    test "sets modem status to operational", %{device_state: state} do
      DOCSIS.simulate_registration_flow(state)

      status = DeviceState.get(state, "Device.Docsis.Status")
      assert status == "Operational"
    end
  end

  describe "simulate_t3_timeout/2" do
    test "generates T3 timeout event", %{device_state: state} do
      events = DOCSIS.simulate_t3_timeout(state, 1)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_T3_TIMEOUT"
      assert event.metadata.channel_id == 1
    end

    test "increments timeout counter", %{device_state: state} do
      path = "Device.Docsis.Upstream.1.Stats.T3Timeouts"
      DeviceState.set(state, path, 5)

      DOCSIS.simulate_t3_timeout(state, 1)

      count = DeviceState.get(state, path)
      assert count == 6
    end
  end

  describe "simulate_t4_timeout/2" do
    test "generates T4 timeout event", %{device_state: state} do
      events = DOCSIS.simulate_t4_timeout(state, 2)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_T4_TIMEOUT"
      assert event.metadata.channel_id == 2
    end
  end

  describe "simulate_ranging_failure/2" do
    test "generates ranging failure event", %{device_state: state} do
      events = DOCSIS.simulate_ranging_failure(state, "timeout")

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_RANGING_FAILURE"
      assert event.metadata.reason == "timeout"
    end

    test "sets status to ranging failure", %{device_state: state} do
      DOCSIS.simulate_ranging_failure(state)

      status = DeviceState.get(state, "Device.Docsis.Status")
      assert status == "RangingFailure"
    end
  end

  describe "simulate_config_download/3" do
    test "generates success event", %{device_state: state} do
      events = DOCSIS.simulate_config_download(state, "gold.cfg", true)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_CONFIG_FILE_DOWNLOAD"
      assert event.event_type == "success"
      assert event.metadata.filename == "gold.cfg"
    end

    test "generates failure event", %{device_state: state} do
      events = DOCSIS.simulate_config_download(state, "gold.cfg", false)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "failure"
    end
  end

  describe "check_snr_alarms/1" do
    test "detects critical SNR on channels", %{device_state: state} do
      DeviceState.set(state, "Device.Docsis.Downstream.1.SNR", 22.0)
      DeviceState.set(state, "Device.Docsis.Downstream.2.SNR", 23.0)

      events = DOCSIS.check_snr_alarms(state)

      assert length(events) >= 2
      assert Enum.all?(events, fn e -> e.event_code == "X_SNR_DEGRADATION" end)
    end

    test "detects low SNR warning", %{device_state: state} do
      DeviceState.set(state, "Device.Docsis.Downstream.1.SNR", 28.0)

      events = DOCSIS.check_snr_alarms(state)

      assert length(events) == 1
      [event] = events
      assert event.event_type == "warning"
    end

    test "returns empty when SNR is good", %{device_state: state} do
      for ch <- 1..32 do
        DeviceState.set(state, "Device.Docsis.Downstream.#{ch}.SNR", 38.0)
      end

      events = DOCSIS.check_snr_alarms(state)

      assert events == []
    end
  end

  describe "check_fec_errors/1" do
    test "detects high uncorrectable errors", %{device_state: state} do
      DeviceState.set(state, "Device.Docsis.Downstream.1.Stats.UncorrectableErrors", 150)

      events = DOCSIS.check_fec_errors(state)

      assert length(events) >= 1
      assert Enum.any?(events, fn e -> e.event_type == "uncorrectable" end)
    end

    test "detects high correctable errors", %{device_state: state} do
      DeviceState.set(state, "Device.Docsis.Downstream.1.Stats.CorrectableErrors", 15000)

      events = DOCSIS.check_fec_errors(state)

      assert length(events) >= 1
      assert Enum.any?(events, fn e -> e.event_type == "correctable" end)
    end
  end

  describe "simulate_partial_service/2" do
    test "generates partial service event", %{device_state: state} do
      events = DOCSIS.simulate_partial_service(state, 16)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_PARTIAL_SERVICE"
      assert event.metadata.locked_channels == 16
    end

    test "sets some channels to unlocked", %{device_state: state} do
      DOCSIS.simulate_partial_service(state, 16)

      # Channels above 16 should be unlocked
      status = DeviceState.get(state, "Device.Docsis.Downstream.20.LockStatus")
      assert status == "Unlocked"
    end
  end

  describe "simulate_plant_issue/1" do
    test "generates multiple events", %{device_state: state} do
      # Set normal SNR first
      for ch <- 1..32 do
        DeviceState.set(state, "Device.Docsis.Downstream.#{ch}.SNR", 38.0)
      end

      events = DOCSIS.simulate_plant_issue(state)

      # Should have SNR alarms and timeouts
      assert length(events) > 0
    end

    test "degrades SNR on channels", %{device_state: state} do
      DeviceState.set(state, "Device.Docsis.Downstream.1.SNR", 38.0)

      DOCSIS.simulate_plant_issue(state)

      snr = DeviceState.get(state, "Device.Docsis.Downstream.1.SNR")
      assert snr < 35.0
    end
  end

  describe "simulate_plant_restore/1" do
    test "restores operational status", %{device_state: state} do
      # First simulate issue
      DOCSIS.simulate_plant_issue(state)

      # Then restore
      events = DOCSIS.simulate_plant_restore(state)

      assert length(events) == 1
      [event] = events
      assert event.event_code == "X_CM_OPERATIONAL"

      status = DeviceState.get(state, "Device.Docsis.Status")
      assert status == "Operational"
    end

    test "restores SNR levels", %{device_state: state} do
      DOCSIS.simulate_plant_issue(state)
      DOCSIS.simulate_plant_restore(state)

      snr = DeviceState.get(state, "Device.Docsis.Downstream.1.SNR")
      assert snr > 35.0
    end
  end

  describe "periodic_health_check/1" do
    test "checks SNR and FEC errors", %{device_state: state} do
      # Set some issues
      DeviceState.set(state, "Device.Docsis.Downstream.1.SNR", 25.0)
      DeviceState.set(state, "Device.Docsis.Downstream.2.Stats.UncorrectableErrors", 200)

      events = DOCSIS.periodic_health_check(state)

      assert length(events) >= 2
    end

    test "returns empty when healthy", %{device_state: state} do
      # Set good values
      for ch <- 1..32 do
        DeviceState.set(state, "Device.Docsis.Downstream.#{ch}.SNR", 38.0)
        DeviceState.set(state, "Device.Docsis.Downstream.#{ch}.Stats.CorrectableErrors", 100)
        DeviceState.set(state, "Device.Docsis.Downstream.#{ch}.Stats.UncorrectableErrors", 0)
      end

      events = DOCSIS.periodic_health_check(state)

      assert events == []
    end
  end
end
