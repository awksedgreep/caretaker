defmodule Caretaker.ACS.RPC.Helpers do
  @moduledoc """
  Device-aware RPC generation helpers.

  Provides convenient functions to generate TR-069 RPC commands with automatic
  parameter mapping and device-specific handling based on device type.
  """

  alias Caretaker.ACS.{DeviceDetection, ParameterMapping}
  alias Caretaker.TR069.RPC.{GetParameterValues, SetParameterValues}

  @type device_type :: DeviceDetection.device_type()

  @doc """
  Generate GetParameterValues RPC with canonical parameter names.

  Automatically maps canonical names to device-specific TR-181 paths.

  ## Examples

      iex> get_parameters(["Device.Model", "PON.RxPower"], {:gpon_ont, :huawei})
      %GetParameterValues{
        parameter_names: [
          "Device.DeviceInfo.ModelName",
          "Device.Optical.Interface.1.OpticalSignalLevel"
        ]
      }
  """
  @spec get_parameters([String.t()], device_type()) :: GetParameterValues.t()
  def get_parameters(canonical_names, device_type) when is_list(canonical_names) do
    device_paths =
      Enum.map(canonical_names, fn name ->
        ParameterMapping.to_device_path(name, device_type)
      end)

    GetParameterValues.new(device_paths)
  end

  @doc """
  Generate GetParameterValues RPC for all device info parameters.

  Returns standard device information (manufacturer, model, serial, software version).
  """
  @spec get_device_info(device_type()) :: GetParameterValues.t()
  def get_device_info(device_type) do
    canonical_names = [
      "Device.Manufacturer",
      "Device.Model",
      "Device.SerialNumber",
      "Device.SoftwareVersion",
      "Device.HardwareVersion"
    ]

    get_parameters(canonical_names, device_type)
  end

  @doc """
  Generate GetParameterValues RPC for PON-specific parameters.

  Only applicable to GPON/XGSPON ONT devices.
  """
  @spec get_pon_status(device_type()) :: GetParameterValues.t() | {:error, :not_pon_device}
  def get_pon_status({type, vendor}) when type in [:gpon_ont, :xgspon_ont] do
    canonical_names = [
      "PON.Status",
      "PON.RxPower",
      "PON.TxPower",
      "PON.Temperature",
      "PON.Voltage"
    ]

    get_parameters(canonical_names, {type, vendor})
  end

  def get_pon_status(_device_type), do: {:error, :not_pon_device}

  @doc """
  Generate GetParameterValues RPC for DOCSIS-specific parameters.

  Only applicable to cable modem devices.
  """
  @spec get_docsis_status(device_type()) :: GetParameterValues.t() | {:error, :not_cable_modem}
  def get_docsis_status({:cable_modem, vendor}) do
    canonical_names = [
      "DOCSIS.Status",
      "DOCSIS.BootState",
      "DOCSIS.DownstreamChannels",
      "DOCSIS.UpstreamChannels",
      "DOCSIS.DS1.Power",
      "DOCSIS.DS1.SNR",
      "DOCSIS.US1.Power"
    ]

    get_parameters(canonical_names, {:cable_modem, vendor})
  end

  def get_docsis_status(_device_type), do: {:error, :not_cable_modem}

  @doc """
  Generate GetParameterValues RPC for WAN interface parameters.

  Applicable to most device types.
  """
  @spec get_wan_info(device_type()) :: GetParameterValues.t()
  def get_wan_info(device_type) do
    canonical_names = [
      "WAN.IPAddress",
      "WAN.SubnetMask",
      "WAN.Gateway"
    ]

    get_parameters(canonical_names, device_type)
  end

  @doc """
  Generate GetParameterValues RPC for WiFi parameters.

  Applicable to devices with WiFi capability.
  """
  @spec get_wifi_config(device_type()) :: GetParameterValues.t()
  def get_wifi_config(device_type) do
    canonical_names = [
      "WiFi.Enabled",
      "WiFi.SSID",
      "WiFi.Channel"
    ]

    get_parameters(canonical_names, device_type)
  end

  @doc """
  Generate SetParameterValues RPC with canonical parameter names.

  Automatically maps canonical names to device-specific TR-181 paths.

  ## Examples

      iex> set_parameters([{"WiFi.SSID", "NewNetwork"}], {:mikrotik, :routeros})
      %SetParameterValues{
        parameter_list: [
          {"Device.WiFi.SSID.1.SSID", "NewNetwork", "xsd:string"}
        ],
        parameter_key: ""
      }
  """
  @spec set_parameters([{String.t(), String.t()}], device_type(), String.t()) ::
          SetParameterValues.t()
  def set_parameters(canonical_params, device_type, parameter_key \\ "")
      when is_list(canonical_params) do
    device_params =
      Enum.map(canonical_params, fn {name, value} ->
        device_path = ParameterMapping.to_device_path(name, device_type)
        type = infer_xsd_type(value)
        %{name: device_path, value: value, type: type}
      end)

    SetParameterValues.new(device_params, parameter_key: parameter_key)
  end

  @doc """
  Generate SetParameterValues RPC to configure WiFi.
  """
  @spec configure_wifi(String.t(), String.t() | nil, device_type()) :: SetParameterValues.t()
  def configure_wifi(ssid, password \\ nil, device_type) do
    params =
      if password do
        [{"WiFi.SSID", ssid}, {"WiFi.Password", password}, {"WiFi.Enabled", "true"}]
      else
        [{"WiFi.SSID", ssid}, {"WiFi.Enabled", "true"}]
      end

    set_parameters(params, device_type, "ConfigureWiFi")
  end

  @doc """
  Generate SetParameterValues RPC to configure WAN interface.
  """
  @spec configure_wan(String.t(), String.t(), String.t(), device_type()) ::
          SetParameterValues.t()
  def configure_wan(ip_address, subnet_mask, gateway, device_type) do
    params = [
      {"WAN.IPAddress", ip_address},
      {"WAN.SubnetMask", subnet_mask},
      {"WAN.Gateway", gateway}
    ]

    set_parameters(params, device_type, "ConfigureWAN")
  end

  @doc """
  Check if a parameter is supported for the given device type.
  """
  @spec parameter_supported?(String.t(), device_type()) :: boolean()
  def parameter_supported?(canonical_name, device_type) do
    ParameterMapping.supported?(canonical_name, device_type)
  end

  @doc """
  Get list of all supported parameters for a device type.
  """
  @spec supported_parameters(device_type()) :: [String.t()]
  def supported_parameters(device_type) do
    ParameterMapping.supported_parameters(device_type)
  end

  # Helper to infer XSD type from value
  defp infer_xsd_type(value) when is_boolean(value), do: "xsd:boolean"
  defp infer_xsd_type(value) when is_integer(value), do: "xsd:int"

  defp infer_xsd_type(value) when is_float(value), do: "xsd:double"

  defp infer_xsd_type(value) when is_binary(value) do
    # Try to detect if it's a number string
    case Integer.parse(value) do
      {_int, ""} ->
        "xsd:int"

      _ ->
        case Float.parse(value) do
          {_float, ""} -> "xsd:double"
          _ -> "xsd:string"
        end
    end
  end

  defp infer_xsd_type(_), do: "xsd:string"
end
