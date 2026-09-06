defmodule Caretaker.CPE.Events.DOCSIS do
  @moduledoc """
  DOCSIS cable modem specific event generation and simulation.

  Generates realistic TR-069 events for DOCSIS 3.0/3.1 cable modems including:
  - Standard TR-069 events (BOOT, PERIODIC, VALUE CHANGE)
  - DOCSIS-specific events (registration, ranging, timeouts)
  - Channel bonding events
  - Config file download events
  - Upstream/downstream alarms
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

  @docsis_events [
    "X_CM_REGISTRATION",
    "X_CM_OPERATIONAL",
    "X_T3_TIMEOUT",
    "X_T4_TIMEOUT",
    "X_RANGING_FAILURE",
    "X_CONFIG_FILE_DOWNLOAD",
    "X_PARTIAL_SERVICE",
    "X_CHANNEL_BONDING",
    "X_FEC_ERRORS",
    "X_SNR_DEGRADATION"
  ]

  @registration_states [
    "other",
    "notReady",
    "notSynchronized",
    "phySynchronized",
    "usParametersAcquired",
    "rangingComplete",
    "ipComplete",
    "todEstablished",
    "securityEstablished",
    "paramTransferComplete",
    "registrationComplete",
    "operational",
    "accessDenied"
  ]

  @doc """
  Returns all supported event codes for DOCSIS devices.
  """
  def supported_events do
    @standard_events ++ @docsis_events
  end

  @doc """
  Returns valid DOCSIS registration states.
  """
  def registration_states, do: @registration_states

  @doc """
  Simulate complete cable modem registration sequence.

  DOCSIS CM must progress through multiple states before becoming operational.
  """
  def simulate_registration_flow(device_state) do
    Logger.info("Starting DOCSIS registration sequence")

    events =
      Enum.map(@registration_states, fn state ->
        create_event("X_CM_REGISTRATION", state, %{state: state})
      end)

    # Update device state through registration phases
    DeviceState.set(device_state, "Device.Docsis.Status", "Ranging")
    Process.sleep(100)

    DeviceState.set(device_state, "Device.Docsis.Status", "RangingComplete")
    Process.sleep(100)

    DeviceState.set(device_state, "Device.Docsis.Status", "Operational")
    DeviceState.set(device_state, "Device.Docsis.BootState", "Operational")

    Logger.info("DOCSIS registration complete - modem operational")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :docsis_registration],
      %{duration_ms: 200},
      %{device_state: device_state}
    )

    events
  end

  @doc """
  Simulate fast registration (already registered, just re-connecting).
  """
  def simulate_fast_registration(device_state) do
    Logger.info("DOCSIS fast registration")

    DeviceState.set(device_state, "Device.Docsis.Status", "Operational")
    DeviceState.set(device_state, "Device.Docsis.BootState", "Operational")

    [create_event("X_CM_OPERATIONAL", "fast-registration", %{state: "operational"})]
  end

  @doc """
  Simulate T3 timeout (upstream ranging request timeout).

  T3 timeouts indicate the CM is not receiving ranging responses from CMTS.
  Often caused by upstream noise or CMTS issues.
  """
  def simulate_t3_timeout(device_state, channel_id) do
    Logger.warning("T3 timeout on upstream channel #{channel_id}")

    # Increment error counter
    path = "Device.Docsis.Upstream.#{channel_id}.Stats.T3Timeouts"
    current = DeviceState.get(device_state, path) || 0
    DeviceState.set(device_state, path, current + 1)

    :telemetry.execute(
      [:caretaker, :cpe, :event, :t3_timeout],
      %{count: 1, channel_id: channel_id},
      %{device_state: device_state}
    )

    [
      create_event("X_T3_TIMEOUT", "ranging-timeout", %{
        channel_id: channel_id,
        total_timeouts: current + 1
      })
    ]
  end

  @doc """
  Simulate T4 timeout (upstream ranging response timeout).

  T4 timeouts indicate the CM sent ranging request but didn't get response.
  Can lead to re-initialization if persistent.
  """
  def simulate_t4_timeout(device_state, channel_id) do
    Logger.warning("T4 timeout on upstream channel #{channel_id}")

    # Increment error counter
    path = "Device.Docsis.Upstream.#{channel_id}.Stats.T4Timeouts"
    current = DeviceState.get(device_state, path) || 0
    DeviceState.set(device_state, path, current + 1)

    :telemetry.execute(
      [:caretaker, :cpe, :event, :t4_timeout],
      %{count: 1, channel_id: channel_id},
      %{device_state: device_state}
    )

    [
      create_event("X_T4_TIMEOUT", "ranging-response-timeout", %{
        channel_id: channel_id,
        total_timeouts: current + 1
      })
    ]
  end

  @doc """
  Simulate ranging failure.

  Complete ranging failure - CM cannot establish communication with CMTS.
  """
  def simulate_ranging_failure(device_state, reason \\ "no-response") do
    Logger.error("DOCSIS ranging failure: #{reason}")

    DeviceState.set(device_state, "Device.Docsis.Status", "RangingFailure")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :ranging_failure],
      %{count: 1},
      %{device_state: device_state, reason: reason}
    )

    [create_event("X_RANGING_FAILURE", reason, %{reason: reason})]
  end

  @doc """
  Simulate config file download from TFTP/HTTP server.

  Occurs during registration after TOD (Time of Day) is established.
  """
  def simulate_config_download(device_state, filename \\ "gold.cfg", success \\ true) do
    Logger.info("Downloading config file: #{filename}")

    if success do
      DeviceState.set(device_state, "Device.Docsis.Interface.1.ConfigFileName", filename)
      DeviceState.set(device_state, "Device.Docsis.Status", "Operational")

      :telemetry.execute(
        [:caretaker, :cpe, :event, :config_download],
        %{success: 1},
        %{device_state: device_state, filename: filename}
      )

      [create_event("X_CONFIG_FILE_DOWNLOAD", "success", %{filename: filename})]
    else
      Logger.error("Config file download failed: #{filename}")

      :telemetry.execute(
        [:caretaker, :cpe, :event, :config_download],
        %{success: 0},
        %{device_state: device_state, filename: filename}
      )

      [create_event("X_CONFIG_FILE_DOWNLOAD", "failure", %{filename: filename})]
    end
  end

  @doc """
  Check for SNR degradation on downstream channels.

  Good SNR: > 35 dB
  Marginal: 30-35 dB
  Poor: < 30 dB
  """
  def check_snr_alarms(device_state) do
    downstream_count =
      DeviceState.get(device_state, "Device.Docsis.DownstreamNumberOfEntries") || 32

    events =
      for ch <- 1..downstream_count, reduce: [] do
        acc ->
          snr =
            DeviceState.get(device_state, "Device.Docsis.Downstream.#{ch}.SNRLevel") ||
              DeviceState.get(device_state, "Device.Docsis.Downstream.#{ch}.SNR")

          cond do
            snr && snr < 25.0 ->
              Logger.error("Critical SNR on downstream channel #{ch}: #{snr} dB")
              [create_event("X_SNR_DEGRADATION", "critical", %{channel_id: ch, snr: snr}) | acc]

            snr && snr < 30.0 ->
              Logger.warning("Low SNR on downstream channel #{ch}: #{snr} dB")
              [create_event("X_SNR_DEGRADATION", "warning", %{channel_id: ch, snr: snr}) | acc]

            true ->
              acc
          end
      end

    if length(events) > 0 do
      :telemetry.execute(
        [:caretaker, :cpe, :event, :snr_alarm],
        %{affected_channels: length(events)},
        %{device_state: device_state}
      )
    end

    events
  end

  @doc """
  Check for excessive FEC (Forward Error Correction) errors.

  High FEC errors indicate RF plant issues but can still maintain service.
  """
  def check_fec_errors(device_state) do
    downstream_count =
      DeviceState.get(device_state, "Device.Docsis.DownstreamNumberOfEntries") || 32

    events =
      for ch <- 1..downstream_count, reduce: [] do
        acc ->
          correctable =
            DeviceState.get(
              device_state,
              "Device.Docsis.Downstream.#{ch}.Stats.CorrectableErrors"
            ) || DeviceState.get(device_state, "Device.Docsis.Downstream.#{ch}.Correcteds") || 0

          uncorrectable =
            DeviceState.get(
              device_state,
              "Device.Docsis.Downstream.#{ch}.Stats.UncorrectableErrors"
            ) || DeviceState.get(device_state, "Device.Docsis.Downstream.#{ch}.Uncorrectables") || 0

          cond do
            uncorrectable > 100 ->
              Logger.error("High uncorrectable FEC errors on channel #{ch}: #{uncorrectable}")

              [
                create_event("X_FEC_ERRORS", "uncorrectable", %{
                  channel_id: ch,
                  count: uncorrectable
                })
                | acc
              ]

            correctable > 10000 ->
              Logger.warning("High correctable FEC errors on channel #{ch}: #{correctable}")

              [
                create_event("X_FEC_ERRORS", "correctable", %{channel_id: ch, count: correctable})
                | acc
              ]

            true ->
              acc
          end
      end

    events
  end

  @doc """
  Simulate partial service mode.

  Some channels locked, others not - degraded but functional service.
  """
  def simulate_partial_service(device_state, locked_channels \\ 16) do
    Logger.warning("Entering partial service mode - #{locked_channels} channels locked")

    DeviceState.set(device_state, "Device.Docsis.Status", "PartialService")

    # Set some channels to unlocked
    downstream_count =
      DeviceState.get(device_state, "Device.Docsis.DownstreamNumberOfEntries") || 32

    for ch <- (locked_channels + 1)..downstream_count do
      DeviceState.set(device_state, "Device.Docsis.Downstream.#{ch}.LockStatus", "Unlocked")
    end

    :telemetry.execute(
      [:caretaker, :cpe, :event, :partial_service],
      %{locked_channels: locked_channels, total_channels: downstream_count},
      %{device_state: device_state}
    )

    [
      create_event("X_PARTIAL_SERVICE", "degraded", %{
        locked_channels: locked_channels,
        total_channels: downstream_count
      })
    ]
  end

  @doc """
  Simulate channel bonding change.

  DOCSIS 3.0+ bonds multiple channels for increased throughput.
  """
  def simulate_channel_bonding(device_state, bonded_channels) do
    Logger.info("Channel bonding: #{bonded_channels} channels bonded")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :channel_bonding],
      %{bonded_channels: bonded_channels},
      %{device_state: device_state}
    )

    [create_event("X_CHANNEL_BONDING", "updated", %{bonded_channels: bonded_channels})]
  end

  @doc """
  Simulate plant issue (ingress noise, amplifier problem).

  Causes cascading issues: SNR degradation, FEC errors, possible T3/T4 timeouts.
  """
  def simulate_plant_issue(device_state) do
    Logger.error("Simulating RF plant issue")

    events = []

    # Degrade SNR on multiple channels
    downstream_count =
      DeviceState.get(device_state, "Device.Docsis.DownstreamNumberOfEntries") || 32

    for ch <- 1..downstream_count do
      current_snr = DeviceState.get(device_state, "Device.Docsis.Downstream.#{ch}.SNR") || 38.0
      degraded_snr = max(current_snr - 10.0, 20.0)
      DeviceState.set(device_state, "Device.Docsis.Downstream.#{ch}.SNR", degraded_snr)
    end

    # Generate events
    events = events ++ check_snr_alarms(device_state)

    # Simulate some T3/T4 timeouts on upstream
    events = events ++ simulate_t3_timeout(device_state, 1)
    events = events ++ simulate_t4_timeout(device_state, 2)

    :telemetry.execute(
      [:caretaker, :cpe, :event, :plant_issue],
      %{event_count: length(events)},
      %{device_state: device_state}
    )

    events
  end

  @doc """
  Restore normal operation after plant issue.
  """
  def simulate_plant_restore(device_state) do
    Logger.info("RF plant issue resolved")

    # Restore SNR levels
    downstream_count =
      DeviceState.get(device_state, "Device.Docsis.DownstreamNumberOfEntries") || 32

    for ch <- 1..downstream_count do
      DeviceState.set(
        device_state,
        "Device.Docsis.Downstream.#{ch}.SNR",
        38.0 + :rand.uniform() * 3.0
      )

      DeviceState.set(device_state, "Device.Docsis.Downstream.#{ch}.LockStatus", "Locked")
    end

    DeviceState.set(device_state, "Device.Docsis.Status", "Operational")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :plant_restore],
      %{count: 1},
      %{device_state: device_state}
    )

    [create_event("X_CM_OPERATIONAL", "restored", %{state: "operational"})]
  end

  @doc """
  Periodic health check for DOCSIS parameters.

  Should be called periodically to detect issues.
  """
  def periodic_health_check(device_state) do
    events = []
    events = events ++ check_snr_alarms(device_state)
    events = events ++ check_fec_errors(device_state)

    if length(events) > 0 do
      :telemetry.execute(
        [:caretaker, :cpe, :event, :health_check],
        %{issue_count: length(events)},
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
