defmodule Caretaker.TR069.DiagnosticsTraceRouteTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.Diagnostics.TraceRoute

  test "build_spv emits SPV for TraceRouteDiagnostics with Requested state" do
    cfg = TraceRoute.new(host: "example.com", max_hop_count: 20, parameter_key: "diag2")
    {:ok, body} = TraceRoute.build_spv(cfg)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "D2"})
    xml = IO.iodata_to_binary(env)
    assert xml =~ "Device.IP.Diagnostics.TraceRouteDiagnostics.Host"
    assert xml =~ "Requested"
    assert xml =~ "<ParameterKey>diag2</ParameterKey>"
  end
end