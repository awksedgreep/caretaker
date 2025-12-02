defmodule Caretaker.Quirks.Mikrotik do
  @moduledoc """
  Quirks and limitations for MikroTik RouterOS TR-069 implementation.

  MikroTik's RouterOS TR-069 package has significant limitations compared to
  a full TR-181 implementation. This module documents and handles these quirks.

  ## Known Limitations

  ### 1. Limited Parameter Set
  RouterOS TR-069 package supports only a subset of TR-181 parameters.
  Most configuration is done through RouterOS-specific mechanisms (CLI, API).

  ### 2. Read-Only Parameters
  Many parameters that should be writable per TR-181 are read-only in RouterOS.

  ### 3. Vendor Extensions
  MikroTik uses X_MIKROTIK_* extensions for RouterOS-specific features.

  ### 4. Script Execution
  Advanced configuration requires executing RouterOS scripts via vendor extensions
  rather than using standard TR-181 parameter operations.

  ### 5. Reboot Requirements
  Some parameter changes require a device reboot to take effect.

  ### 6. Limited WiFi Support
  WiFi configuration through TR-069 is minimal; prefer RouterOS wireless configuration.

  ## Supported Parameters

  The TR-069 package primarily supports:
  - Basic device information (manufacturer, model, versions)
  - Management server configuration (ACS URL, credentials, periodic inform)
  - Connection request handling
  - Basic system status (uptime, CPU, memory)
  - Limited interface information

  ## Unsupported/Limited Areas

  - Advanced WiFi configuration
  - Firewall rules (use X_MIKROTIK_Script instead)
  - Routing beyond basic static routes
  - QoS configuration
  - VPN configuration
  - User management

  ## Reference

  MikroTik TR-069 Client documentation:
  https://help.mikrotik.com/docs/display/ROS/TR-069+Client
  """

  @behaviour Caretaker.Quirks.Behaviour

  require Logger

  # Core supported parameters in RouterOS TR-069 package
  @supported_params [
    # Device.DeviceInfo.* - Basic device identification
    "Device.DeviceInfo.Manufacturer",
    "Device.DeviceInfo.ManufacturerOUI",
    "Device.DeviceInfo.ModelName",
    "Device.DeviceInfo.Description",
    "Device.DeviceInfo.ProductClass",
    "Device.DeviceInfo.SerialNumber",
    "Device.DeviceInfo.HardwareVersion",
    "Device.DeviceInfo.SoftwareVersion",
    "Device.DeviceInfo.ProvisioningCode",
    "Device.DeviceInfo.UpTime",
    "Device.DeviceInfo.FirstUseDate",
    "Device.DeviceInfo.ProcessStatus.CPUUsage",
    "Device.DeviceInfo.MemoryStatus.Total",
    "Device.DeviceInfo.MemoryStatus.Free",
    # Mikrotik-specific device info
    "Device.DeviceInfo.X_MIKROTIK_BoardName",
    "Device.DeviceInfo.X_MIKROTIK_Architecture",
    "Device.DeviceInfo.X_MIKROTIK_CPUCount",
    "Device.DeviceInfo.X_MIKROTIK_CPUFrequency",
    "Device.DeviceInfo.X_MIKROTIK_License",
    "Device.DeviceInfo.X_MIKROTIK_FactoryFirmware",
    "Device.DeviceInfo.X_MIKROTIK_CurrentFirmware",
    # Device.ManagementServer.* - ACS configuration (full support)
    "Device.ManagementServer.URL",
    "Device.ManagementServer.Username",
    "Device.ManagementServer.Password",
    "Device.ManagementServer.PeriodicInformEnable",
    "Device.ManagementServer.PeriodicInformInterval",
    "Device.ManagementServer.PeriodicInformTime",
    "Device.ManagementServer.ConnectionRequestURL",
    "Device.ManagementServer.ConnectionRequestUsername",
    "Device.ManagementServer.ConnectionRequestPassword",
    "Device.ManagementServer.ParameterKey",
    # Device.Time.* - Time configuration
    "Device.Time.Enable",
    "Device.Time.Status",
    "Device.Time.NTPServer1",
    "Device.Time.NTPServer2",
    "Device.Time.CurrentLocalTime",
    # Device.Ethernet.InterfaceNumberOfEntries - Interface count (read-only)
    "Device.Ethernet.InterfaceNumberOfEntries",
    # Device.Ethernet.Interface.{i}.* - Basic interface info (mostly read-only)
    "Device.Ethernet.Interface.{i}.Enable",
    "Device.Ethernet.Interface.{i}.Status",
    "Device.Ethernet.Interface.{i}.Alias",
    "Device.Ethernet.Interface.{i}.Name",
    "Device.Ethernet.Interface.{i}.MACAddress",
    "Device.Ethernet.Interface.{i}.MaxBitRate",
    "Device.Ethernet.Interface.{i}.DuplexMode",
    "Device.Ethernet.Interface.{i}.Stats.BytesSent",
    "Device.Ethernet.Interface.{i}.Stats.BytesReceived",
    "Device.Ethernet.Interface.{i}.Stats.PacketsSent",
    "Device.Ethernet.Interface.{i}.Stats.PacketsReceived",
    # Device.IP.InterfaceNumberOfEntries
    "Device.IP.InterfaceNumberOfEntries",
    # Device.IP.Interface.{i}.* - IP configuration (limited)
    "Device.IP.Interface.{i}.Enable",
    "Device.IP.Interface.{i}.Status",
    "Device.IP.Interface.{i}.Name",
    "Device.IP.Interface.{i}.IPv4Enable",
    "Device.IP.Interface.{i}.IPv4AddressNumberOfEntries",
    "Device.IP.Interface.{i}.IPv4Address.{i}.Enable",
    "Device.IP.Interface.{i}.IPv4Address.{i}.Status",
    "Device.IP.Interface.{i}.IPv4Address.{i}.IPAddress",
    "Device.IP.Interface.{i}.IPv4Address.{i}.SubnetMask",
    # Device.Routing.* - Very limited routing support
    "Device.Routing.Router.{i}.Enable",
    "Device.Routing.Router.{i}.IPv4Forwarding.{i}.Enable",
    "Device.Routing.Router.{i}.IPv4Forwarding.{i}.DestIPAddress",
    "Device.Routing.Router.{i}.IPv4Forwarding.{i}.DestSubnetMask",
    "Device.Routing.Router.{i}.IPv4Forwarding.{i}.GatewayIPAddress",
    # Mikrotik-specific extensions
    "Device.X_MIKROTIK_System.Identity",
    "Device.X_MIKROTIK_System.Note",
    "Device.X_MIKROTIK_System.Clock.TimeZone",
    "Device.X_MIKROTIK_System.Clock.NTPEnabled",
    "Device.X_MIKROTIK_System.Clock.NTPServers"
  ]

  # Parameters with specific notes/limitations
  @parameter_notes %{
    "Device.ManagementServer.PeriodicInformInterval" => [
      "Minimum supported value is 60 seconds",
      "Values below 60 will be rejected or rounded up"
    ],
    "Device.ManagementServer.URL" => [
      "Changes take effect immediately",
      "Must be a valid HTTP/HTTPS URL"
    ],
    "Device.DeviceInfo.ProvisioningCode" => [
      "Can be set but rarely used in RouterOS deployments",
      "Consider using X_MIKROTIK_System.Note for device annotations"
    ],
    "Device.Ethernet.Interface.{i}.Enable" => [
      "May require admin privileges",
      "Some interfaces cannot be disabled (e.g., management)"
    ],
    "Device.WiFi.*" => [
      "WiFi configuration through TR-069 is very limited",
      "Use RouterOS wireless configuration or X_MIKROTIK_Script for advanced setup"
    ],
    "Device.Firewall.*" => [
      "Firewall rules cannot be managed through TR-069",
      "Use X_MIKROTIK_Script to execute firewall commands"
    ],
    "Device.NAT.*" => [
      "NAT configuration is read-only or unsupported",
      "Use X_MIKROTIK_Script for NAT setup"
    ],
    "Device.DHCPv4.*" => [
      "DHCP server configuration is limited",
      "Use X_MIKROTIK_Script for full DHCP control"
    ]
  }

  @impl true
  def vendor_name, do: "MikroTik"

  @impl true
  def supported_parameters, do: @supported_params

  @impl true
  def supported_parameter?(parameter_path) do
    # Check exact match
    if parameter_path in @supported_params do
      true
    else
      # Check pattern match (e.g., Device.Ethernet.Interface.1.Enable matches Device.Ethernet.Interface.{i}.Enable)
      Enum.any?(@supported_params, fn pattern ->
        pattern_matches?(pattern, parameter_path)
      end)
    end
  end

  @impl true
  def parameter_notes(parameter_path) do
    # Check for exact match
    notes = Map.get(@parameter_notes, parameter_path, [])

    # Check for pattern match
    pattern_notes =
      @parameter_notes
      |> Enum.filter(fn {pattern, _notes} -> pattern_matches?(pattern, parameter_path) end)
      |> Enum.flat_map(fn {_pattern, notes} -> notes end)

    notes ++ pattern_notes
  end

  @impl true
  def transform_request(envelope) do
    # MikroTik generally handles standard CWMP envelopes well
    # No special transformations needed for requests
    envelope
  end

  @impl true
  def transform_response(envelope) do
    # MikroTik responses are generally standards-compliant
    # No special transformations needed
    envelope
  end

  @doc """
  Generate a RouterOS script to be executed via vendor extension.

  This is the recommended way to perform advanced configuration on MikroTik
  devices that cannot be done through standard TR-069 parameters.

  ## Examples

      # Configure firewall rule
      script = Mikrotik.generate_script(:firewall_rule, %{
        chain: "input",
        protocol: "tcp",
        dst_port: 22,
        action: "accept"
      })

      # Configure DHCP server
      script = Mikrotik.generate_script(:dhcp_server, %{
        interface: "bridge",
        address_pool: "192.168.88.10-192.168.88.254",
        gateway: "192.168.88.1"
      })
  """
  @spec generate_script(atom(), map()) :: String.t()
  def generate_script(:firewall_rule, params) do
    """
    /ip firewall filter add \\
      chain=#{params[:chain]} \\
      protocol=#{params[:protocol]} \\
      dst-port=#{params[:dst_port]} \\
      action=#{params[:action]} \\
      comment="Added via TR-069"
    """
  end

  def generate_script(:dhcp_server, params) do
    """
    /ip dhcp-server network add \\
      address=#{params[:network]} \\
      gateway=#{params[:gateway]} \\
      dns-server=#{params[:dns_servers] || "1.1.1.1,8.8.8.8"} \\
      comment="Added via TR-069"
    """
  end

  def generate_script(:nat_masquerade, params) do
    """
    /ip firewall nat add \\
      chain=srcnat \\
      out-interface=#{params[:out_interface]} \\
      action=masquerade \\
      comment="Added via TR-069"
    """
  end

  def generate_script(:static_route, params) do
    """
    /ip route add \\
      dst-address=#{params[:dst_address]} \\
      gateway=#{params[:gateway]} \\
      distance=#{params[:distance] || 1} \\
      comment="Added via TR-069"
    """
  end

  def generate_script(:wifi_security, params) do
    """
    /interface wireless security-profiles add \\
      name=#{params[:profile_name]} \\
      mode=dynamic-keys \\
      authentication-types=wpa2-psk \\
      wpa2-pre-shared-key=#{params[:passphrase]} \\
      comment="Added via TR-069"

    /interface wireless set #{params[:interface]} \\
      security-profile=#{params[:profile_name]}
    """
  end

  def generate_script(:system_identity, params) do
    """
    /system identity set name=#{params[:name]}
    """
  end

  def generate_script(type, _params) do
    Logger.warning("Unknown script type for MikroTik: #{type}")
    ""
  end

  @doc """
  Get recommended alternatives for unsupported parameters.

  ## Examples

      iex> Mikrotik.alternative_approach("Device.WiFi.Radio.1.Channel")
      {:script, "Use /interface wireless set command", "See generate_script/2"}
  """
  @spec alternative_approach(String.t()) ::
          {:script, String.t(), String.t()} | {:read_only, String.t()} | :unsupported
  def alternative_approach(parameter_path) do
    cond do
      String.contains?(parameter_path, "WiFi") ->
        {:script, "Use RouterOS wireless interface configuration",
         "Execute: /interface wireless set [name] [parameters]"}

      String.contains?(parameter_path, "Firewall") ->
        {:script, "Use RouterOS firewall configuration",
         "Execute: /ip firewall filter add [parameters]"}

      String.contains?(parameter_path, "NAT") ->
        {:script, "Use RouterOS NAT configuration", "Execute: /ip firewall nat add [parameters]"}

      String.contains?(parameter_path, "QoS") ->
        {:script, "Use RouterOS queue configuration",
         "Execute: /queue simple add or /queue tree add"}

      String.contains?(parameter_path, "DHCPv4") ->
        {:script, "Use RouterOS DHCP server configuration",
         "Execute: /ip dhcp-server and /ip dhcp-server network commands"}

      String.contains?(parameter_path, "Routing") ->
        {:script, "Use RouterOS routing configuration", "Execute: /ip route or /routing commands"}

      String.contains?(parameter_path, "Stats") ->
        {:read_only, "Statistics parameters are read-only in RouterOS"}

      true ->
        :unsupported
    end
  end

  @doc """
  Check if a parameter change requires a reboot.

  ## Examples

      iex> Mikrotik.requires_reboot?("Device.ManagementServer.URL")
      false

      iex> Mikrotik.requires_reboot?("Device.DeviceInfo.ProvisioningCode")
      false
  """
  @spec requires_reboot?(String.t()) :: boolean()
  def requires_reboot?(parameter_path) do
    # Most RouterOS changes take effect immediately
    # Very few TR-069 parameters require reboot
    cond do
      String.starts_with?(parameter_path, "Device.ManagementServer") -> false
      String.starts_with?(parameter_path, "Device.Time") -> false
      true -> false
    end
  end

  @doc """
  Get minimum supported firmware version for TR-069.

  RouterOS TR-069 client was introduced in RouterOS v6.x and
  improved significantly in v7.x.
  """
  @spec minimum_version() :: String.t()
  def minimum_version, do: "6.45"

  @doc """
  Get recommended firmware version for TR-069.
  """
  @spec recommended_version() :: String.t()
  def recommended_version, do: "7.12"

  @doc """
  Check if firmware version is adequate for TR-069 support.

  ## Examples

      iex> Mikrotik.adequate_version?("7.12.1")
      true

      iex> Mikrotik.adequate_version?("6.44")
      false
  """
  @spec adequate_version?(String.t()) :: boolean()
  def adequate_version?(version) when is_binary(version) do
    # RouterOS uses version format like "6.45" or "7.12.1"
    # Elixir's Version.parse requires semantic versioning (major.minor.patch)
    # So we normalize by adding .0 if needed
    normalized =
      case String.split(version, ".") do
        [major, minor] -> "#{major}.#{minor}.0"
        _ -> version
      end

    case Version.parse(normalized) do
      {:ok, v} ->
        {:ok, min} = Version.parse(minimum_version() <> ".0")
        Version.compare(v, min) in [:gt, :eq]

      _ ->
        false
    end
  end

  def adequate_version?(_), do: false

  # Helper function to match parameter patterns
  defp pattern_matches?(pattern, path) do
    # Convert pattern like "Device.Ethernet.Interface.{i}.Enable"
    # to regex that matches "Device.Ethernet.Interface.1.Enable"
    regex_pattern =
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("{i}", "\\d+")
      |> then(&("^" <> &1 <> "$"))

    Regex.match?(~r/#{regex_pattern}/, path)
  end
end
