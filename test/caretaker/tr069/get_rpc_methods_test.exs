defmodule Caretaker.TR069.GetRPCMethodsTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{GetRPCMethods, GetRPCMethodsResponse}

  test "GetRPCMethods request/response round-trip" do
    {:ok, body} = GetRPCMethods.encode(%GetRPCMethods{})
    {:ok, env} = SOAP.encode_envelope(body, %{id: "GR1"})
    {:ok, %{body: %{rpc: "GetRPCMethods", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %GetRPCMethods{}} = GetRPCMethods.decode(xml)

    methods = ["Inform", "InformResponse", "GetParameterValues", "Download"]
    {:ok, body2} = GetRPCMethodsResponse.encode(%GetRPCMethodsResponse{methods: methods})
    {:ok, env2} = SOAP.encode_envelope(body2, %{id: "GR2"})
    {:ok, %{body: %{rpc: "GetRPCMethodsResponse", xml: xml2}}} = SOAP.decode_envelope(IO.iodata_to_binary(env2))
    assert {:ok, %GetRPCMethodsResponse{methods: back}} = GetRPCMethodsResponse.decode(xml2)
    assert back == methods
  end
end