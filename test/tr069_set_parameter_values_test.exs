defmodule Caretaker.TR069.RPC.SetParameterValuesTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.SetParameterValues

  test "encode request with parameters" do
    req =
      SetParameterValues.new([
        %{name: "Device.DeviceInfo.Manufacturer", value: "Acme", type: "xsd:string"},
        %{name: "Device.DeviceInfo.SerialNumber", value: "XYZ", type: "xsd:string"}
      ], parameter_key: "k1")

    assert {:ok, body} = SetParameterValues.encode(req)
    xml = IO.iodata_to_binary(body)
    assert xml =~ "<cwmp:SetParameterValues>"
    assert xml =~ "<ParameterValueStruct>"
    assert xml =~ "<Name>Device.DeviceInfo.Manufacturer</Name>"
    assert xml =~ "<Value xsi:type=\"xsd:string\">Acme</Value>"
    assert xml =~ "<ParameterKey>k1</ParameterKey>"
  end
end