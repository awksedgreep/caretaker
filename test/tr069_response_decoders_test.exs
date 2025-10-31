defmodule Caretaker.TR069.ResponseDecodersTest do
  use ExUnit.Case, async: true

  alias Caretaker.TR069.RPC.{
    GetParameterValuesResponse,
    GetParameterNamesResponse,
    SetParameterValuesResponse,
    AddObjectResponse,
    DeleteObjectResponse
  }

  test "GetParameterValuesResponse decode" do
    xml = """
    <cwmp:GetParameterValuesResponse xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">
      <ParameterList>
        <ParameterValueStruct>
          <Name>Device.DeviceInfo.Manufacturer</Name>
          <Value xsi:type=\"xsd:string\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">Acme</Value>
        </ParameterValueStruct>
      </ParameterList>
    </cwmp:GetParameterValuesResponse>
    """

    assert {:ok,
            %{
              parameters: [
                %{name: "Device.DeviceInfo.Manufacturer", value: "Acme", type: "xsd:string"}
              ]
            }} =
             GetParameterValuesResponse.decode(xml)
  end

  test "GetParameterNamesResponse decode" do
    xml = """
    <cwmp:GetParameterNamesResponse xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">
      <ParameterList>
        <ParameterInfoStruct>
          <Name>Device.DeviceInfo.</Name>
          <Writable>0</Writable>
        </ParameterInfoStruct>
      </ParameterList>
    </cwmp:GetParameterNamesResponse>
    """

    assert {:ok, %{parameters: [%{name: "Device.DeviceInfo.", writable: false}]}} =
             GetParameterNamesResponse.decode(xml)
  end

  test "SetParameterValuesResponse decode" do
    xml = """
    <cwmp:SetParameterValuesResponse xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\"><Status>0</Status></cwmp:SetParameterValuesResponse>
    """

    assert {:ok, %{status: 0}} = SetParameterValuesResponse.decode(xml)
  end

  test "AddObjectResponse decode" do
    xml = """
    <cwmp:AddObjectResponse xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\"><InstanceNumber>5</InstanceNumber><Status>0</Status></cwmp:AddObjectResponse>
    """

    assert {:ok, %{instance_number: 5, status: 0}} = AddObjectResponse.decode(xml)
  end

  test "DeleteObjectResponse decode" do
    xml = """
    <cwmp:DeleteObjectResponse xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\"><Status>0</Status></cwmp:DeleteObjectResponse>
    """

    assert {:ok, %{status: 0}} = DeleteObjectResponse.decode(xml)
  end
end
