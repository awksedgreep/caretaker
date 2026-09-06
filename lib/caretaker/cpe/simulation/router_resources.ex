defmodule Caretaker.CPE.Simulation.RouterResources do
  @moduledoc """
  Simulates router resource usage including CPU, memory, and network connections.

  This module provides realistic simulation of:
  - CPU usage based on load profile
  - Memory consumption
  - Connection tracking (NAT sessions, firewall states)
  - Interface traffic statistics
  - Load-based performance degradation

  ## Usage

      # Update resources with normal load
      device_state = RouterResources.update(device_state)

      # Simulate high load scenario
      device_state = RouterResources.update(device_state, load_profile: :high)

      # Simulate resource exhaustion
      device_state = RouterResources.update(device_state, load_profile: :exhausted)
  """

  require Logger
  alias Caretaker.CPE.DeviceState
  alias Caretaker.CPE.Events.Router

  @type load_profile :: :idle | :low | :normal | :high | :exhausted

  @doc """
  Update router resource statistics.

  ## Options

  - `:load_profile` - System load profile (`:idle`, `:low`, `:normal`, `:high`, `:exhausted`)
  - `:update_interfaces` - Whether to update interface stats (default: true)
  """
  @spec update(pid(), keyword()) :: :ok
  def update(device_state, opts \\ []) do
    load_profile = Keyword.get(opts, :load_profile, :normal)
    update_interfaces = Keyword.get(opts, :update_interfaces, true)

    # Update CPU usage
    cpu_usage = simulate_cpu(load_profile)
    DeviceState.set(device_state, "Device.DeviceInfo.ProcessStatus.CPUUsage", cpu_usage)

    # Update memory
    {total_memory, free_memory} = simulate_memory(load_profile)
    DeviceState.set(device_state, "Device.DeviceInfo.MemoryStatus.Total", total_memory)
    DeviceState.set(device_state, "Device.DeviceInfo.MemoryStatus.Free", free_memory)

    # Update connection count (if supported - Mikrotik specific)
    connection_count = simulate_connections(load_profile)

    if DeviceState.get(device_state, "Device.Firewall.X_MIKROTIK_ConnectionCount") do
      DeviceState.set(
        device_state,
        "Device.Firewall.X_MIKROTIK_ConnectionCount",
        connection_count
      )
    end

    # Update interface statistics
    if update_interfaces do
      update_interface_stats(device_state, load_profile)
    end

    # Update uptime
    current_uptime = DeviceState.get(device_state, "Device.DeviceInfo.UpTime") || 0
    DeviceState.set(device_state, "Device.DeviceInfo.UpTime", current_uptime + 1)

    # Check for router-specific events
    _events = Router.periodic_health_check(device_state)

    :telemetry.execute(
      [:caretaker, :cpe, :simulation, :router_resources],
      %{cpu: cpu_usage, memory_free: free_memory, connections: connection_count},
      %{load_profile: load_profile}
    )

    :ok
  end

  # Simulate CPU usage percentage
  defp simulate_cpu(load_profile) do
    base_cpu =
      case load_profile do
        :idle -> 2
        :low -> 10
        :normal -> 25
        :high -> 60
        :exhausted -> 95
      end

    variation = :rand.normal() * 5
    new_value = base_cpu + variation

    round(max(0, min(100, new_value)))
  end

  # Simulate memory usage
  defp simulate_memory(load_profile) do
    # Total memory in KB (e.g., 1GB = 1048576 KB)
    total = 1_048_576

    base_free_pct =
      case load_profile do
        :idle -> 0.9
        :low -> 0.75
        :normal -> 0.5
        :high -> 0.25
        :exhausted -> 0.05
      end

    # Noise proportional to the profile's baseline: matches the previous ~0.05
    # spread at :normal while keeping :exhausted reliably near its floor.
    variation = :rand.normal() * base_free_pct * 0.1
    free_pct = max(0.01, min(0.95, base_free_pct + variation))
    free = round(total * free_pct)

    {total, free}
  end

  # Simulate connection count
  defp simulate_connections(load_profile) do
    base_connections =
      case load_profile do
        :idle -> 50
        :low -> 500
        :normal -> 1500
        :high -> 5000
        :exhausted -> 15000
      end

    variation = :rand.uniform(round(base_connections * 0.2))
    base_connections + variation
  end

  # Update interface traffic statistics
  defp update_interface_stats(device_state, load_profile) do
    # Get interface count
    eth_count = DeviceState.get(device_state, "Device.Ethernet.InterfaceNumberOfEntries") || 1

    # Update each interface
    Enum.each(1..eth_count, fn idx ->
      eth_path = "Device.Ethernet.Interface.#{idx}"
      status = DeviceState.get(device_state, "#{eth_path}.Status")

      # Only update active interfaces
      if status == "Up" do
        is_wan = DeviceState.get(device_state, "#{eth_path}.Upstream") == true
        update_single_interface(device_state, eth_path, load_profile, is_wan)
      end
    end)

    # Update IP interface stats (if they exist)
    ip_count = DeviceState.get(device_state, "Device.IP.InterfaceNumberOfEntries") || 0

    Enum.each(1..ip_count, fn idx ->
      ip_path = "Device.IP.Interface.#{idx}"
      status = DeviceState.get(device_state, "#{ip_path}.Status")

      if status == "Up" do
        update_single_interface(device_state, ip_path, load_profile, false)
      end
    end)
  end

  # Update statistics for a single interface
  defp update_single_interface(device_state, base_path, load_profile, is_wan) do
    stats_path = "#{base_path}.Stats"

    # Current counters
    bytes_sent = DeviceState.get(device_state, "#{stats_path}.BytesSent") || 0
    bytes_recv = DeviceState.get(device_state, "#{stats_path}.BytesReceived") || 0
    packets_sent = DeviceState.get(device_state, "#{stats_path}.PacketsSent") || 0
    packets_recv = DeviceState.get(device_state, "#{stats_path}.PacketsReceived") || 0

    # Calculate increments based on load
    traffic_multiplier =
      case load_profile do
        :idle -> 0.1
        :low -> 0.5
        :normal -> 1.0
        :high -> 2.5
        :exhausted -> 5.0
      end

    # WAN interfaces typically have more traffic
    wan_multiplier = if is_wan, do: 3.0, else: 1.0

    # Traffic increments (bytes per second * multipliers)
    base_sent = 100_000 * traffic_multiplier * wan_multiplier
    base_recv = 200_000 * traffic_multiplier * wan_multiplier

    bytes_sent_inc = round(base_sent + :rand.uniform(round(base_sent * 0.5)))
    bytes_recv_inc = round(base_recv + :rand.uniform(round(base_recv * 0.5)))

    packets_sent_inc = round(bytes_sent_inc / 1000)
    packets_recv_inc = round(bytes_recv_inc / 1000)

    # Update counters
    DeviceState.set(device_state, "#{stats_path}.BytesSent", bytes_sent + bytes_sent_inc)
    DeviceState.set(device_state, "#{stats_path}.BytesReceived", bytes_recv + bytes_recv_inc)
    DeviceState.set(device_state, "#{stats_path}.PacketsSent", packets_sent + packets_sent_inc)

    DeviceState.set(
      device_state,
      "#{stats_path}.PacketsReceived",
      packets_recv + packets_recv_inc
    )

    # Simulate occasional errors under high load
    if load_profile in [:high, :exhausted] and :rand.uniform(100) < 5 do
      errors_recv = DeviceState.get(device_state, "#{stats_path}.ErrorsReceived") || 0
      DeviceState.set(device_state, "#{stats_path}.ErrorsReceived", errors_recv + 1)
    end

    # Simulate packet drops under exhaustion
    if load_profile == :exhausted and :rand.uniform(100) < 10 do
      discards = DeviceState.get(device_state, "#{stats_path}.DiscardPacketsSent") || 0
      DeviceState.set(device_state, "#{stats_path}.DiscardPacketsSent", discards + 1)
    end
  end

  @doc """
  Simulate a gradual load increase over time.

  Useful for testing how systems respond to growing traffic.
  """
  @spec simulate_load_ramp(pid(), keyword()) :: :ok
  def simulate_load_ramp(device_state, opts \\ []) do
    duration_ms = Keyword.get(opts, :duration, 60_000)
    steps = Keyword.get(opts, :steps, 10)
    step_delay = div(duration_ms, steps)

    profiles = [:idle, :low, :normal, :high, :exhausted]

    Enum.each(0..(steps - 1), fn step ->
      # Calculate which profile to use
      profile_index = min(div(step * length(profiles), steps), length(profiles) - 1)
      profile = Enum.at(profiles, profile_index)

      Logger.info("Load ramp step #{step + 1}/#{steps}: #{profile}")
      update(device_state, load_profile: profile)

      if step < steps - 1, do: Process.sleep(step_delay)
    end)

    :ok
  end

  @doc """
  Get current router resource status.
  """
  @spec status(pid()) :: map()
  def status(device_state) do
    cpu = DeviceState.get(device_state, "Device.DeviceInfo.ProcessStatus.CPUUsage")
    mem_total = DeviceState.get(device_state, "Device.DeviceInfo.MemoryStatus.Total")
    mem_free = DeviceState.get(device_state, "Device.DeviceInfo.MemoryStatus.Free")

    mem_used_pct =
      if mem_total && mem_free do
        Float.round((1 - mem_free / mem_total) * 100, 1)
      else
        nil
      end

    %{
      cpu_usage: cpu,
      memory_total: mem_total,
      memory_free: mem_free,
      memory_used_pct: mem_used_pct,
      uptime: DeviceState.get(device_state, "Device.DeviceInfo.UpTime")
    }
  end

  @doc """
  Determine load profile from current resource usage.
  """
  @spec detect_load_profile(pid()) :: load_profile()
  def detect_load_profile(device_state) do
    cpu = DeviceState.get(device_state, "Device.DeviceInfo.ProcessStatus.CPUUsage") || 0

    cond do
      cpu < 5 -> :idle
      cpu < 20 -> :low
      cpu < 50 -> :normal
      cpu < 80 -> :high
      true -> :exhausted
    end
  end
end
