defmodule Caretaker.TR069.ResponseEncodersTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.{
    GetParameterValuesResponse,
    GetParameterNamesResponse,
    SetParameterValuesResponse,
    AddObjectResponse,
    DeleteObjectResponse
  }

  test "encode/decode GetParameterValuesResponse" do
    data = %{
      parameters: [%{name: "Device.DeviceInfo.Manufacturer", value: "Acme", type: "xsd:string"}]
    }

    assert {:ok, xml} = GetParameterValuesResponse.encode(data)
    assert xml =~ "<cwmp:GetParameterValuesResponse>"
    assert {:ok, ^data} = GetParameterValuesResponse.decode(xml)
  end

  test "encode/decode GetParameterNamesResponse" do
    data = %{parameters: [%{name: "Device.", writable: true}]}
    assert {:ok, xml} = GetParameterNamesResponse.encode(data)
    assert xml =~ "<cwmp:GetParameterNamesResponse>"
    assert {:ok, ^data} = GetParameterNamesResponse.decode(xml)
  end

  test "encode/decode SetParameterValuesResponse" do
    data = %{status: 0}
    assert {:ok, xml} = SetParameterValuesResponse.encode(data)
    assert xml =~ "<cwmp:SetParameterValuesResponse>"
    assert {:ok, ^data} = SetParameterValuesResponse.decode(xml)
  end

  test "encode/decode AddObjectResponse" do
    data = %{instance_number: 7, status: 0}
    assert {:ok, xml} = AddObjectResponse.encode(data)
    assert xml =~ "<cwmp:AddObjectResponse>"
    assert {:ok, ^data} = AddObjectResponse.decode(xml)
  end

  test "encode/decode DeleteObjectResponse" do
    data = %{status: 0}
    assert {:ok, xml} = DeleteObjectResponse.encode(data)
    assert xml =~ "<cwmp:DeleteObjectResponse>"
    assert {:ok, ^data} = DeleteObjectResponse.decode(xml)
  end
end
