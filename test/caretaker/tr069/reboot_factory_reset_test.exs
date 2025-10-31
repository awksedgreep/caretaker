defmodule Caretaker.TR069.RebootFactoryResetTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.{Reboot, RebootResponse, FactoryReset, FactoryResetResponse}

  test "Reboot encode/decode" do
    r = Reboot.new(command_key: "CK-1")
    {:ok, body} = Reboot.encode(r)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "R1"})
    {:ok, %{body: %{rpc: "Reboot", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %Reboot{command_key: "CK-1"}} = Reboot.decode(xml)
  end

  test "RebootResponse encode/decode" do
    {:ok, body} = RebootResponse.encode(%RebootResponse{})
    {:ok, env} = SOAP.encode_envelope(body, %{id: "RR"})
    {:ok, %{body: %{rpc: "RebootResponse", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %RebootResponse{}} = RebootResponse.decode(xml)
  end

  test "FactoryReset encode/decode" do
    {:ok, body} = FactoryReset.encode(%FactoryReset{})
    {:ok, env} = SOAP.encode_envelope(body, %{id: "F1"})
    {:ok, %{body: %{rpc: "FactoryReset", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %FactoryReset{}} = FactoryReset.decode(xml)
  end

  test "FactoryResetResponse encode/decode" do
    {:ok, body} = FactoryResetResponse.encode(%FactoryResetResponse{})
    {:ok, env} = SOAP.encode_envelope(body, %{id: "FR"})
    {:ok, %{body: %{rpc: "FactoryResetResponse", xml: xml}}} = SOAP.decode_envelope(IO.iodata_to_binary(env))
    assert {:ok, %FactoryResetResponse{}} = FactoryResetResponse.decode(xml)
  end
end