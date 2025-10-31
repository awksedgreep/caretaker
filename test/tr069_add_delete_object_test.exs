defmodule Caretaker.TR069.RPC.AddDeleteObjectTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.{AddObject, DeleteObject}

  test "encode add and delete object" do
    assert {:ok, add} =
             AddObject.encode(AddObject.new("Device.WiFi.SSID.1.", parameter_key: "k2"))

    s1 = IO.iodata_to_binary(add)
    assert s1 =~ "<cwmp:AddObject>"
    assert s1 =~ "<ObjectName>Device.WiFi.SSID.1.</ObjectName>"
    assert s1 =~ "<ParameterKey>k2</ParameterKey>"

    assert {:ok, del} =
             DeleteObject.encode(DeleteObject.new("Device.WiFi.SSID.1.", parameter_key: "k3"))

    s2 = IO.iodata_to_binary(del)
    assert s2 =~ "<cwmp:DeleteObject>"
    assert s2 =~ "<ObjectName>Device.WiFi.SSID.1.</ObjectName>"
    assert s2 =~ "<ParameterKey>k3</ParameterKey>"
  end
end
