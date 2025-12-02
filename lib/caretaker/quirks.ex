defmodule Caretaker.Quirks do
  @moduledoc """
  Registry and dispatcher for vendor-specific TR-069 quirks.

  This module provides a central registry for vendor-specific adaptations and
  workarounds needed to handle deviations from the TR-069/CWMP specification.

  ## Overview

  Different CPE vendors implement TR-069 with varying degrees of compliance.
  Some have limited parameter support, non-standard request/response formats,
  or vendor-specific extensions. This module allows the ACS to detect and
  adapt to these quirks automatically.

  ## Usage

      # Detect quirks based on OUI
      quirks = Quirks.get_quirks("D4CA6D")  # Mikrotik OUI

      # Apply request transformations before sending to CPE
      transformed_request = Quirks.apply_request_quirks(envelope, oui)

      # Apply response transformations after receiving from CPE
      transformed_response = Quirks.apply_response_quirks(envelope, oui)

      # Check if a parameter is supported by the vendor
      supported? = Quirks.supported_parameter?(oui, "Device.WiFi.Radio.1.Channel")

  ## Supported Vendors

  - **Mikrotik (D4CA6D, 2CC81B, E48D8C)** - RouterOS TR-069 package limitations
  """

  @type oui :: String.t()
  @type quirks_module :: module()

  # OUI to quirks module mapping
  @quirks_registry %{
    # Mikrotik OUIs
    "D4CA6D" => Caretaker.Quirks.Mikrotik,
    "2CC81B" => Caretaker.Quirks.Mikrotik,
    "E48D8C" => Caretaker.Quirks.Mikrotik
  }

  @doc """
  Get the quirks module for a specific OUI.

  Returns the quirks module if one is registered for the OUI, otherwise nil.
  OUI lookup is case-insensitive.

  ## Examples

      iex> Quirks.get_quirks("D4CA6D")
      Caretaker.Quirks.Mikrotik

      iex> Quirks.get_quirks("d4ca6d")
      Caretaker.Quirks.Mikrotik

      iex> Quirks.get_quirks("UNKNOWN")
      nil
  """
  @spec get_quirks(oui()) :: quirks_module() | nil
  def get_quirks(oui) when is_binary(oui) do
    Map.get(@quirks_registry, String.upcase(oui))
  end

  def get_quirks(_), do: nil

  @doc """
  Apply request quirks to an envelope before sending to CPE.

  If quirks exist for the OUI, delegates to the quirks module's
  `transform_request/1` function. Otherwise, returns the envelope unchanged.

  ## Examples

      envelope = %{...}
      transformed = Quirks.apply_request_quirks(envelope, "D4CA6D")
  """
  @spec apply_request_quirks(map(), oui()) :: map()
  def apply_request_quirks(envelope, oui) do
    case get_quirks(oui) do
      nil -> envelope
      mod -> mod.transform_request(envelope)
    end
  end

  @doc """
  Apply response quirks to an envelope received from CPE.

  If quirks exist for the OUI, delegates to the quirks module's
  `transform_response/1` function. Otherwise, returns the envelope unchanged.

  ## Examples

      envelope = %{...}
      transformed = Quirks.apply_response_quirks(envelope, "D4CA6D")
  """
  @spec apply_response_quirks(map(), oui()) :: map()
  def apply_response_quirks(envelope, oui) do
    case get_quirks(oui) do
      nil -> envelope
      mod -> mod.transform_response(envelope)
    end
  end

  @doc """
  Check if a parameter is supported by the vendor.

  Returns true if the parameter is known to be supported, false if unsupported,
  or nil if no quirks information exists for the OUI.

  ## Examples

      iex> Quirks.supported_parameter?("D4CA6D", "Device.ManagementServer.URL")
      true

      iex> Quirks.supported_parameter?("D4CA6D", "Device.WiFi.AccessPoint.1.Security.X_COMPLEX_PARAM")
      false

      iex> Quirks.supported_parameter?("UNKNOWN", "Device.DeviceInfo.Manufacturer")
      nil
  """
  @spec supported_parameter?(oui(), String.t()) :: boolean() | nil
  def supported_parameter?(oui, parameter_path) do
    case get_quirks(oui) do
      nil -> nil
      mod -> mod.supported_parameter?(parameter_path)
    end
  end

  @doc """
  Get vendor-specific notes or warnings for a parameter.

  Returns a list of notes/warnings about the parameter's behavior on this vendor,
  or an empty list if no quirks exist.

  ## Examples

      iex> Quirks.parameter_notes("D4CA6D", "Device.ManagementServer.PeriodicInformInterval")
      ["Minimum supported interval is 60 seconds", "Changes require reboot"]
  """
  @spec parameter_notes(oui(), String.t()) :: [String.t()]
  def parameter_notes(oui, parameter_path) do
    case get_quirks(oui) do
      nil -> []
      mod -> mod.parameter_notes(parameter_path)
    end
  end

  @doc """
  Get a list of all registered OUIs with quirks.

  ## Examples

      iex> Quirks.registered_ouis()
      ["D4CA6D", "2CC81B", "E48D8C"]
  """
  @spec registered_ouis() :: [oui()]
  def registered_ouis do
    Map.keys(@quirks_registry)
  end

  @doc """
  Get vendor information for an OUI.

  ## Examples

      iex> Quirks.vendor_info("D4CA6D")
      %{name: "MikroTik", quirks_module: Caretaker.Quirks.Mikrotik}
  """
  @spec vendor_info(oui()) :: map() | nil
  def vendor_info(oui) do
    case get_quirks(oui) do
      nil ->
        nil

      mod ->
        %{
          name: mod.vendor_name(),
          quirks_module: mod,
          supported_parameters_count: length(mod.supported_parameters())
        }
    end
  end
end
