defmodule Caretaker.CPE.Events.PON do
  @moduledoc """
  PON (GPON/XGPON) specific event generation and simulation.

  Generates realistic TR-069 events for fiber ONT devices including:
  - Standard TR-069 events (BOOT, PERIODIC, VALUE CHANGE)
  - PON-specific vendor events (registration, optical alarms, dying gasp)
  - Link state changes
  - Threshold-based alarms
  """

  require Logger
  alias Caretaker.CPE.DeviceState

  @standard_events [
    "1 BOOT",
    "2 PERIODIC",
    "4 VALUE CHANGE",
    "6 CONNECTION REQUEST",
    "7 TRANSFER COMPLETE",
    "8 DIAGNOSTICS COMPLETE"
  ]

  @pon_events [
    "X_ONU_REGISTRATION",
    "X_OPTICAL_ALARM",
    "X_DYING_GASP",
    "X_LINK_DOWN",
    "X_LINK_UP",
    "X_TEMPERATURE_ALARM",
    "X_VOLTAGE_ALARM"
  ]

  @doc """
  Returns all supported event codes for PON devices.
  """
  def supported_events do
    @standard_events ++ @pon_events
  end

  @doc """
  Check for optical power alarms based on current signal levels.

  Generates X_OPTICAL_ALARM event if RX or TX power exceeds thresholds.
  """
  def check_optical_alarms(device_state) do
    rx_power = DeviceState.get(device_state, "Device.Optical.Interface.1.OpticalSignalLevel")
    tx_power = DeviceState.get(device_state, "Device.Optical.Interface.1.TransmitOpticalLevel")

    lower_threshold =
      DeviceState.get(device_state, "Device.Optical.Interface.1.LowerOpticalThreshold")

    upper_threshold =
      DeviceState.get(device_state, "Device.Optical.Interface.1.UpperOpticalThreshold")

    events = []

    # Check RX power
    events =
      cond do
        lower_threshold && rx_power && rx_power < lower_threshold ->
          Logger.warning(
            "Optical RX power alarm: #{rx_power} dBm below threshold #{lower_threshold} dBm"
          )

          [
            create_event("X_OPTICAL_ALARM", "low-rx-power", %{
              rx_power: rx_power,
              threshold: lower_threshold
            })
            | events
          ]

        upper_threshold && rx_power && rx_power > upper_threshold ->
          Logger.warning(
            "Optical RX power alarm: #{rx_power} dBm above threshold #{upper_threshold} dBm"
          )

          [
            create_event("X_OPTICAL_ALARM", "high-rx-power", %{
              rx_power: rx_power,
              threshold: upper_threshold
            })
            | events
          ]

        true ->
          events
      end

    # Check TX power (typically between 0 and +5 dBm)
    events =
      cond do
        tx_power && tx_power < -3.0 ->
          Logger.warning("Optical TX power alarm: #{tx_power} dBm too low")
          [create_event("X_OPTICAL_ALARM", "low-tx-power", %{tx_power: tx_power}) | events]

        tx_power && tx_power > 7.0 ->
          Logger.warning("Optical TX power alarm: #{tx_power} dBm too high")
          [create_event("X_OPTICAL_ALARM", "high-tx-power", %{tx_power: tx_power}) | events]

        true ->
          events
      end

    events
  end

  @doc """
  Check for temperature alarms.

  PON optics typically operate between -40°C and +85°C.
  Warning at 70°C, critical at 80°C.
  """
  def check_temperature_alarm(device_state) do
    temp = DeviceState.get(device_state, "Device.Optical.Interface.1.Temperature")

    cond do
      is_nil(temp) ->
        []

      temp >= 80.0 ->
        Logger.error("Critical temperature alarm: #{temp}°C")
        [create_event("X_TEMPERATURE_ALARM", "critical", %{temperature: temp})]

      temp >= 70.0 ->
        Logger.warning("Temperature warning: #{temp}°C")
        [create_event("X_TEMPERATURE_ALARM", "warning", %{temperature: temp})]

      temp <= -30.0 ->
        Logger.warning("Low temperature warning: #{temp}°C")
        [create_event("X_TEMPERATURE_ALARM", "low", %{temperature: temp})]

      true ->
        []
    end
  end

  @doc """
  Check for supply voltage alarms.

  Typical PON ONT operates at 12V or 48V DC.
  Alarms if voltage drops significantly.
  """
  def check_voltage_alarm(device_state) do
    voltage = DeviceState.get(device_state, "Device.DeviceInfo.X_VENDOR_SupplyVoltage")

    if voltage do
      cond do
        voltage < 10.5 ->
          Logger.error("Critical voltage alarm: #{voltage}V")
          [create_event("X_VOLTAGE_ALARM", "critical-low", %{voltage: voltage})]

        voltage < 11.0 ->
          Logger.warning("Low voltage warning: #{voltage}V")
          [create_event("X_VOLTAGE_ALARM", "low", %{voltage: voltage})]

        voltage > 14.0 ->
          Logger.warning("High voltage warning: #{voltage}V")
          [create_event("X_VOLTAGE_ALARM", "high", %{voltage: voltage})]

        true ->
          []
      end
    else
      []
    end
  end

  @doc """
  Simulate dying gasp event.

  Dying gasp is a last-gasp message sent when the ONT detects power loss.
  This is typically the last message before the device goes offline.
  """
  def simulate_dying_gasp(device_state) do
    Logger.error("DYING GASP - Power loss detected!")

    # Set status to indicate power failure
    DeviceState.set(device_state, "Device.DeviceInfo.X_VENDOR_PowerStatus", "power-loss")

    event =
      create_event("X_DYING_GASP", "power-loss", %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        reason: "AC power failure detected"
      })

    :telemetry.execute(
      [:caretaker, :cpe, :event, :dying_gasp],
      %{count: 1},
      %{device_state: device_state}
    )

    [event]
  end

  @doc """
  Simulate ONU registration sequence.

  PON ONT must register with OLT before passing traffic.
  States: unregistered -> ranging -> authentication -> operational
  """
  def simulate_onu_registration(device_state, target_state \\ :operational) do
    current_state = DeviceState.get(device_state, "Device.X_VENDOR_PON.Status") || "unregistered"

    case {current_state, target_state} do
      {"unregistered", :operational} ->
        # Go through registration sequence
        events = [
          create_event("X_ONU_REGISTRATION", "ranging", %{state: "ranging"}),
          create_event("X_ONU_REGISTRATION", "authenticating", %{state: "authenticating"}),
          create_event("X_ONU_REGISTRATION", "operational", %{state: "operational"})
        ]

        DeviceState.set(device_state, "Device.X_VENDOR_PON.Status", "operational")
        DeviceState.set(device_state, "Device.Optical.Interface.1.Status", "Up")

        Logger.info("ONU registration complete")
        events

      {_, :operational} when current_state != "operational" ->
        # Fast path to operational
        DeviceState.set(device_state, "Device.X_VENDOR_PON.Status", "operational")
        DeviceState.set(device_state, "Device.Optical.Interface.1.Status", "Up")

        [create_event("X_ONU_REGISTRATION", "operational", %{state: "operational"})]

      {_, :unregistered} ->
        # Deregister
        DeviceState.set(device_state, "Device.X_VENDOR_PON.Status", "unregistered")
        DeviceState.set(device_state, "Device.Optical.Interface.1.Status", "Down")

        Logger.warning("ONU deregistered")
        [create_event("X_ONU_REGISTRATION", "deregistered", %{state: "unregistered"})]

      _ ->
        []
    end
  end

  @doc """
  Simulate link state change (up/down).

  Can be triggered by optical signal loss, OLT reboot, fiber cut, etc.
  """
  def simulate_link_state_change(device_state, new_state) when new_state in [:up, :down] do
    current_status = DeviceState.get(device_state, "Device.Optical.Interface.1.Status")
    target_status = if new_state == :up, do: "Up", else: "Down"

    if current_status != target_status do
      DeviceState.set(device_state, "Device.Optical.Interface.1.Status", target_status)

      event_code = if new_state == :up, do: "X_LINK_UP", else: "X_LINK_DOWN"
      event_type = if new_state == :up, do: "link-restored", else: "link-lost"

      Logger.info("Link state changed: #{event_type}")

      :telemetry.execute(
        [:caretaker, :cpe, :event, :link_state],
        %{state: new_state},
        %{device_state: device_state}
      )

      [create_event(event_code, event_type, %{status: target_status})]
    else
      []
    end
  end

  @doc """
  Simulate fiber cut scenario.

  Optical signal drops to near zero, multiple alarms triggered,
  link goes down, ONU deregisters.
  """
  def simulate_fiber_cut(device_state) do
    Logger.error("Simulating fiber cut scenario")

    # Drop optical RX power to -40 dBm (no signal)
    DeviceState.set(device_state, "Device.Optical.Interface.1.OpticalSignalLevel", -40.0)

    # Generate cascading events
    events = []
    events = events ++ check_optical_alarms(device_state)
    events = events ++ simulate_link_state_change(device_state, :down)
    events = events ++ simulate_onu_registration(device_state, :unregistered)

    :telemetry.execute(
      [:caretaker, :cpe, :event, :fiber_cut],
      %{count: 1},
      %{device_state: device_state}
    )

    events
  end

  @doc """
  Simulate fiber restoration after cut.

  Signal returns, alarms clear, ONU re-registers, link comes up.
  """
  def simulate_fiber_restore(device_state, target_rx_power \\ -18.5) do
    Logger.info("Simulating fiber restoration")

    # Restore optical RX power
    DeviceState.set(
      device_state,
      "Device.Optical.Interface.1.OpticalSignalLevel",
      target_rx_power
    )

    # Generate recovery events - link state first, then registration
    events = []
    events = events ++ simulate_link_state_change(device_state, :up)
    events = events ++ simulate_onu_registration(device_state, :operational)

    :telemetry.execute(
      [:caretaker, :cpe, :event, :fiber_restore],
      %{count: 1},
      %{device_state: device_state}
    )

    events
  end

  @doc """
  Generate periodic alarm checks based on current state.

  Should be called periodically (e.g., every 30 seconds) to check
  for threshold violations and generate appropriate events.
  """
  def periodic_alarm_check(device_state) do
    events = []
    events = events ++ check_optical_alarms(device_state)
    events = events ++ check_temperature_alarm(device_state)
    events = events ++ check_voltage_alarm(device_state)

    if length(events) > 0 do
      :telemetry.execute(
        [:caretaker, :cpe, :event, :alarm_check],
        %{alarm_count: length(events)},
        %{device_state: device_state, events: events}
      )
    end

    events
  end

  # Private helper to create event structure
  defp create_event(event_code, event_type, metadata) do
    %{
      event_code: event_code,
      event_type: event_type,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end
end
