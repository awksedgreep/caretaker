defmodule Caretaker.TR181.StoreDeepMergeTest do
  use ExUnit.Case, async: true
  alias Caretaker.TR181.Store
  alias Caretaker.TR181.Schema

  setup do
    start_supervised!(Store)
    :ok
  end

  test "merge_params casts and stores nested model" do
    key = {"A1B2C3", "PC", "SN123"}

    params = [
      %{name: "Device.DeviceInfo.Manufacturer", value: "ACME", type: "xsd:string"},
      %{name: "Device.DeviceInfo.SerialNumber", value: "SN123", type: "xsd:string"},
      %{name: "Device.DeviceInfo.UpTime", value: "3600", type: "xsd:int"}
    ]

    assert :ok == Store.merge_params(key, params, Schema.default())

    assert %{
             "Device" => %{
               "DeviceInfo" => %{
                 "Manufacturer" => "ACME",
                 "SerialNumber" => "SN123",
                 "UpTime" => 3600
               }
             }
           } = Store.get(key)
  end

  test "deep merge for different branches" do
    key = {"A", "PC", "SN"}
    schema = %{}

    assert :ok =
             Store.merge_params(
               key,
               [
                 %{
                   name: "Device.WANDevice.1.WANConnectionDevice.1.Param",
                   value: "X",
                   type: "xsd:string"
                 }
               ],
               schema
             )

    assert :ok =
             Store.merge_params(
               key,
               [
                 %{
                   name: "Device.WANDevice.1.WANConnectionDevice.2.Param",
                   value: "Y",
                   type: "xsd:string"
                 }
               ],
               schema
             )

    model = Store.get(key)

    assert model["Device"]["WANDevice"]["1"]["WANConnectionDevice"]["1"]["Param"] == "X"
    assert model["Device"]["WANDevice"]["1"]["WANConnectionDevice"]["2"]["Param"] == "Y"
  end

  test "validation failure does not mutate store" do
    key = {"A", "PC", "SN"}
    bad_params = [%{name: "Device.DeviceInfo.UpTime", value: "abc", type: "xsd:int"}]

    assert {:error, _} = Store.merge_params(key, bad_params, Schema.default())
    assert nil == Store.get(key)
  end
end
