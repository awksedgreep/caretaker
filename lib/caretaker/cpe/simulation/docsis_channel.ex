defmodule Caretaker.CPE.Simulation.DocsisChannel do
  @moduledoc """
  Simulates DOCSIS downstream and upstream channel conditions for cable modems.

  This module provides realistic simulation of:
  - Downstream channel SNR variations
  - Upstream power level adjustments
  - Channel lock status
  - Error counters (corrected/uncorrectable)
  - T3/T4 timeout events
  - Partial service scenarios

  ## Usage

      # Update all channel stats with normal variations
      device_state = DocsisChannel.update(device_state)

      # Simulate plant issues (ingress noise)
      device_state = DocsisChannel.update(device_state, scenario: :plant_issue)

      # Simulate ranging problems
      device_state = DocsisChannel.update(device_state, scenario: :ranging_issue)
  """

  require Logger
  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.Events.DOCSIS

  @type scenario :: :normal | :plant_issue | :ranging_issue | :partial_service

  @downstream_channels 1..32
  @upstream_channels 1..8

  @doc """
  Update all DOCSIS channel statistics.

  ## Options

  - `:scenario` - Simulation scenario
  - `:affected_channels` - List of channel numbers to affect (default: all)
  """
  @spec update(pid(), keyword()) :: :ok
  def update(device_state, opts \\ []) do
    scenario = Keyword.get(opts, :scenario, :normal)
    affected_ds = Keyword.get(opts, :affected_downstream, Enum.to_list(@downstream_channels))
    affected_us = Keyword.get(opts, :affected_upstream, Enum.to_list(@upstream_channels))

    # Update downstream channels
    Enum.each(@downstream_channels, fn ch ->
      if ch in affected_ds do
        update_downstream_channel(device_state, ch, scenario)
      else
        update_downstream_channel(device_state, ch, :normal)
      end
    end)

    # Update upstream channels
    Enum.each(@upstream_channels, fn ch ->
      if ch in affected_us do
        update_upstream_channel(device_state, ch, scenario)
      else
        update_upstream_channel(device_state, ch, :normal)
      end
    end)

    # Update overall status
    update_modem_status(device_state, scenario)

    # Check for DOCSIS-specific events
    _events = DOCSIS.periodic_health_check(device_state)

    :telemetry.execute(
      [:caretaker, :cpe, :simulation, :docsis_channels],
      %{},
      %{scenario: scenario}
    )

    :ok
  end

  # Update downstream channel parameters
  defp update_downstream_channel(device_state, ch, scenario) do
    path = "Device.Docsis.Downstream.#{ch}"

    current_snr = DeviceState.get(device_state, "#{path}.SNRLevel") || 38.5
    current_power = DeviceState.get(device_state, "#{path}.PowerLevel") || 2.5
    current_correcteds = DeviceState.get(device_state, "#{path}.Correcteds") || 100
    current_uncorrectables = DeviceState.get(device_state, "#{path}.Uncorrectables") || 0

    # Simulate SNR variations
    new_snr = simulate_downstream_snr(current_snr, scenario)
    new_power = simulate_downstream_power(current_power, scenario)

    # Simulate error counters
    {new_correcteds, new_uncorrectables} =
      simulate_error_counters(current_correcteds, current_uncorrectables, scenario)

    # Determine lock status
    lock_status = if new_snr > 30.0, do: "Locked", else: "Unlocked"
    channel_status = if new_snr > 30.0, do: "Up", else: "Down"

    # Update parameters
    DeviceState.set(device_state, "#{path}.SNRLevel", new_snr)
    DeviceState.set(device_state, "#{path}.PowerLevel", new_power)
    DeviceState.set(device_state, "#{path}.Correcteds", new_correcteds)
    DeviceState.set(device_state, "#{path}.Uncorrectables", new_uncorrectables)
    DeviceState.set(device_state, "#{path}.LockStatus", lock_status)
    DeviceState.set(device_state, "#{path}.Status", channel_status)

    # Increment octet counter
    current_octets = DeviceState.get(device_state, "#{path}.Octets") || 0
    new_octets = current_octets + :rand.uniform(1_000_000) + 500_000
    DeviceState.set(device_state, "#{path}.Octets", new_octets)
  end

  # Update upstream channel parameters
  defp update_upstream_channel(device_state, ch, scenario) do
    path = "Device.Docsis.Upstream.#{ch}"

    current_power = DeviceState.get(device_state, "#{path}.PowerLevel") || 42.0
    current_t3 = DeviceState.get(device_state, "#{path}.T3Timeouts") || 0
    current_t4 = DeviceState.get(device_state, "#{path}.T4Timeouts") || 0

    # Simulate upstream power (CMTS adjusts this)
    new_power = simulate_upstream_power(current_power, scenario)

    # Simulate timeout events
    {new_t3, new_t4} = simulate_timeouts(current_t3, current_t4, scenario)

    # Determine status
    ranging_status = if scenario == :ranging_issue, do: "RangingInProgress", else: "Success"
    channel_status = if new_t3 > 10 or new_t4 > 10, do: "Down", else: "Up"

    # Update parameters
    DeviceState.set(device_state, "#{path}.PowerLevel", new_power)
    DeviceState.set(device_state, "#{path}.T3Timeouts", new_t3)
    DeviceState.set(device_state, "#{path}.T4Timeouts", new_t4)
    DeviceState.set(device_state, "#{path}.RangingStatus", ranging_status)
    DeviceState.set(device_state, "#{path}.Status", channel_status)

    # Log ranging issues
    if new_t3 > current_t3 do
      Logger.warning("T3 timeout on upstream channel #{ch}")

      :telemetry.execute(
        [:caretaker, :cpe, :simulation, :docsis_timeout],
        %{channel: ch},
        %{type: :t3, scenario: scenario}
      )
    end

    if new_t4 > current_t4 do
      Logger.warning("T4 timeout on upstream channel #{ch}")

      :telemetry.execute(
        [:caretaker, :cpe, :simulation, :docsis_timeout],
        %{channel: ch},
        %{type: :t4, scenario: scenario}
      )
    end
  end

  # Simulate downstream SNR
  defp simulate_downstream_snr(current, scenario) do
    base_variation = :rand.normal() * 0.3

    scenario_effect =
      case scenario do
        :normal -> 0.0
        :plant_issue -> -3.0 + :rand.normal() * 1.5
        :partial_service -> -5.0 + :rand.normal() * 2.0
        _ -> 0.0
      end

    new_value = current + base_variation + scenario_effect
    Float.round(max(25.0, min(45.0, new_value)), 1)
  end

  # Simulate downstream power level
  defp simulate_downstream_power(current, scenario) do
    base_variation = :rand.normal() * 0.2

    scenario_effect =
      case scenario do
        :plant_issue -> -1.0
        :partial_service -> -2.0
        _ -> 0.0
      end

    new_value = current + base_variation + scenario_effect
    Float.round(max(-15.0, min(15.0, new_value)), 1)
  end

  # Simulate error counters
  defp simulate_error_counters(correcteds, uncorrectables, scenario) do
    # Normal increment
    corrected_increment = :rand.uniform(10) + 5

    # Scenario-based uncorrectable errors
    uncorrectable_increment =
      case scenario do
        :plant_issue ->
          if :rand.uniform(100) < 30, do: 1, else: 0

        :partial_service ->
          if :rand.uniform(100) < 50, do: :rand.uniform(3), else: 0

        _ ->
          if :rand.uniform(1000) < 5, do: 1, else: 0
      end

    {correcteds + corrected_increment, uncorrectables + uncorrectable_increment}
  end

  # Simulate upstream power adjustments
  defp simulate_upstream_power(current, scenario) do
    # CMTS adjusts power based on received signal
    base_adjustment = :rand.normal() * 0.5

    scenario_effect =
      case scenario do
        :plant_issue -> 2.0
        :ranging_issue -> 3.0
        _ -> 0.0
      end

    new_value = current + base_adjustment + scenario_effect
    # Typical range: 35-51 dBmV
    Float.round(max(35.0, min(51.0, new_value)), 1)
  end

  # Simulate timeout events
  defp simulate_timeouts(t3, t4, scenario) do
    t3_increment =
      case scenario do
        :ranging_issue -> if :rand.uniform(100) < 50, do: 1, else: 0
        :plant_issue -> if :rand.uniform(100) < 20, do: 1, else: 0
        _ -> 0
      end

    t4_increment =
      case scenario do
        :ranging_issue -> if :rand.uniform(100) < 30, do: 1, else: 0
        :plant_issue -> if :rand.uniform(100) < 10, do: 1, else: 0
        _ -> 0
      end

    {t3 + t3_increment, t4 + t4_increment}
  end

  # Update overall modem status
  defp update_modem_status(device_state, scenario) do
    status =
      case scenario do
        :normal -> "Operational"
        :plant_issue -> "Operational"
        :ranging_issue -> "Ranging"
        :partial_service -> "PartialService"
      end

    boot_state =
      case scenario do
        :ranging_issue -> "Ranging"
        _ -> "Operational"
      end

    DeviceState.set(device_state, "Device.Docsis.Status", status)
    DeviceState.set(device_state, "Device.Docsis.BootState", boot_state)
  end

  @doc """
  Simulate cable modem registration flow.

  This simulates the boot sequence from scanning to operational.
  """
  @spec simulate_registration(pid()) :: :ok
  def simulate_registration(device_state) do
    stages = [
      {"Scanning", 2000},
      {"SyncAcquired", 1000},
      {"Ranging", 3000},
      {"RangingComplete", 500},
      {"DHCPv4", 2000},
      {"TOD", 1000},
      {"TFTP", 5000},
      {"Operational", 0}
    ]

    Enum.each(stages, fn {stage, delay} ->
      DeviceState.set(device_state, "Device.Docsis.BootState", stage)

      Logger.info("CM registration stage: #{stage}")

      :telemetry.execute(
        [:caretaker, :cpe, :simulation, :docsis_registration],
        %{},
        %{stage: stage}
      )

      if delay > 0, do: Process.sleep(delay)
    end)

    DeviceState.set(device_state, "Device.Docsis.Status", "Operational")
    :ok
  end

  @doc """
  Get current DOCSIS status summary.
  """
  @spec status(pid()) :: map()
  def status(device_state) do
    # Sample a few channels for overview
    ds_snr_1 = DeviceState.get(device_state, "Device.Docsis.Downstream.1.SNRLevel")
    us_power_1 = DeviceState.get(device_state, "Device.Docsis.Upstream.1.PowerLevel")

    %{
      status: DeviceState.get(device_state, "Device.Docsis.Status"),
      boot_state: DeviceState.get(device_state, "Device.Docsis.BootState"),
      downstream_snr: ds_snr_1,
      upstream_power: us_power_1,
      downstream_channels: Enum.count(@downstream_channels),
      upstream_channels: Enum.count(@upstream_channels)
    }
  end
end
