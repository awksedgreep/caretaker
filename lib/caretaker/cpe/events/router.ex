defmodule Caretaker.CPE.Events.Router do
  @moduledoc """
  Router-specific event generation and simulation.

  Generates realistic TR-069 events for router devices (including MikroTik RouterOS) including:
  - Standard TR-069 events (BOOT, PERIODIC, VALUE CHANGE)
  - Router-specific events (firmware upgrades, config changes, link state)
  - WAN/LAN events
  - DHCP events
  - Routing events
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

  @router_events [
    "X_FIRMWARE_UPGRADE",
    "X_CONFIG_CHANGE",
    "X_WAN_LINK_UP",
    "X_WAN_LINK_DOWN",
    "X_LAN_LINK_UP",
    "X_LAN_LINK_DOWN",
    "X_DHCP_LEASE_ACQUIRED",
    "X_DHCP_LEASE_RENEWED",
    "X_DHCP_LEASE_EXPIRED",
    "X_ROUTE_ADDED",
    "X_ROUTE_DELETED",
    "X_HIGH_CPU_USAGE",
    "X_HIGH_MEMORY_USAGE",
    "X_CONNECTION_LIMIT"
  ]

  @doc """
  Returns all supported event codes for router devices.
  """
  def supported_events do
    @standard_events ++ @router_events
  end

  @doc """
  Simulate firmware upgrade sequence.

  Typical flow:
  1. Download notification
  2. Verification
  3. Installation (with reboot)
  4. Boot with new version
  """
  def simulate_firmware_upgrade(device_state, new_version) do
    current_version = DeviceState.get(device_state, "Device.DeviceInfo.SoftwareVersion")
    Logger.info("Firmware upgrade: #{current_version} -> #{new_version}")

    events = [
      create_event("X_FIRMWARE_UPGRADE", "download-started", %{
        target_version: new_version
      }),
      create_event("X_FIRMWARE_UPGRADE", "download-complete", %{
        target_version: new_version
      }),
      create_event("X_FIRMWARE_UPGRADE", "verification", %{
        target_version: new_version,
        status: "verified"
      }),
      create_event("X_FIRMWARE_UPGRADE", "installing", %{
        target_version: new_version
      })
    ]

    # Update version after "reboot"
    DeviceState.set(device_state, "Device.DeviceInfo.SoftwareVersion", new_version)

    events =
      events ++
        [
          create_event("1 BOOT", "firmware-upgrade", %{
            previous_version: current_version,
            new_version: new_version
          })
        ]

    :telemetry.execute(
      [:caretaker, :cpe, :event, :firmware_upgrade],
      %{count: 1},
      %{device_state: device_state, from: current_version, to: new_version}
    )

    events
  end

  @doc """
  Simulate configuration change event.

  Triggered when TR-069 SetParameterValues succeeds.
  """
  def simulate_config_change(device_state, changed_params) do
    Logger.info("Configuration changed: #{length(changed_params)} parameters")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :config_change],
      %{param_count: length(changed_params)},
      %{device_state: device_state, params: changed_params}
    )

    [
      create_event("X_CONFIG_CHANGE", "parameter-update", %{
        parameter_count: length(changed_params),
        parameters: Enum.take(changed_params, 10)
      })
    ]
  end

  @doc """
  Simulate WAN link state change.

  Critical event - affects internet connectivity.
  """
  def simulate_wan_link_change(device_state, new_state) when new_state in [:up, :down] do
    wan_interface = "Device.IP.Interface.1"
    current_status = DeviceState.get(device_state, "#{wan_interface}.Status")
    target_status = if new_state == :up, do: "Up", else: "Down"

    if current_status != target_status do
      DeviceState.set(device_state, "#{wan_interface}.Status", target_status)

      event_code = if new_state == :up, do: "X_WAN_LINK_UP", else: "X_WAN_LINK_DOWN"
      event_type = if new_state == :up, do: "link-restored", else: "link-lost"

      Logger.info("WAN link state changed: #{event_type}")

      :telemetry.execute(
        [:caretaker, :cpe, :event, :wan_link],
        %{state: new_state},
        %{device_state: device_state}
      )

      [create_event(event_code, event_type, %{interface: wan_interface, status: target_status})]
    else
      []
    end
  end

  @doc """
  Simulate LAN link state change.

  Less critical than WAN but still important for connectivity.
  """
  def simulate_lan_link_change(device_state, interface_num, new_state)
      when new_state in [:up, :down] do
    lan_interface = "Device.Ethernet.Interface.#{interface_num}"
    current_status = DeviceState.get(device_state, "#{lan_interface}.Status")
    target_status = if new_state == :up, do: "Up", else: "Down"

    if current_status != target_status do
      DeviceState.set(device_state, "#{lan_interface}.Status", target_status)

      event_code = if new_state == :up, do: "X_LAN_LINK_UP", else: "X_LAN_LINK_DOWN"
      event_type = if new_state == :up, do: "connected", else: "disconnected"

      Logger.info("LAN interface #{interface_num} #{event_type}")

      :telemetry.execute(
        [:caretaker, :cpe, :event, :lan_link],
        %{state: new_state, interface: interface_num},
        %{device_state: device_state}
      )

      [
        create_event(event_code, event_type, %{
          interface: lan_interface,
          interface_num: interface_num,
          status: target_status
        })
      ]
    else
      []
    end
  end

  @doc """
  Simulate DHCP client lease acquisition (WAN side).
  """
  def simulate_dhcp_lease_acquired(device_state, ip_address, lease_time) do
    Logger.info("DHCP lease acquired: #{ip_address} (#{lease_time}s)")

    DeviceState.set(device_state, "Device.IP.Interface.1.IPv4Address.1.IPAddress", ip_address)

    :telemetry.execute(
      [:caretaker, :cpe, :event, :dhcp_lease],
      %{action: :acquired, lease_time: lease_time},
      %{device_state: device_state, ip: ip_address}
    )

    [
      create_event("X_DHCP_LEASE_ACQUIRED", "new-lease", %{
        ip_address: ip_address,
        lease_time: lease_time
      })
    ]
  end

  @doc """
  Simulate DHCP lease renewal.
  """
  def simulate_dhcp_lease_renewed(device_state, ip_address) do
    Logger.info("DHCP lease renewed: #{ip_address}")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :dhcp_lease],
      %{action: :renewed},
      %{device_state: device_state, ip: ip_address}
    )

    [create_event("X_DHCP_LEASE_RENEWED", "renewed", %{ip_address: ip_address})]
  end

  @doc """
  Simulate DHCP lease expiration (connection lost).
  """
  def simulate_dhcp_lease_expired(device_state) do
    Logger.warning("DHCP lease expired")

    old_ip = DeviceState.get(device_state, "Device.IP.Interface.1.IPv4Address.1.IPAddress")
    DeviceState.set(device_state, "Device.IP.Interface.1.IPv4Address.1.IPAddress", "0.0.0.0")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :dhcp_lease],
      %{action: :expired},
      %{device_state: device_state}
    )

    [create_event("X_DHCP_LEASE_EXPIRED", "expired", %{previous_ip: old_ip})]
  end

  @doc """
  Simulate route addition (static or dynamic).
  """
  def simulate_route_added(device_state, destination, gateway, metric \\ 0) do
    Logger.info("Route added: #{destination} via #{gateway}")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :route],
      %{action: :added},
      %{device_state: device_state, destination: destination, gateway: gateway}
    )

    [
      create_event("X_ROUTE_ADDED", "route-installed", %{
        destination: destination,
        gateway: gateway,
        metric: metric
      })
    ]
  end

  @doc """
  Simulate route deletion.
  """
  def simulate_route_deleted(device_state, destination) do
    Logger.info("Route deleted: #{destination}")

    :telemetry.execute(
      [:caretaker, :cpe, :event, :route],
      %{action: :deleted},
      %{device_state: device_state, destination: destination}
    )

    [create_event("X_ROUTE_DELETED", "route-removed", %{destination: destination})]
  end

  @doc """
  Check for high CPU usage.

  Warning threshold: 80%
  Critical threshold: 95%
  """
  def check_cpu_usage(device_state) do
    cpu_usage = DeviceState.get(device_state, "Device.DeviceInfo.ProcessStatus.CPUUsage") || 0

    cond do
      cpu_usage >= 95 ->
        Logger.error("Critical CPU usage: #{cpu_usage}%")

        :telemetry.execute(
          [:caretaker, :cpe, :event, :resource_alarm],
          %{resource: :cpu, level: :critical, usage: cpu_usage},
          %{device_state: device_state}
        )

        [create_event("X_HIGH_CPU_USAGE", "critical", %{cpu_usage: cpu_usage})]

      cpu_usage >= 80 ->
        Logger.warning("High CPU usage: #{cpu_usage}%")

        :telemetry.execute(
          [:caretaker, :cpe, :event, :resource_alarm],
          %{resource: :cpu, level: :warning, usage: cpu_usage},
          %{device_state: device_state}
        )

        [create_event("X_HIGH_CPU_USAGE", "warning", %{cpu_usage: cpu_usage})]

      true ->
        []
    end
  end

  @doc """
  Check for high memory usage.

  Warning threshold: 85%
  Critical threshold: 95%
  """
  def check_memory_usage(device_state) do
    total = DeviceState.get(device_state, "Device.DeviceInfo.MemoryStatus.Total") || 1
    free = DeviceState.get(device_state, "Device.DeviceInfo.MemoryStatus.Free") || 0

    used_percent = ((total - free) / total * 100) |> Float.round(1)

    cond do
      used_percent >= 95 ->
        Logger.error("Critical memory usage: #{used_percent}%")

        :telemetry.execute(
          [:caretaker, :cpe, :event, :resource_alarm],
          %{resource: :memory, level: :critical, usage: used_percent},
          %{device_state: device_state}
        )

        [create_event("X_HIGH_MEMORY_USAGE", "critical", %{memory_usage: used_percent})]

      used_percent >= 85 ->
        Logger.warning("High memory usage: #{used_percent}%")

        :telemetry.execute(
          [:caretaker, :cpe, :event, :resource_alarm],
          %{resource: :memory, level: :warning, usage: used_percent},
          %{device_state: device_state}
        )

        [create_event("X_HIGH_MEMORY_USAGE", "warning", %{memory_usage: used_percent})]

      true ->
        []
    end
  end

  @doc """
  Check for connection table exhaustion.

  RouterOS and other routers have limits on tracked connections.
  """
  def check_connection_limit(device_state, max_connections \\ 65536) do
    current_connections =
      DeviceState.get(device_state, "Device.X_VENDOR_ConnectionTracking.Current") || 0

    usage_percent = (current_connections / max_connections * 100) |> Float.round(1)

    cond do
      usage_percent >= 95 ->
        Logger.error("Connection table near limit: #{current_connections}/#{max_connections}")

        :telemetry.execute(
          [:caretaker, :cpe, :event, :connection_limit],
          %{level: :critical, current: current_connections, max: max_connections},
          %{device_state: device_state}
        )

        [
          create_event("X_CONNECTION_LIMIT", "critical", %{
            current: current_connections,
            max: max_connections,
            usage_percent: usage_percent
          })
        ]

      usage_percent >= 85 ->
        Logger.warning("Connection table usage high: #{current_connections}/#{max_connections}")

        :telemetry.execute(
          [:caretaker, :cpe, :event, :connection_limit],
          %{level: :warning, current: current_connections, max: max_connections},
          %{device_state: device_state}
        )

        [
          create_event("X_CONNECTION_LIMIT", "warning", %{
            current: current_connections,
            max: max_connections,
            usage_percent: usage_percent
          })
        ]

      true ->
        []
    end
  end

  @doc """
  Simulate ISP outage (WAN goes down, DHCP expires).
  """
  def simulate_isp_outage(device_state) do
    Logger.error("Simulating ISP outage")

    events = []
    events = events ++ simulate_wan_link_change(device_state, :down)
    events = events ++ simulate_dhcp_lease_expired(device_state)

    :telemetry.execute(
      [:caretaker, :cpe, :event, :isp_outage],
      %{count: 1},
      %{device_state: device_state}
    )

    events
  end

  @doc """
  Restore connectivity after ISP outage.
  """
  def simulate_isp_restore(device_state, new_ip) do
    Logger.info("ISP connectivity restored")

    events = []
    events = events ++ simulate_wan_link_change(device_state, :up)
    events = events ++ simulate_dhcp_lease_acquired(device_state, new_ip, 86400)

    :telemetry.execute(
      [:caretaker, :cpe, :event, :isp_restore],
      %{count: 1},
      %{device_state: device_state}
    )

    events
  end

  @doc """
  Periodic health check for router.

  Should be called periodically to detect resource issues.
  """
  def periodic_health_check(device_state) do
    events = []
    events = events ++ check_cpu_usage(device_state)
    events = events ++ check_memory_usage(device_state)
    events = events ++ check_connection_limit(device_state)

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
