defmodule Caretaker.CPE.Simulation.OpticalSignalTest do
  use ExUnit.Case, async: true

  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.Simulation.OpticalSignal

  setup do
    # Load fiber ONT profile with optical parameters
    profile_path =
      Path.join([File.cwd!(), "priv", "profiles", "fiber_ont_full.json"])

    device_id = %{
      oui: "TEST01",
      product_class: "FiberONT",
      serial_number: "TEST001"
    }

    {:ok, device_state} = DeviceState.start_link(device_id: device_id)
    :ok = DeviceState.load_profile(device_state, profile_path)

    on_exit(fn ->
      if Process.alive?(device_state), do: Agent.stop(device_state)
    end)

    %{device_state: device_state}
  end

  describe "normal operation" do
    test "updates optical parameters with realistic variations", %{device_state: state} do
      initial_rx =
        DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")

      initial_tx =
        DeviceState.get(state, "Device.Optical.Interface.1.TransmitOpticalLevel")

      # Update multiple times
      :ok = OpticalSignal.update(state, scenario: :normal)
      :ok = OpticalSignal.update(state, scenario: :normal)
      :ok = OpticalSignal.update(state, scenario: :normal)

      final_rx = DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")
      final_tx = DeviceState.get(state, "Device.Optical.Interface.1.TransmitOpticalLevel")

      # Values should vary but stay in realistic range
      assert is_float(final_rx)
      assert final_rx >= -30.0 and final_rx <= 0.0

      assert is_float(final_tx)
      assert final_tx >= 0.5 and final_tx <= 4.5

      # Should have changed (probabilistic, but very likely)
      assert final_rx != initial_rx or final_tx != initial_tx
    end

    test "maintains status as Up during normal operation", %{device_state: state} do
      :ok = OpticalSignal.update(state, scenario: :normal)
      status = DeviceState.get(state, "Device.Optical.Interface.1.Status")
      assert status == "Up"
    end

    test "updates temperature based on load", %{device_state: state} do
      :ok = OpticalSignal.update(state, load_factor: 0.9, ambient_temp: 30)
      temp = DeviceState.get(state, "Device.Optical.Interface.1.Temperature")

      assert is_integer(temp)
      assert temp >= 30
      assert temp <= 85
    end

    test "updates voltage and bias current", %{device_state: state} do
      :ok = OpticalSignal.update(state, scenario: :normal)

      voltage = DeviceState.get(state, "Device.Optical.Interface.1.Voltage")
      bias = DeviceState.get(state, "Device.Optical.Interface.1.Bias")

      assert is_float(voltage)
      assert voltage >= 2.8 and voltage <= 3.6

      assert is_float(bias)
      assert bias >= 10.0 and bias <= 50.0
    end
  end

  describe "degraded signal" do
    test "reduces RX power during degraded scenario", %{device_state: state} do
      initial_rx =
        DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")

      :ok = OpticalSignal.update(state, scenario: :degraded)
      degraded_rx = DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")

      # Degraded should be lower (though random, very likely)
      assert degraded_rx < initial_rx + 1.0
    end

    test "still maintains Up status if above threshold", %{device_state: state} do
      :ok = OpticalSignal.update(state, scenario: :degraded)
      rx_power = DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")
      threshold = DeviceState.get(state, "Device.Optical.Interface.1.LowerOpticalThreshold")

      if rx_power >= threshold do
        status = DeviceState.get(state, "Device.Optical.Interface.1.Status")
        assert status == "Up"
      end
    end
  end

  describe "critical condition" do
    test "triggers alarm when below threshold", %{device_state: state} do
      # Attach telemetry handler
      test_pid = self()
      handler_id = "test-optical-alarm-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:caretaker, :cpe, :simulation, :optical_alarm],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:alarm, measurements, metadata})
        end,
        nil
      )

      # Run critical scenario multiple times to trigger alarm
      Enum.each(1..5, fn _ ->
        :ok = OpticalSignal.update(state, scenario: :critical)
      end)

      rx_power = DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")
      threshold = DeviceState.get(state, "Device.Optical.Interface.1.LowerOpticalThreshold")

      if rx_power < threshold do
        assert_receive {:alarm, _measurements, metadata}, 1000
        assert metadata.type == :low_rx_power
        status = DeviceState.get(state, "Device.Optical.Interface.1.Status")
        assert status == "Error"
      end

      :telemetry.detach(handler_id)
    end
  end

  describe "dying gasp" do
    test "simulates power loss", %{device_state: state} do
      :ok = OpticalSignal.simulate_dying_gasp(state)

      status = DeviceState.get(state, "Device.Optical.Interface.1.Status")
      voltage = DeviceState.get(state, "Device.Optical.Interface.1.Voltage")

      assert status == "Down"
      assert voltage == 0.0
    end

    test "emits dying gasp telemetry event", %{device_state: state} do
      test_pid = self()
      handler_id = "test-dying-gasp-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:caretaker, :cpe, :simulation, :dying_gasp],
        fn _name, _measurements, metadata, _config ->
          send(test_pid, {:dying_gasp, metadata})
        end,
        nil
      )

      :ok = OpticalSignal.simulate_dying_gasp(state)

      assert_receive {:dying_gasp, metadata}, 1000
      assert metadata.device_id != nil

      :telemetry.detach(handler_id)
    end
  end

  describe "status reporting" do
    test "returns comprehensive status", %{device_state: state} do
      status = OpticalSignal.status(state)

      assert is_map(status)
      assert Map.has_key?(status, :rx_power)
      assert Map.has_key?(status, :tx_power)
      assert Map.has_key?(status, :temperature)
      assert Map.has_key?(status, :voltage)
      assert Map.has_key?(status, :bias)
      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :lower_threshold)
      assert Map.has_key?(status, :upper_threshold)
    end
  end

  describe "telemetry" do
    test "emits update telemetry", %{device_state: state} do
      test_pid = self()
      handler_id = "test-optical-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:caretaker, :cpe, :simulation, :optical_signal],
        fn _name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      :ok = OpticalSignal.update(state, scenario: :normal)

      assert_receive {:telemetry, measurements, metadata}, 1000
      assert Map.has_key?(measurements, :rx_power)
      assert Map.has_key?(measurements, :tx_power)
      assert Map.has_key?(measurements, :temperature)
      assert metadata.scenario == :normal

      :telemetry.detach(handler_id)
    end
  end
end
