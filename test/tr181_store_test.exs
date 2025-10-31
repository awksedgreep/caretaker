defmodule Caretaker.TR181.StoreTest do
  use ExUnit.Case, async: false

  alias Caretaker.TR181.{Store, Schema}

  setup do
    {:ok, _} = start_supervised(Store)
    :ok
  end

  test "merge validated params into device model and fetch" do
    key = {"A1B2C3", "Router", "XYZ123"}

    params = [
      %{name: "Device.DeviceInfo.Manufacturer", value: "Acme", type: "xsd:string"},
      %{name: "Device.DeviceInfo.SerialNumber", value: "SN123", type: "xsd:string"},
      %{name: "Device.DeviceInfo.UpTime", value: "30", type: "xsd:int"}
    ]

    assert :ok = Store.merge_params(key, params, Schema.default())

    model = Store.get(key)
    assert model["Device"]["DeviceInfo"]["Manufacturer"] == "Acme"
    assert model["Device"]["DeviceInfo"]["UpTime"] == 30
  end

  test "validation errors are returned and model not updated" do
    key = {"A1B2C3", "Router", "XYZ123"}

    bad = [%{name: "Device.DeviceInfo.UpTime", value: "-5", type: "xsd:int"}]

    assert {:error, errs} = Store.merge_params(key, bad, Schema.default())
    assert {"Device.DeviceInfo.Manufacturer", :required} in errs
    assert {"Device.DeviceInfo.SerialNumber", :required} in errs
    assert {"Device.DeviceInfo.UpTime", {:min, 0}} in errs

    assert Store.get(key) == nil
  end
end