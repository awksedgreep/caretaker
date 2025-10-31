defmodule Caretaker.TR069.ParameterAttributesTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{GetParameterAttributes, GetParameterAttributesResponse, SetParameterAttributes, SetParameterAttributesResponse}

  test "GetParameterAttributes encode/decode" do
    req = GetParameterAttributes.new(["Device.", "Device.ManagementServer."])
    {:ok, body} = GetParameterAttributes.encode(req)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "PA1"})
    {:ok, %{body: %{rpc: "GetParameterAttributes", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %GetParameterAttributes{names: ["Device.", "Device.ManagementServer."]}} = GetParameterAttributes.decode(xml)
  end

  test "GetParameterAttributesResponse encode/decode" do
    resp = %{parameters: [%{name: "Device.", notification: 0, access_list: ["Subscriber", "ACS"]}]}
    {:ok, body} = GetParameterAttributesResponse.encode(resp)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "PA2"})
    {:ok, %{body: %{rpc: "GetParameterAttributesResponse", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %{parameters: [got]}} = GetParameterAttributesResponse.decode(xml)
    assert got.name == "Device."
    assert got.notification == 0
    assert got.access_list == ["Subscriber", "ACS"]
  end

  test "SetParameterAttributes encode/decode and response" do
    req = %{parameters: [%{name: "Device.", notification_change: true, notification: 1, access_list_change: true, access_list: ["ACS"]}]}
    {:ok, body} = SetParameterAttributes.encode(req)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "SP1"})
    {:ok, %{body: %{rpc: "SetParameterAttributes", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %{parameters: [got]}} = SetParameterAttributes.decode(xml)
    assert got.name == "Device."
    assert got.notification_change == true
    assert got.notification == 1
    assert got.access_list_change == true
    assert got.access_list == ["ACS"]

    {:ok, body2} = SetParameterAttributesResponse.encode(%SetParameterAttributesResponse{})
    {:ok, env2} = SOAP.encode_envelope(body2, %{id: "SP2"})
    {:ok, %{body: %{rpc: "SetParameterAttributesResponse", xml: xml2}}} = SOAP.decode_envelope(IO.iodata_to_binary(env2))
    assert {:ok, %SetParameterAttributesResponse{}} = SetParameterAttributesResponse.decode(xml2)
  end
end