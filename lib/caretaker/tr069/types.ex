defmodule Caretaker.TR069.Types do
  @moduledoc """
  Common TR-069 types and validations.
  """

  @type oui :: String.t()
  @type product_class :: String.t()
  @type serial_number :: String.t()
  @type event_code :: String.t()

  @spec valid_oui?(String.t()) :: boolean()
  def valid_oui?(value) when is_binary(value) and byte_size(value) == 6, do: true
  def valid_oui?(_), do: false
end
