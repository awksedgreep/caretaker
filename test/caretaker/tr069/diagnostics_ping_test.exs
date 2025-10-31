defmodule Caretaker.TR069.DiagnosticsPingTest do
  use ExUnit.Case, async: true

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.Diagnostics.Ping

  test "build_spv emits SPV for PingDiagnostics with Requested state" do
    cfg = Ping.new(host: "1.1.1.1", repetitions: 3, timeout: 1500, data_block_size: 64, parameter_key: "diag1")
    {:ok, body} = Ping.build_spv(cfg)
    {:ok, env} = SOAP.encode_envelope(body, %{id: "D1"})
    xml = IO.iodata_to_binary(env)
    assert xml =~ "<cwmp:SetParameterValues>"
    assert xml =~ "Device.IP.Diagnostics.PingDiagnostics.Host"
    assert xml =~ "Requested"
    assert xml =~ "<ParameterKey>diag1</ParameterKey>"
  end
end