defmodule Caretaker.CPE.Simulation.OpticalSignal do
  @moduledoc """
  Simulates realistic optical signal levels for PON (GPON/XGPON) devices.

  This module provides realistic simulation of:
  - Optical receive power (RX) with normal variations
  - Optical transmit power (TX) with temperature effects
  - Temperature fluctuations based on load
  - Voltage and bias current monitoring
  - Alarm triggering when thresholds are exceeded

  ## Usage

      # Update optical parameters with normal variations
      device_state = OpticalSignal.update(device_state)

      # Simulate degraded signal
      device_state = OpticalSignal.update(device_state, scenario: :degraded)

      # Simulate critical condition (triggers alarms)
      device_state = OpticalSignal.update(device_state, scenario: :critical)
  """

  require Logger
  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.Events.PON

  @type scenario :: :normal | :degraded | :critical | :recovering

  @doc """
  Update optical parameters based on the specified scenario.

  ## Options

  - `:scenario` - Simulation scenario (`:normal`, `:degraded`, `:critical`, `:recovering`)
  - `:noise` - RX power noise level in dB (default: 0.5)
  - `:ambient_temp` - Ambient temperature in Celsius (default: 25)
  - `:load_factor` - Device load factor 0.0-1.0 (default: 0.3)
  """
  @spec update(pid(), keyword()) :: :ok
  def update(device_state, opts \\ []) do
    scenario = Keyword.get(opts, :scenario, :normal)
    noise = Keyword.get(opts, :noise, 0.5)
    ambient_temp = Keyword.get(opts, :ambient_temp, 25)
    load_factor = Keyword.get(opts, :load_factor, 0.3)

    # Get current values
    current_rx = DeviceState.get(device_state, "Device.Optical.Interface.1.OpticalSignalLevel")
    current_tx = DeviceState.get(device_state, "Device.Optical.Interface.1.TransmitOpticalLevel")
    current_temp = DeviceState.get(device_state, "Device.Optical.Interface.1.Temperature")

    lower_threshold =
      DeviceState.get(device_state, "Device.Optical.Interface.1.LowerOpticalThreshold")

    upper_threshold =
      DeviceState.get(device_state, "Device.Optical.Interface.1.UpperOpticalThreshold")

    # Calculate new values based on scenario
    new_rx = simulate_rx_power(current_rx, scenario, noise)
    new_tx = simulate_tx_power(current_tx, current_temp, scenario)
    new_temp = simulate_temperature(current_temp, ambient_temp, load_factor, scenario)
    new_voltage = simulate_voltage(scenario)
    new_bias = simulate_bias(scenario)

    # Update device state
    DeviceState.set(device_state, "Device.Optical.Interface.1.OpticalSignalLevel", new_rx)
    DeviceState.set(device_state, "Device.Optical.Interface.1.TransmitOpticalLevel", new_tx)
    DeviceState.set(device_state, "Device.Optical.Interface.1.Temperature", new_temp)
    DeviceState.set(device_state, "Device.Optical.Interface.1.Voltage", new_voltage)
    DeviceState.set(device_state, "Device.Optical.Interface.1.Bias", new_bias)

    # Check for alarm conditions
    check_alarms(device_state, new_rx, lower_threshold, upper_threshold, scenario)

    # Check for PON-specific events and alarms
    _events = PON.periodic_alarm_check(device_state)

    # Emit telemetry
    :telemetry.execute(
      [:caretaker, :cpe, :simulation, :optical_signal],
      %{rx_power: new_rx, tx_power: new_tx, temperature: new_temp},
      %{scenario: scenario}
    )

    :ok
  end

  # Simulate RX power variations
  defp simulate_rx_power(current, scenario, noise) do
    base_variation = :rand.normal() * noise

    scenario_effect =
      case scenario do
        :normal -> 0.0
        :degraded -> -2.0 + :rand.normal() * 1.0
        :critical -> -5.0 + :rand.normal() * 2.0
        :recovering -> -1.0 + :rand.normal() * 0.8
      end

    new_value = current + base_variation + scenario_effect
    # Clamp to realistic range (-30 dBm to 0 dBm)
    Float.round(max(-30.0, min(0.0, new_value)), 1)
  end

  # Simulate TX power (affected by temperature)
  defp simulate_tx_power(current, temperature, scenario) do
    # TX power decreases slightly with higher temperature
    temp_effect = (temperature - 45) * -0.01

    scenario_effect =
      case scenario do
        :normal -> 0.0
        :degraded -> -0.3
        :critical -> -0.8
        :recovering -> -0.1
      end

    base_variation = :rand.normal() * 0.1

    new_value = current + temp_effect + scenario_effect + base_variation
    # Typical range: 0.5 to 4.0 dBm
    Float.round(max(0.5, min(4.5, new_value)), 1)
  end

  # Simulate temperature variations
  defp simulate_temperature(current, ambient, load_factor, scenario) do
    # Temperature rises with load
    load_heat = load_factor * 15
    target_temp = ambient + load_heat

    # Gradual approach to target temperature
    temp_delta = (target_temp - current) * 0.1
    random_variation = :rand.normal() * 0.5

    scenario_effect =
      case scenario do
        :critical -> 5.0
        :degraded -> 3.0
        _ -> 0.0
      end

    new_value = current + temp_delta + random_variation + scenario_effect
    # Typical range: 0 to 85°C
    round(max(0, min(85, new_value)))
  end

  # Simulate voltage (normally stable around 3.3V)
  defp simulate_voltage(scenario) do
    base = 3.3
    variation = :rand.normal() * 0.05

    scenario_effect =
      case scenario do
        :critical -> -0.2
        :degraded -> -0.1
        _ -> 0.0
      end

    new_value = base + variation + scenario_effect
    Float.round(max(2.8, min(3.6, new_value)), 2)
  end

  # Simulate bias current (normally stable around 20-30 mA)
  defp simulate_bias(scenario) do
    base = 25.0
    variation = :rand.normal() * 1.0

    scenario_effect =
      case scenario do
        :critical -> 5.0
        :degraded -> 2.0
        _ -> 0.0
      end

    new_value = base + variation + scenario_effect
    Float.round(max(10.0, min(50.0, new_value)), 1)
  end

  # Check for alarm conditions and update status
  defp check_alarms(device_state, rx_power, lower_threshold, upper_threshold, scenario) do
    cond do
      rx_power < lower_threshold ->
        DeviceState.set(device_state, "Device.Optical.Interface.1.Status", "Error")

        Logger.warning("Optical RX power below threshold",
          rx_power: rx_power,
          threshold: lower_threshold,
          scenario: scenario
        )

        :telemetry.execute(
          [:caretaker, :cpe, :simulation, :optical_alarm],
          %{rx_power: rx_power},
          %{type: :low_rx_power, threshold: lower_threshold}
        )

      rx_power > upper_threshold ->
        DeviceState.set(device_state, "Device.Optical.Interface.1.Status", "Error")

        Logger.warning("Optical RX power above threshold",
          rx_power: rx_power,
          threshold: upper_threshold,
          scenario: scenario
        )

        :telemetry.execute(
          [:caretaker, :cpe, :simulation, :optical_alarm],
          %{rx_power: rx_power},
          %{type: :high_rx_power, threshold: upper_threshold}
        )

      true ->
        DeviceState.set(device_state, "Device.Optical.Interface.1.Status", "Up")
    end
  end

  @doc """
  Simulate a dying gasp event (sudden power loss).

  This is typically the last message sent before the device goes offline.
  """
  @spec simulate_dying_gasp(pid()) :: :ok
  def simulate_dying_gasp(device_state) do
    DeviceState.set(device_state, "Device.Optical.Interface.1.Status", "Down")
    DeviceState.set(device_state, "Device.Optical.Interface.1.Voltage", 0.0)

    # Generate dying gasp events
    _events = PON.simulate_dying_gasp(device_state)

    :telemetry.execute(
      [:caretaker, :cpe, :simulation, :dying_gasp],
      %{},
      %{device_id: DeviceState.device_id(device_state)}
    )

    Logger.warning("Dying gasp event simulated")

    :ok
  end

  @doc """
  Get current optical signal status summary.
  """
  @spec status(pid()) :: map()
  def status(device_state) do
    %{
      rx_power: DeviceState.get(device_state, "Device.Optical.Interface.1.OpticalSignalLevel"),
      tx_power: DeviceState.get(device_state, "Device.Optical.Interface.1.TransmitOpticalLevel"),
      temperature: DeviceState.get(device_state, "Device.Optical.Interface.1.Temperature"),
      voltage: DeviceState.get(device_state, "Device.Optical.Interface.1.Voltage"),
      bias: DeviceState.get(device_state, "Device.Optical.Interface.1.Bias"),
      status: DeviceState.get(device_state, "Device.Optical.Interface.1.Status"),
      lower_threshold:
        DeviceState.get(device_state, "Device.Optical.Interface.1.LowerOpticalThreshold"),
      upper_threshold:
        DeviceState.get(device_state, "Device.Optical.Interface.1.UpperOpticalThreshold")
    }
  end
end
