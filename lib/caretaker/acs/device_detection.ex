defmodule Caretaker.ACS.DeviceDetection do
  @moduledoc """
  Detect device type and vendor from Inform message.

  Uses DeviceId (OUI, manufacturer, product class) and optional parameters
  to identify the specific device type and vendor. This enables device-specific
  handling, quirks application, and parameter mapping.
  """

  require Logger

  @type device_type ::
          {:mikrotik, :routeros}
          | {:gpon_ont, vendor()}
          | {:xgspon_ont, vendor()}
          | {:cable_modem, vendor()}
          | {:router, :generic}
          | {:generic, :unknown}

  @type vendor ::
          :huawei
          | :zte
          | :nokia
          | :fiberhome
          | :arris
          | :technicolor
          | :netgear
          | :cisco
          | :ubiquiti
          | :unknown

  @type device_info :: %{
          type: device_type(),
          oui: String.t(),
          manufacturer: String.t(),
          product_class: String.t(),
          serial_number: String.t(),
          model: String.t() | nil,
          software_version: String.t() | nil
        }

  # Known OUIs for device vendors
  @mikrotik_ouis ["D4CA6D", "2CC81B", "E48D8C", "6C3B6B", "4C5E0C", "000C42"]

  @huawei_ouis ["00E0FC", "ECE309", "5C5476", "48F317", "007B72"]

  @zte_ouis ["001E58", "48F222", "F8E7B5", "5C353B", "705DAC"]

  @nokia_ouis ["0004ED", "00E0B1", "D8D385", "7C7D3D", "A81B5A"]

  @fiberhome_ouis ["706D15", "68DBCA", "3468A7", "1CA77C"]

  @arris_ouis ["0015A4", "001A1B", "001DD8", "002205", "44E9DD"]

  @technicolor_ouis ["00195E", "64D9EA", "C4665C", "7838EE", "00145E"]

  @doc """
  Detect device type from Inform message.

  ## Examples

      iex> inform = %Inform{device_id: %{oui: "D4CA6D", manufacturer: "MikroTik", product_class: "RouterOS", serial_number: "123"}}
      iex> DeviceDetection.detect(inform)
      %{type: {:mikrotik, :routeros}, oui: "D4CA6D", manufacturer: "MikroTik", product_class: "RouterOS", serial_number: "123", model: nil, software_version: nil}
  """
  @spec detect(Caretaker.TR069.RPC.Inform.t()) :: device_info()
  def detect(%Caretaker.TR069.RPC.Inform{} = inform) do
    oui = normalize_oui(inform.device_id.oui)
    manufacturer = inform.device_id.manufacturer
    product_class = inform.device_id.product_class
    serial_number = inform.device_id.serial_number

    # Extract model and version from parameter list if available
    model = get_param_value(inform.parameter_list, "Device.DeviceInfo.ModelName")

    software_version =
      get_param_value(inform.parameter_list, "Device.DeviceInfo.SoftwareVersion")

    device_type =
      cond do
        is_mikrotik?(oui, manufacturer) ->
          {:mikrotik, :routeros}

        # Check XGS-PON before GPON since "XGSPON" contains "PON"
        is_xgspon_ont?(product_class, model) ->
          {:xgspon_ont, detect_ont_vendor(oui, manufacturer)}

        is_gpon_ont?(product_class, model) ->
          {:gpon_ont, detect_ont_vendor(oui, manufacturer)}

        is_cable_modem?(product_class, model) ->
          {:cable_modem, detect_cm_vendor(oui, manufacturer)}

        is_router?(product_class, model) ->
          {:router, :generic}

        true ->
          {:generic, :unknown}
      end

    Logger.info("Detected device type: #{inspect(device_type)} for OUI: #{oui}")

    %{
      type: device_type,
      oui: oui,
      manufacturer: manufacturer,
      product_class: product_class,
      serial_number: serial_number,
      model: model,
      software_version: software_version
    }
  end

  @doc """
  Check if device is a Mikrotik RouterOS device.
  """
  @spec is_mikrotik?(String.t(), String.t()) :: boolean()
  def is_mikrotik?(oui, manufacturer) do
    oui in @mikrotik_ouis or
      String.contains?(String.downcase(manufacturer), ["mikrotik", "routeros"])
  end

  @doc """
  Check if device is a GPON ONT.
  """
  @spec is_gpon_ont?(String.t(), String.t() | nil) :: boolean()
  def is_gpon_ont?(product_class, model) do
    pc = String.downcase(product_class)
    m = if model, do: String.downcase(model), else: ""

    String.contains?(pc, ["ont", "onu", "gpon"]) or
      (String.contains?(m, ["ont", "onu", "gpon"]) and not String.contains?(m, ["xgs", "10g"]))
  end

  @doc """
  Check if device is an XGS-PON ONT.
  """
  @spec is_xgspon_ont?(String.t(), String.t() | nil) :: boolean()
  def is_xgspon_ont?(product_class, model) do
    pc = String.downcase(product_class)
    m = if model, do: String.downcase(model), else: ""

    String.contains?(pc, ["xgspon", "xgs-pon", "10gpon", "xgs_pon"]) or
      String.contains?(m, ["xgs", "10g"])
  end

  @doc """
  Check if device is a cable modem (DOCSIS).
  """
  @spec is_cable_modem?(String.t(), String.t() | nil) :: boolean()
  def is_cable_modem?(product_class, model) do
    pc = String.downcase(product_class)
    m = if model, do: String.downcase(model), else: ""

    String.contains?(pc, ["cm", "cable", "docsis", "emta"]) or
      String.contains?(m, ["cm", "cable", "docsis", "emta"])
  end

  @doc """
  Check if device is a generic router.
  """
  @spec is_router?(String.t(), String.t() | nil) :: boolean()
  def is_router?(product_class, model) do
    pc = String.downcase(product_class)
    m = if model, do: String.downcase(model), else: ""

    String.contains?(pc, ["router", "gateway", "cpe"]) or
      String.contains?(m, ["router", "gateway"])
  end

  @doc """
  Detect ONT vendor from OUI and manufacturer string.
  """
  @spec detect_ont_vendor(String.t(), String.t()) :: vendor()
  def detect_ont_vendor(oui, manufacturer) do
    mfg = String.downcase(manufacturer)

    cond do
      oui in @huawei_ouis or String.contains?(mfg, "huawei") -> :huawei
      oui in @zte_ouis or String.contains?(mfg, "zte") -> :zte
      oui in @nokia_ouis or String.contains?(mfg, "nokia") -> :nokia
      oui in @fiberhome_ouis or String.contains?(mfg, "fiberhome") -> :fiberhome
      true -> :unknown
    end
  end

  @doc """
  Detect cable modem vendor from OUI and manufacturer string.
  """
  @spec detect_cm_vendor(String.t(), String.t()) :: vendor()
  def detect_cm_vendor(oui, manufacturer) do
    mfg = String.downcase(manufacturer)

    cond do
      oui in @arris_ouis or String.contains?(mfg, "arris") -> :arris
      oui in @technicolor_ouis or String.contains?(mfg, "technicolor") -> :technicolor
      String.contains?(mfg, "netgear") -> :netgear
      String.contains?(mfg, "cisco") -> :cisco
      String.contains?(mfg, "ubiquiti") -> :ubiquiti
      true -> :unknown
    end
  end

  @doc """
  Normalize OUI format (remove colons, uppercase).
  """
  @spec normalize_oui(String.t()) :: String.t()
  def normalize_oui(oui) do
    oui
    |> String.replace(":", "")
    |> String.replace("-", "")
    |> String.upcase()
  end

  # Helper to extract parameter value from parameter list
  defp get_param_value(param_list, name) when is_list(param_list) do
    Enum.find_value(param_list, fn
      %{name: ^name, value: value} -> value
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp get_param_value(_, _), do: nil
end
