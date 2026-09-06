defmodule Caretaker.CPE.Fleet do
  @moduledoc """
  Manages a fleet of simulated CPE devices for load testing and ACS validation.

  The Fleet module provides:
  - **Spawn N devices** with different profiles and staggered timing
  - **Fleet-wide operations** (stop all, trigger inform, update params)
  - **Aggregate metrics** (connected count, session stats, memory usage)
  - **Per-device control** (stop specific device, trigger events)

  ## Usage

      # Start a fleet of 100 devices
      {:ok, fleet} = Fleet.start_link(
        acs_url: "http://localhost:4000/cwmp",
        count: 100,
        profiles: [
          {60, :fiber_ont},    # 60% fiber ONTs
          {40, :cable_modem}   # 40% cable modems
        ],
        connection_delay: 50..200  # ms between device spawns
      )

      # Check fleet status
      Fleet.stats(fleet)
      # => %{total: 100, spawned: 100, connected: 98, sessions: 450, ...}

      # Control specific devices
      Fleet.stop_device(fleet, "SN-050")
      Fleet.trigger_inform(fleet, "SN-023", ["4 VALUE CHANGE"])

      # Fleet-wide operations
      Fleet.trigger_all_informs(fleet, ["2 PERIODIC"])
      Fleet.stop_all(fleet)
  """

  use GenServer
  require Logger

  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.DynamicBehavior

  @type profile :: :fiber_ont | :cable_modem | :router | :custom | map()
  @type device_info :: %{
          serial_number: String.t(),
          profile: profile(),
          state: :spawned | :connecting | :connected | :disconnected | :stopped,
          device_state: pid() | nil,
          dynamic_behavior: pid() | nil,
          sessions: non_neg_integer(),
          last_inform: DateTime.t() | nil
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Start a new Fleet manager.

  Options:
  - `acs_url` - ACS endpoint URL (required)
  - `count` - Number of devices to spawn (default: 10)
  - `profiles` - List of {percentage, profile} tuples (default: all fiber_ont)
  - `connection_delay` - Delay between device spawns in ms (default: 100..500)
  - `oui_prefix` - OUI prefix for generated devices (default: "FLEET0")
  - `product_class` - Product class (default: "SimulatedCPE")
  - `behaviors` - DynamicBehavior config for all devices (optional)
  - `auto_start` - Automatically spawn devices on start (default: false)
  - `name` - Optional GenServer name
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    init_opts = Keyword.drop(opts, [:name])

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @doc """
  Spawn all configured devices.
  """
  @spec spawn_devices(GenServer.server()) :: {:ok, non_neg_integer()}
  def spawn_devices(server) do
    GenServer.call(server, :spawn_devices, :infinity)
  end

  @doc """
  Stop all devices and clean up.
  """
  @spec stop_all(GenServer.server()) :: :ok
  def stop_all(server) do
    GenServer.call(server, :stop_all, :infinity)
  end

  @doc """
  Stop a specific device by serial number.
  """
  @spec stop_device(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  def stop_device(server, serial_number) do
    GenServer.call(server, {:stop_device, serial_number})
  end

  @doc """
  Trigger an Inform for a specific device.
  """
  @spec trigger_inform(GenServer.server(), String.t(), [String.t()]) :: :ok | {:error, :not_found}
  def trigger_inform(server, serial_number, events \\ ["2 PERIODIC"]) do
    GenServer.call(server, {:trigger_inform, serial_number, events})
  end

  @doc """
  Trigger a connection request for a specific device.

  This adds a "6 CONNECTION REQUEST" event and is typically called by the
  ConnectionRequestServer when an ACS sends a connection request.
  """
  @spec trigger_connection_request(GenServer.server(), String.t()) ::
          :ok | {:error, :not_found | :no_behavior}
  def trigger_connection_request(server, serial_number) do
    GenServer.call(server, {:trigger_connection_request, serial_number})
  end

  @doc """
  Trigger Inform for all devices.
  """
  @spec trigger_all_informs(GenServer.server(), [String.t()]) :: :ok
  def trigger_all_informs(server, events \\ ["2 PERIODIC"]) do
    GenServer.call(server, {:trigger_all_informs, events}, :infinity)
  end

  @doc """
  Update a parameter on a specific device.
  """
  @spec update_param(GenServer.server(), String.t(), String.t(), term()) ::
          :ok | {:error, :not_found}
  def update_param(server, serial_number, path, value) do
    GenServer.call(server, {:update_param, serial_number, path, value})
  end

  @doc """
  Update a parameter on all devices.
  """
  @spec update_all_params(GenServer.server(), String.t(), term()) :: :ok
  def update_all_params(server, path, value) do
    GenServer.call(server, {:update_all_params, path, value}, :infinity)
  end

  @doc """
  Get fleet statistics.
  """
  @spec stats(GenServer.server()) :: map()
  def stats(server) do
    GenServer.call(server, :stats)
  end

  @doc """
  Get list of all devices with their current state.
  """
  @spec list_devices(GenServer.server()) :: [device_info()]
  def list_devices(server) do
    GenServer.call(server, :list_devices)
  end

  @doc """
  Get info for a specific device.
  """
  @spec get_device(GenServer.server(), String.t()) :: {:ok, device_info()} | {:error, :not_found}
  def get_device(server, serial_number) do
    GenServer.call(server, {:get_device, serial_number})
  end

  @doc """
  Add a new device to the fleet dynamically.
  """
  @spec add_device(GenServer.server(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def add_device(server, opts \\ []) do
    GenServer.call(server, {:add_device, opts})
  end

  @doc """
  Run one CWMP session for a device against the fleet's `acs_url`.

  The session runs in a background task using `Caretaker.CPE.Client`; the device
  is marked `:connecting`, then `:connected` with its session count incremented
  when the session completes. Requires a Finch pool (started on demand).
  """
  @spec run_session(GenServer.server(), String.t(), [String.t()]) :: :ok | {:error, :not_found}
  def run_session(server, serial_number, events \\ ["2 PERIODIC"]) do
    GenServer.call(server, {:run_session, serial_number, events})
  end

  @doc """
  Run a CWMP session for every spawned device against the fleet's `acs_url`.
  Returns the number of sessions started.
  """
  @spec run_all_sessions(GenServer.server(), [String.t()]) :: {:ok, non_neg_integer()}
  def run_all_sessions(server, events \\ ["2 PERIODIC"]) do
    GenServer.call(server, {:run_all_sessions, events})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    acs_url = Keyword.fetch!(opts, :acs_url)
    count = Keyword.get(opts, :count, 10)
    profiles = Keyword.get(opts, :profiles, [{100, :fiber_ont}])
    connection_delay = Keyword.get(opts, :connection_delay, 100..500)
    oui_prefix = Keyword.get(opts, :oui_prefix, "FLEET0")
    product_class = Keyword.get(opts, :product_class, "SimulatedCPE")
    behaviors = Keyword.get(opts, :behaviors, [])
    auto_start = Keyword.get(opts, :auto_start, false)

    state = %{
      acs_url: acs_url,
      count: count,
      profiles: normalize_profiles(profiles),
      connection_delay: connection_delay,
      oui_prefix: oui_prefix,
      product_class: product_class,
      behaviors: behaviors,
      devices: %{},
      spawned: false,
      started_at: DateTime.utc_now(),
      total_sessions: 0,
      memory_before: nil
    }

    :telemetry.execute(
      [:caretaker, :fleet, :init],
      %{count: count},
      %{acs_url: acs_url, profiles: profiles}
    )

    if auto_start do
      send(self(), :auto_spawn)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:spawn_devices, _from, state) do
    if state.spawned do
      {:reply, {:ok, map_size(state.devices)}, state}
    else
      memory_before = :erlang.memory(:total)
      new_state = do_spawn_devices(%{state | memory_before: memory_before})

      :telemetry.execute(
        [:caretaker, :fleet, :spawned],
        %{count: map_size(new_state.devices)},
        %{acs_url: new_state.acs_url}
      )

      {:reply, {:ok, map_size(new_state.devices)}, new_state}
    end
  end

  @impl true
  def handle_call(:stop_all, _from, state) do
    new_state = do_stop_all(state)

    :telemetry.execute(
      [:caretaker, :fleet, :stopped],
      %{count: map_size(state.devices)},
      %{}
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:stop_device, serial_number}, _from, state) do
    case Map.get(state.devices, serial_number) do
      nil ->
        {:reply, {:error, :not_found}, state}

      device ->
        new_device = stop_device_processes(device)
        new_devices = Map.put(state.devices, serial_number, new_device)
        {:reply, :ok, %{state | devices: new_devices}}
    end
  end

  @impl true
  def handle_call({:trigger_inform, serial_number, events}, _from, state) do
    case Map.get(state.devices, serial_number) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{dynamic_behavior: nil} ->
        {:reply, {:error, :no_behavior}, state}

      %{dynamic_behavior: behavior} = device when is_pid(behavior) ->
        if Process.alive?(behavior) do
          Enum.each(events, fn event ->
            DynamicBehavior.add_event(behavior, event, "")
          end)

          new_device = %{device | last_inform: DateTime.utc_now()}
          new_devices = Map.put(state.devices, serial_number, new_device)
          {:reply, :ok, %{state | devices: new_devices}}
        else
          {:reply, {:error, :behavior_dead}, state}
        end

      _ ->
        {:reply, {:error, :no_behavior}, state}
    end
  end

  @impl true
  def handle_call({:trigger_connection_request, serial_number}, _from, state) do
    case Map.get(state.devices, serial_number) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{dynamic_behavior: nil} ->
        {:reply, {:error, :no_behavior}, state}

      %{dynamic_behavior: behavior} = device when is_pid(behavior) ->
        if Process.alive?(behavior) do
          DynamicBehavior.add_event(behavior, "6 CONNECTION REQUEST", "")
          new_device = %{device | last_inform: DateTime.utc_now()}
          new_devices = Map.put(state.devices, serial_number, new_device)
          {:reply, :ok, %{state | devices: new_devices}}
        else
          {:reply, {:error, :behavior_dead}, state}
        end

      _ ->
        {:reply, {:error, :no_behavior}, state}
    end
  end

  @impl true
  def handle_call({:trigger_all_informs, events}, _from, state) do
    new_devices =
      Map.new(state.devices, fn {sn, device} ->
        case device.dynamic_behavior do
          nil ->
            {sn, device}

          behavior when is_pid(behavior) ->
            if Process.alive?(behavior) do
              Enum.each(events, fn event ->
                DynamicBehavior.add_event(behavior, event, "")
              end)

              {sn, %{device | last_inform: DateTime.utc_now()}}
            else
              {sn, device}
            end

          _ ->
            {sn, device}
        end
      end)

    {:reply, :ok, %{state | devices: new_devices}}
  end

  @impl true
  def handle_call({:update_param, serial_number, path, value}, _from, state) do
    case Map.get(state.devices, serial_number) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{device_state: nil} ->
        {:reply, {:error, :no_state}, state}

      %{device_state: device_state} when is_pid(device_state) ->
        if Process.alive?(device_state) do
          DeviceState.set(device_state, path, value)
          {:reply, :ok, state}
        else
          {:reply, {:error, :state_dead}, state}
        end

      _ ->
        {:reply, {:error, :no_state}, state}
    end
  end

  @impl true
  def handle_call({:update_all_params, path, value}, _from, state) do
    Enum.each(state.devices, fn {_sn, device} ->
      case device.device_state do
        nil ->
          :ok

        pid when is_pid(pid) ->
          if Process.alive?(pid), do: DeviceState.set(pid, path, value)

        _ ->
          :ok
      end
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    memory_after = :erlang.memory(:total)

    stats = %{
      total: state.count,
      spawned: map_size(state.devices),
      connected: count_by_state(state.devices, :connected),
      connecting: count_by_state(state.devices, :connecting),
      disconnected: count_by_state(state.devices, :disconnected),
      stopped: count_by_state(state.devices, :stopped),
      total_sessions: state.total_sessions,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at, :second),
      memory_before_bytes: state.memory_before,
      memory_after_bytes: memory_after,
      memory_delta_bytes:
        if(state.memory_before, do: memory_after - state.memory_before, else: nil),
      memory_per_device_bytes:
        if state.memory_before && map_size(state.devices) > 0 do
          div(memory_after - state.memory_before, map_size(state.devices))
        else
          nil
        end,
      acs_url: state.acs_url
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:list_devices, _from, state) do
    devices =
      state.devices
      |> Map.values()
      |> Enum.map(&sanitize_device_info/1)

    {:reply, devices, state}
  end

  @impl true
  def handle_call({:get_device, serial_number}, _from, state) do
    case Map.get(state.devices, serial_number) do
      nil -> {:reply, {:error, :not_found}, state}
      device -> {:reply, {:ok, sanitize_device_info(device)}, state}
    end
  end

  @impl true
  def handle_call({:add_device, opts}, _from, state) do
    serial_number =
      Keyword.get(
        opts,
        :serial_number,
        generate_serial(state.oui_prefix, map_size(state.devices) + 1)
      )

    profile = Keyword.get(opts, :profile, :fiber_ont)

    if Map.has_key?(state.devices, serial_number) do
      {:reply, {:error, :already_exists}, state}
    else
      device = spawn_single_device(state, serial_number, profile)
      new_devices = Map.put(state.devices, serial_number, device)
      {:reply, {:ok, serial_number}, %{state | devices: new_devices}}
    end
  end

  @impl true
  def handle_call({:run_session, serial_number, events}, _from, state) do
    case Map.get(state.devices, serial_number) do
      nil ->
        {:reply, {:error, :not_found}, state}

      device ->
        {:reply, :ok, %{state | devices: Map.put(state.devices, serial_number, start_session(state, device, events))}}
    end
  end

  @impl true
  def handle_call({:run_all_sessions, events}, _from, state) do
    new_devices =
      Map.new(state.devices, fn {sn, device} -> {sn, start_session(state, device, events)} end)

    {:reply, {:ok, map_size(new_devices)}, %{state | devices: new_devices}}
  end

  @impl true
  def handle_info(:auto_spawn, state) do
    memory_before = :erlang.memory(:total)
    new_state = do_spawn_devices(%{state | memory_before: memory_before})

    :telemetry.execute(
      [:caretaker, :fleet, :spawned],
      %{count: map_size(new_state.devices)},
      %{acs_url: new_state.acs_url}
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:device_session_complete, serial_number}, state) do
    case Map.get(state.devices, serial_number) do
      nil ->
        {:noreply, state}

      device ->
        new_device = %{
          device
          | sessions: device.sessions + 1,
            state: :connected,
            last_inform: DateTime.utc_now()
        }

        new_devices = Map.put(state.devices, serial_number, new_device)
        {:noreply, %{state | devices: new_devices, total_sessions: state.total_sessions + 1}}
    end
  end

  @impl true
  def handle_info({:device_session_failed, serial_number, reason}, state) do
    Logger.debug("Fleet device #{serial_number} session failed: #{inspect(reason)}")

    case Map.get(state.devices, serial_number) do
      nil ->
        {:noreply, state}

      device ->
        new_devices = Map.put(state.devices, serial_number, %{device | state: :disconnected})
        {:noreply, %{state | devices: new_devices}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # A device's DeviceState or DynamicBehavior went down: mark it stopped so
    # one crashing device never takes the whole fleet with it.
    new_devices =
      Map.new(state.devices, fn {sn, device} ->
        if device.device_state == pid or device.dynamic_behavior == pid do
          if reason not in [:normal, :shutdown] do
            Logger.warning("Fleet device #{sn} process went down: #{inspect(reason)}")
          end

          {sn, %{device | state: :stopped, device_state: nil, dynamic_behavior: nil}}
        else
          {sn, device}
        end
      end)

    {:noreply, %{state | devices: new_devices}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp normalize_profiles(profiles) do
    # Ensure percentages add up and convert to cumulative ranges
    total = Enum.reduce(profiles, 0, fn {pct, _}, acc -> acc + pct end)

    if total != 100 do
      Logger.warning("Fleet profiles don't add up to 100% (got #{total}%), normalizing")
    end

    profiles
    |> Enum.reduce({0, []}, fn {pct, profile}, {cumulative, acc} ->
      new_cumulative = cumulative + pct
      {new_cumulative, [{cumulative, new_cumulative, profile} | acc]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp do_spawn_devices(state) do
    devices =
      1..state.count
      |> Enum.reduce(%{}, fn i, acc ->
        serial_number = generate_serial(state.oui_prefix, i)
        profile = select_profile(state.profiles, i, state.count)

        device = spawn_single_device(state, serial_number, profile)

        # Stagger device spawns
        delay = get_delay(state.connection_delay)
        if delay > 0, do: Process.sleep(delay)

        Map.put(acc, serial_number, device)
      end)

    %{state | devices: devices, spawned: true}
  end

  defp spawn_single_device(state, serial_number, profile) do
    # Load profile parameters
    params = load_profile_params(profile)

    device_id = %{
      oui: state.oui_prefix,
      product_class: state.product_class,
      serial_number: serial_number
    }

    # Start DeviceState, then unlink and monitor it so a device crash is
    # observed (via :DOWN) without propagating to the fleet.
    {:ok, device_state} =
      DeviceState.start_link(
        device_id: device_id,
        params: params
      )

    Process.unlink(device_state)
    Process.monitor(device_state)

    # Start DynamicBehavior if configured
    dynamic_behavior =
      if state.behaviors != [] do
        {:ok, behavior} =
          DynamicBehavior.start_link(
            device_state: device_state,
            behaviors: state.behaviors
          )

        Process.unlink(behavior)
        Process.monitor(behavior)

        # Link behavior to device state
        DeviceState.set_option(device_state, :dynamic_behavior, behavior)

        # Start behaviors
        DynamicBehavior.start(behavior)

        behavior
      else
        nil
      end

    :telemetry.execute(
      [:caretaker, :fleet, :device, :spawned],
      %{},
      %{serial_number: serial_number, profile: profile}
    )

    %{
      serial_number: serial_number,
      profile: profile,
      state: :spawned,
      device_state: device_state,
      dynamic_behavior: dynamic_behavior,
      sessions: 0,
      last_inform: nil,
      spawned_at: DateTime.utc_now()
    }
  end

  # Kick off a background CWMP session for a device. The task is unlinked so a
  # session failure never propagates to the fleet; it reports back by message.
  defp start_session(_state, %{device_state: nil} = device, _events), do: device

  defp start_session(state, device, events) do
    fleet = self()
    sn = device.serial_number
    acs_url = state.acs_url
    device_state = device.device_state

    device_id = %{
      manufacturer: DeviceState.get(device_state, "Device.DeviceInfo.Manufacturer") || "Caretaker",
      oui: state.oui_prefix,
      product_class: state.product_class,
      serial_number: sn
    }

    spawn(fn ->
      result =
        Caretaker.CPE.Client.run_session(acs_url,
          device_id: device_id,
          device_state: device_state,
          events: events
        )

      case result do
        {:ok, _} -> send(fleet, {:device_session_complete, sn})
        {:error, reason} -> send(fleet, {:device_session_failed, sn, reason})
      end
    end)

    %{device | state: :connecting}
  end

  defp stop_device_processes(device) do
    # Stop dynamic behavior
    if device.dynamic_behavior && Process.alive?(device.dynamic_behavior) do
      DynamicBehavior.stop_behaviors(device.dynamic_behavior)
      Agent.stop(device.dynamic_behavior, :normal)
    end

    # Stop device state
    if device.device_state && Process.alive?(device.device_state) do
      Agent.stop(device.device_state, :normal)
    end

    %{device | state: :stopped, device_state: nil, dynamic_behavior: nil}
  end

  defp do_stop_all(state) do
    new_devices =
      Map.new(state.devices, fn {sn, device} ->
        {sn, stop_device_processes(device)}
      end)

    %{state | devices: new_devices}
  end

  defp generate_serial(prefix, index) do
    # Generate serial like "FLEET0-000001"
    padded = String.pad_leading(Integer.to_string(index), 6, "0")
    "#{prefix}-#{padded}"
  end

  defp select_profile(profiles, index, total) do
    # Distribute devices across profiles based on percentage
    position = rem(index * 100, total * 100) / total

    Enum.find_value(profiles, :fiber_ont, fn {min, max, profile} ->
      if position >= min and position < max, do: profile, else: nil
    end)
  end

  defp get_delay(delay) when is_integer(delay), do: delay
  defp get_delay(min..max//_step), do: Enum.random(min..max)
  defp get_delay(_), do: 100

  defp load_profile_params(:fiber_ont), do: load_profile_file("fiber_ont.json", "Fiber ONT")

  defp load_profile_params(:cable_modem),
    do: load_profile_file("cable_modem.json", "Cable Modem")

  defp load_profile_params(:router) do
    default_params("Router")
  end

  defp load_profile_params(%{} = params), do: params

  defp load_profile_params(_), do: default_params("Generic CPE")

  defp load_profile_file(filename, description) do
    path = Application.app_dir(:caretaker, ["priv", "profiles", filename])

    case File.read(path) do
      {:ok, json} -> Jason.decode!(json)
      _ -> default_params(description)
    end
  end

  defp default_params(description) do
    %{
      "Device" => %{
        "DeviceInfo" => %{
          "Manufacturer" => "Caretaker",
          "Description" => description,
          "SoftwareVersion" => "1.0.0",
          "HardwareVersion" => "1.0",
          "UpTime" => 0
        }
      }
    }
  end

  defp count_by_state(devices, target_state) do
    Enum.count(devices, fn {_sn, device} -> device.state == target_state end)
  end

  defp sanitize_device_info(device) do
    %{
      serial_number: device.serial_number,
      profile: device.profile,
      state: device.state,
      sessions: device.sessions,
      last_inform: device.last_inform,
      has_device_state: device.device_state != nil && Process.alive?(device.device_state),
      has_dynamic_behavior:
        device.dynamic_behavior != nil && Process.alive?(device.dynamic_behavior)
    }
  end
end
