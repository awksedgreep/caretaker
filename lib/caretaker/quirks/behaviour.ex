defmodule Caretaker.Quirks.Behaviour do
  @moduledoc """
  Behaviour definition for vendor-specific quirks modules.

  Each vendor quirks module must implement this behaviour to provide:
  - Request/response transformations
  - Parameter support detection
  - Vendor-specific notes and limitations
  """

  @doc """
  Transform a request envelope before sending to the CPE.

  This callback allows modification of requests to work around vendor-specific
  issues or limitations.
  """
  @callback transform_request(envelope :: map()) :: map()

  @doc """
  Transform a response envelope received from the CPE.

  This callback allows normalization of vendor-specific response formats
  to standard TR-069 format.
  """
  @callback transform_response(envelope :: map()) :: map()

  @doc """
  Check if a parameter path is supported by this vendor.

  Returns true if the parameter is known to be supported, false if unsupported.
  """
  @callback supported_parameter?(parameter_path :: String.t()) :: boolean()

  @doc """
  Get vendor-specific notes or warnings about a parameter.

  Returns a list of human-readable notes about parameter behavior.
  """
  @callback parameter_notes(parameter_path :: String.t()) :: [String.t()]

  @doc """
  Get the vendor name.
  """
  @callback vendor_name() :: String.t()

  @doc """
  Get a list of all supported parameter paths.
  """
  @callback supported_parameters() :: [String.t()]
end
