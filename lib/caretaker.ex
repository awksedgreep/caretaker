defmodule Caretaker do
  @moduledoc """
  Caretaker — an Elixir TR-069/TR-181 toolkit.

  This library provides:
    - CWMP SOAP helpers built on Lather
    - TR-069 RPC structs and codecs
    - A minimal ACS server with Plug and Bandit
    - Telemetry events under the :caretaker prefix
  """

  @typedoc "Telemetry prefix for all events from this library"
  @type telemetry_prefix :: [atom()]

  @spec telemetry_prefix() :: telemetry_prefix()
  def telemetry_prefix, do: [:caretaker]
end
