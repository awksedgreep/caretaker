defmodule Caretaker.TR181.Schema do
  @moduledoc """
  Minimal schema for TR-181 parameter types and simple constraints.
  """

  @type rule ::
          :required | {:type, String.t()} | {:min, number()} | {:max, number()} | {:enum, [any()]}
  @type t :: %{optional(String.t()) => [rule]}

  @doc "Example default schema for Device.DeviceInfo.*"
  @spec default() :: t()
  def default do
    %{
      "Device.DeviceInfo.Manufacturer" => [:required, {:type, "xsd:string"}],
      "Device.DeviceInfo.SerialNumber" => [:required, {:type, "xsd:string"}],
      "Device.DeviceInfo.UpTime" => [{:type, "xsd:int"}, {:min, 0}]
    }
  end
end
