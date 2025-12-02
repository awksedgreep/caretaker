defmodule Caretaker.CPE.DynamicBehavior do
  @moduledoc """
  Manages dynamic device behaviors for the simulated CPE.

  This module provides realistic device simulation including:
  - **Periodic Inform**: Scheduled Inform messages with configurable interval and jitter
  - **Dynamic Parameters**: Auto-updating parameters (UpTime, interface stats)
  - **Value Change Events**: Track parameter changes for "4 VALUE CHANGE" event generation

  ## Configuration

      behaviors = [
        periodic_inform: [interval: 300_000, jitter: 30_000],
        dynamic_params: ["Device.DeviceInfo.UpTime"],
        value_change_events: true
      ]

  ## Usage with CPE Client

      {:ok, behavior} = DynamicBehavior.start_link(
        device_state: device_state,
        behaviors: behaviors
      )

      # Start all configured behaviors
      DynamicBehavior.start(behavior)

      # Check for pending events
      events = DynamicBehavior.pending_events(behavior)

      # Clear events after sending Inform
      DynamicBehavior.clear_events(behavior)
  """

  use GenServer
  require Logger

  alias Caretaker.CPE.DeviceState

  @type behavior_config :: [
          periodic_inform: keyword(),
          dynamic_params: [String.t()],
          value_change_events: boolean()
        ]

  @type event :: %{
          code: String.t(),
          command_key: String.t()
        }

  # Default dynamic parameters that auto-update
  @default_dynamic_params [
    "Device.DeviceInfo.UpTime"
  ]

  # Interface stats parameters (simulated)
  @interface_stats [
    "Device.IP.Interface.1.Stats.BytesSent",
    "Device.IP.Interface.1.Stats.BytesReceived",
    "Device.IP.Interface.1.Stats.PacketsSent",
    "Device.IP.Interface.1.Stats.PacketsReceived"
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Start a new DynamicBehavior manager.

  Options:
  - `device_state` - DeviceState agent (required)
  - `behaviors` - Behavior configuration (optional)
  - `name` - Optional GenServer name
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    init_opts = Keyword.take(opts, [:device_state, :behaviors])

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Start all configured dynamic behaviors.
  """
  @spec start(GenServer.server()) :: :ok
  def start(server) do
    GenServer.call(server, :start)
  end

  @doc """
  Stop all dynamic behaviors.
  """
  @spec stop_behaviors(GenServer.server()) :: :ok
  def stop_behaviors(server) do
    GenServer.call(server, :stop_behaviors)
  end

  @doc """
  Get pending events for the next Inform.

  Returns list of event codes that should be included.
  """
  @spec pending_events(GenServer.server()) :: [event()]
  def pending_events(server) do
    GenServer.call(server, :pending_events)
  end

  @doc """
  Clear pending events (call after Inform is sent).
  """
  @spec clear_events(GenServer.server()) :: :ok
  def clear_events(server) do
    GenServer.call(server, :clear_events)
  end

  @doc """
  Add a pending event (e.g., from external trigger).
  """
  @spec add_event(GenServer.server(), String.t(), String.t()) :: :ok
  def add_event(server, event_code, command_key \\ "") do
    GenServer.call(server, {:add_event, event_code, command_key})
  end

  @doc """
  Record a parameter change for value change tracking.
  """
  @spec record_change(GenServer.server(), String.t(), term(), term()) :: :ok
  def record_change(server, path, old_value, new_value) do
    GenServer.cast(server, {:record_change, path, old_value, new_value})
  end

  @doc """
  Get current status of all behaviors.
  """
  @spec status(GenServer.server()) :: map()
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Trigger immediate periodic inform (for testing).
  """
  @spec trigger_periodic_inform(GenServer.server()) :: :ok
  def trigger_periodic_inform(server) do
    GenServer.call(server, :trigger_periodic_inform)
  end

  @doc """
  Update dynamic parameters manually (for testing or external triggers).
  """
  @spec update_dynamic_params(GenServer.server()) :: :ok
  def update_dynamic_params(server) do
    GenServer.call(server, :update_dynamic_params)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    device_state = Keyword.fetch!(opts, :device_state)
    behaviors = Keyword.get(opts, :behaviors, [])

    state = %{
      device_state: device_state,
      behaviors: behaviors,
      running: false,
      started_at: nil,
      pending_events: [],
      changed_params: MapSet.new(),
      timers: %{},
      # Periodic inform config
      periodic_inform: Keyword.get(behaviors, :periodic_inform),
      # Dynamic params config
      dynamic_params: Keyword.get(behaviors, :dynamic_params, @default_dynamic_params),
      # Value change tracking
      value_change_events: Keyword.get(behaviors, :value_change_events, false),
      # Stats simulation state
      stats_state: %{
        bytes_sent: 0,
        bytes_received: 0,
        packets_sent: 0,
        packets_received: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start, _from, state) do
    if state.running do
      {:reply, :ok, state}
    else
      new_state = start_behaviors(state)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:stop_behaviors, _from, state) do
    new_state = cancel_all_timers(state)
    {:reply, :ok, %{new_state | running: false}}
  end

  @impl true
  def handle_call(:pending_events, _from, state) do
    {:reply, state.pending_events, state}
  end

  @impl true
  def handle_call(:clear_events, _from, state) do
    {:reply, :ok, %{state | pending_events: [], changed_params: MapSet.new()}}
  end

  @impl true
  def handle_call({:add_event, event_code, command_key}, _from, state) do
    event = %{code: event_code, command_key: command_key}
    new_events = [event | state.pending_events] |> Enum.uniq_by(& &1.code)
    {:reply, :ok, %{state | pending_events: new_events}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      running: state.running,
      started_at: state.started_at,
      pending_events: length(state.pending_events),
      changed_params: MapSet.size(state.changed_params),
      periodic_inform_enabled: state.periodic_inform != nil,
      dynamic_params: state.dynamic_params,
      value_change_events: state.value_change_events
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:trigger_periodic_inform, _from, state) do
    new_state = do_periodic_inform(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:update_dynamic_params, _from, state) do
    new_state = do_update_dynamic_params(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:record_change, path, old_value, new_value}, state) do
    if state.value_change_events and old_value != new_value do
      :telemetry.execute(
        [:caretaker, :cpe, :param, :changed],
        %{},
        %{path: path, old_value: old_value, new_value: new_value}
      )

      new_changed = MapSet.put(state.changed_params, path)

      # Add VALUE CHANGE event if not already pending
      new_events =
        if Enum.any?(state.pending_events, &(&1.code == "4 VALUE CHANGE")) do
          state.pending_events
        else
          [%{code: "4 VALUE CHANGE", command_key: ""} | state.pending_events]
        end

      {:noreply, %{state | changed_params: new_changed, pending_events: new_events}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:periodic_inform_tick, state) do
    new_state = do_periodic_inform(state)
    {:noreply, schedule_periodic_inform(new_state)}
  end

  @impl true
  def handle_info(:dynamic_params_tick, state) do
    new_state = do_update_dynamic_params(state)
    {:noreply, schedule_dynamic_params(new_state)}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp start_behaviors(state) do
    now = DateTime.utc_now()

    state
    |> Map.put(:running, true)
    |> Map.put(:started_at, now)
    |> schedule_periodic_inform()
    |> schedule_dynamic_params()
  end

  defp cancel_all_timers(state) do
    Enum.each(state.timers, fn {_name, ref} ->
      if ref, do: Process.cancel_timer(ref)
    end)

    %{state | timers: %{}}
  end

  defp schedule_periodic_inform(state) do
    case state.periodic_inform do
      nil ->
        state

      config ->
        interval = Keyword.get(config, :interval, 300_000)
        jitter = Keyword.get(config, :jitter, 0)

        # Calculate actual delay with jitter
        jitter_amount = if jitter > 0, do: :rand.uniform(jitter), else: 0
        delay = interval + jitter_amount

        # Cancel existing timer if any
        if timer = state.timers[:periodic_inform] do
          Process.cancel_timer(timer)
        end

        ref = Process.send_after(self(), :periodic_inform_tick, delay)

        :telemetry.execute(
          [:caretaker, :cpe, :periodic_inform, :scheduled],
          %{delay_ms: delay},
          %{interval: interval, jitter: jitter}
        )

        put_in(state, [:timers, :periodic_inform], ref)
    end
  end

  defp schedule_dynamic_params(state) do
    if state.dynamic_params != [] do
      # Update dynamic params every second
      delay = 1_000

      if timer = state.timers[:dynamic_params] do
        Process.cancel_timer(timer)
      end

      ref = Process.send_after(self(), :dynamic_params_tick, delay)
      put_in(state, [:timers, :dynamic_params], ref)
    else
      state
    end
  end

  defp do_periodic_inform(state) do
    # Add "2 PERIODIC" event
    event = %{code: "2 PERIODIC", command_key: ""}
    new_events = [event | state.pending_events] |> Enum.uniq_by(& &1.code)

    :telemetry.execute(
      [:caretaker, :cpe, :periodic_inform, :triggered],
      %{},
      %{pending_events: length(new_events)}
    )

    %{state | pending_events: new_events}
  end

  defp do_update_dynamic_params(state) do
    device_state = state.device_state

    # Update UpTime if tracked
    if "Device.DeviceInfo.UpTime" in state.dynamic_params and state.started_at do
      uptime = DateTime.diff(DateTime.utc_now(), state.started_at, :second)
      DeviceState.set(device_state, "Device.DeviceInfo.UpTime", uptime)
    end

    # Update interface stats if tracked
    new_stats_state =
      Enum.reduce(@interface_stats, state.stats_state, fn param, acc ->
        if param in state.dynamic_params do
          update_interface_stat(device_state, param, acc)
        else
          acc
        end
      end)

    :telemetry.execute(
      [:caretaker, :cpe, :dynamic_params, :updated],
      %{},
      %{params: state.dynamic_params}
    )

    %{state | stats_state: new_stats_state}
  end

  defp update_interface_stat(device_state, param, stats_state) do
    cond do
      String.ends_with?(param, "BytesSent") ->
        # Simulate ~100KB/s traffic variation
        increment = :rand.uniform(100_000) + 50_000
        new_value = stats_state.bytes_sent + increment
        DeviceState.set(device_state, param, new_value)
        %{stats_state | bytes_sent: new_value}

      String.ends_with?(param, "BytesReceived") ->
        # Simulate ~200KB/s traffic variation
        increment = :rand.uniform(200_000) + 100_000
        new_value = stats_state.bytes_received + increment
        DeviceState.set(device_state, param, new_value)
        %{stats_state | bytes_received: new_value}

      String.ends_with?(param, "PacketsSent") ->
        increment = :rand.uniform(100) + 50
        new_value = stats_state.packets_sent + increment
        DeviceState.set(device_state, param, new_value)
        %{stats_state | packets_sent: new_value}

      String.ends_with?(param, "PacketsReceived") ->
        increment = :rand.uniform(150) + 75
        new_value = stats_state.packets_received + increment
        DeviceState.set(device_state, param, new_value)
        %{stats_state | packets_received: new_value}

      true ->
        stats_state
    end
  end
end
