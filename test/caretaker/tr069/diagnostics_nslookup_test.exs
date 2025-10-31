defmodule Caretaker.TR069.DiagnosticsNSLookupTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.Diagnostics.NSLookup

  test "build_spv emits SPV for NSLookupDiagnostics with Requested state" do
    cfg = NSLookup.new(host_name: "example.com", number_of_repetitions: 2, parameter_key: "diag3")
    {:ok, body} = NSLookup.build_spv(cfg)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "D3"})
    xml = IO.iodata_to_binary(env)
    assert xml =~ "Device.DNS.Diagnostics.NSLookupDiagnostics.HostName"
    assert xml =~ "Requested"
    assert xml =~ "<ParameterKey>diag3</ParameterKey>"
  end
end