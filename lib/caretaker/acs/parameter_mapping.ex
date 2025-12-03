defmodule Caretaker.ACS.ParameterMapping do
  @moduledoc """
  Map between canonical parameter names and device-specific TR-181 paths.

  Different device types may use different parameter paths for the same
  conceptual value. This module provides bidirectional mapping between
  canonical names (human-friendly, vendor-neutral) and device-specific
  TR-181 parameter paths.

  ## Examples

      iex> ParameterMapping.to_device_path("WAN.IPAddress", {:mikrotik, :routeros})
      "Device.IP.Interface.1.IPv4Address.1.IPAddress"

      iex> ParameterMapping.to_device_path("PON.RxPower", {:gpon_ont, :huawei})
      "Device.Optical.Interface.1.OpticalSignalLevel"

      iex> ParameterMapping.from_device_path("Device.Optical.Interface.1.OpticalSignalLevel", {:gpon_ont, :huawei})
      "PON.RxPower"
  """

  alias Caretaker.ACS.DeviceDetection

  @type device_type :: DeviceDetection.device_type()
  @type canonical_name :: String.t()
  @type device_path :: String.t()

  # Canonical parameter mappings per device type
  # Format: %{device_type => %{canonical_name => device_path}}
  @mappings %{
    # Mikrotik RouterOS - limited TR-181 support
    {:mikrotik, :routeros} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "Device.SerialNumber" => "Device.DeviceInfo.SerialNumber",
      "Device.SoftwareVersion" => "Device.DeviceInfo.SoftwareVersion",
      "Device.HardwareVersion" => "Device.DeviceInfo.HardwareVersion",
      "Device.UpTime" => "Device.DeviceInfo.UpTime",
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress",
      "WAN.SubnetMask" => "Device.IP.Interface.1.IPv4Address.1.SubnetMask",
      "WAN.Gateway" => "Device.Routing.Router.1.IPv4Forwarding.1.GatewayIPAddress",
      "WiFi.SSID" => "Device.WiFi.SSID.1.SSID",
      "WiFi.Password" => "Device.WiFi.AccessPoint.1.Security.PreSharedKey",
      "WiFi.Channel" => "Device.WiFi.Radio.1.Channel",
      "WiFi.Enabled" => "Device.WiFi.Radio.1.Enable",
      "Management.URL" => "Device.ManagementServer.URL",
      "Management.Username" => "Device.ManagementServer.Username",
      "Management.Password" => "Device.ManagementServer.Password",
      "Management.PeriodicInformInterval" => "Device.ManagementServer.PeriodicInformInterval"
    },
    # GPON/XGSPON ONT - vendor-agnostic mappings
    {:gpon_ont, :huawei} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "Device.SerialNumber" => "Device.DeviceInfo.SerialNumber",
      "Device.SoftwareVersion" => "Device.DeviceInfo.SoftwareVersion",
      "PON.RxPower" => "Device.Optical.Interface.1.OpticalSignalLevel",
      "PON.TxPower" => "Device.Optical.Interface.1.TransmitOpticalLevel",
      "PON.Temperature" => "Device.Optical.Interface.1.Temperature",
      "PON.Voltage" => "Device.Optical.Interface.1.Voltage",
      "PON.Status" => "Device.Optical.Interface.1.Status",
      "PON.LowerThreshold" => "Device.Optical.Interface.1.LowerOpticalThreshold",
      "PON.UpperThreshold" => "Device.Optical.Interface.1.UpperOpticalThreshold",
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress",
      "WAN.SubnetMask" => "Device.IP.Interface.1.IPv4Address.1.SubnetMask",
      "WAN.Gateway" => "Device.IP.Interface.1.IPv4Address.1.DefaultGateway",
      "WiFi.SSID" => "Device.WiFi.SSID.1.SSID",
      "WiFi.Password" => "Device.WiFi.AccessPoint.1.Security.KeyPassphrase",
      "WiFi.Channel" => "Device.WiFi.Radio.1.Channel",
      "WiFi.Enabled" => "Device.WiFi.Radio.1.Enable"
    },
    {:gpon_ont, :zte} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "Device.SerialNumber" => "Device.DeviceInfo.SerialNumber",
      "Device.SoftwareVersion" => "Device.DeviceInfo.SoftwareVersion",
      "PON.RxPower" => "Device.Optical.Interface.1.OpticalSignalLevel",
      "PON.TxPower" => "Device.Optical.Interface.1.TransmitOpticalLevel",
      "PON.Temperature" => "Device.Optical.Interface.1.Temperature",
      "PON.Status" => "Device.Optical.Interface.1.Status",
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress",
      "WAN.SubnetMask" => "Device.IP.Interface.1.IPv4Address.1.SubnetMask",
      "WiFi.SSID" => "Device.WiFi.SSID.1.SSID",
      "WiFi.Channel" => "Device.WiFi.Radio.1.Channel"
    },
    {:gpon_ont, :nokia} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "PON.RxPower" => "Device.Optical.Interface.1.OpticalSignalLevel",
      "PON.TxPower" => "Device.Optical.Interface.1.TransmitOpticalLevel",
      "PON.Status" => "Device.Optical.Interface.1.Status",
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress"
    },
    # XGS-PON inherits GPON mappings
    {:xgspon_ont, :huawei} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "PON.RxPower" => "Device.Optical.Interface.1.OpticalSignalLevel",
      "PON.TxPower" => "Device.Optical.Interface.1.TransmitOpticalLevel",
      "PON.Temperature" => "Device.Optical.Interface.1.Temperature",
      "PON.Status" => "Device.Optical.Interface.1.Status"
    },
    # Cable Modem (DOCSIS)
    {:cable_modem, :arris} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "Device.SerialNumber" => "Device.DeviceInfo.SerialNumber",
      "Device.SoftwareVersion" => "Device.DeviceInfo.SoftwareVersion",
      "DOCSIS.Status" => "Device.Docsis.Status",
      "DOCSIS.BootState" => "Device.Docsis.BootState",
      "DOCSIS.DownstreamChannels" => "Device.Docsis.DownstreamNumberOfEntries",
      "DOCSIS.UpstreamChannels" => "Device.Docsis.UpstreamNumberOfEntries",
      "DOCSIS.DS1.Frequency" => "Device.Docsis.Downstream.1.Frequency",
      "DOCSIS.DS1.Power" => "Device.Docsis.Downstream.1.Power",
      "DOCSIS.DS1.SNR" => "Device.Docsis.Downstream.1.SNR",
      "DOCSIS.US1.Frequency" => "Device.Docsis.Upstream.1.Frequency",
      "DOCSIS.US1.Power" => "Device.Docsis.Upstream.1.Power",
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress",
      "WAN.SubnetMask" => "Device.IP.Interface.1.IPv4Address.1.SubnetMask"
    },
    {:cable_modem, :technicolor} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "DOCSIS.Status" => "Device.Docsis.Status",
      "DOCSIS.DownstreamChannels" => "Device.Docsis.DownstreamNumberOfEntries",
      "DOCSIS.UpstreamChannels" => "Device.Docsis.UpstreamNumberOfEntries",
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress"
    },
    # Generic router (fallback)
    {:router, :generic} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "Device.SerialNumber" => "Device.DeviceInfo.SerialNumber",
      "Device.SoftwareVersion" => "Device.DeviceInfo.SoftwareVersion",
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress",
      "WAN.SubnetMask" => "Device.IP.Interface.1.IPv4Address.1.SubnetMask",
      "WiFi.SSID" => "Device.WiFi.SSID.1.SSID",
      "WiFi.Channel" => "Device.WiFi.Radio.1.Channel"
    },
    # Generic/unknown device (standard TR-181 paths)
    {:generic, :unknown} => %{
      "Device.Manufacturer" => "Device.DeviceInfo.Manufacturer",
      "Device.Model" => "Device.DeviceInfo.ModelName",
      "Device.SerialNumber" => "Device.DeviceInfo.SerialNumber",
      "Device.SoftwareVersion" => "Device.DeviceInfo.SoftwareVersion"
    }
  }

  @doc """
  Convert canonical parameter name to device-specific TR-181 path.

  Returns the device-specific path if mapping exists, otherwise returns
  the canonical name unchanged (passthrough).
  """
  @spec to_device_path(canonical_name(), device_type()) :: device_path()
  def to_device_path(canonical_name, device_type) do
    case get_in(@mappings, [device_type, canonical_name]) do
      nil -> canonical_name
      device_path -> device_path
    end
  end

  @doc """
  Convert device-specific TR-181 path to canonical parameter name.

  Returns the canonical name if mapping exists, otherwise returns
  the device path unchanged (passthrough).
  """
  @spec from_device_path(device_path(), device_type()) :: canonical_name()
  def from_device_path(device_path, device_type) do
    case get_in(@mappings, [device_type]) do
      nil ->
        device_path

      mapping ->
        case Enum.find(mapping, fn {_canonical, path} -> path == device_path end) do
          {canonical, _path} -> canonical
          nil -> device_path
        end
    end
  end

  @doc """
  Get all supported canonical parameter names for a device type.
  """
  @spec supported_parameters(device_type()) :: [canonical_name()]
  def supported_parameters(device_type) do
    case get_in(@mappings, [device_type]) do
      nil -> []
      mapping -> Map.keys(mapping)
    end
  end

  @doc """
  Check if a canonical parameter is supported for a device type.
  """
  @spec supported?(canonical_name(), device_type()) :: boolean()
  def supported?(canonical_name, device_type) do
    case get_in(@mappings, [device_type, canonical_name]) do
      nil -> false
      _path -> true
    end
  end

  @doc """
  Batch convert multiple canonical names to device paths.
  """
  @spec to_device_paths([canonical_name()], device_type()) :: [{canonical_name(), device_path()}]
  def to_device_paths(canonical_names, device_type) when is_list(canonical_names) do
    Enum.map(canonical_names, fn name ->
      {name, to_device_path(name, device_type)}
    end)
  end

  @doc """
  Batch convert multiple device paths to canonical names.
  """
  @spec from_device_paths([device_path()], device_type()) :: [{device_path(), canonical_name()}]
  def from_device_paths(device_paths, device_type) when is_list(device_paths) do
    Enum.map(device_paths, fn path ->
      {path, from_device_path(path, device_type)}
    end)
  end
end
