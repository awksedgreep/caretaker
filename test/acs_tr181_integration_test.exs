defmodule Caretaker.ACS.TR181IntegrationTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias Caretaker.CWMP.SOAP
  alias Caretaker.TR069.RPC.GetParameterValuesResponse

  setup do
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)
    _ = start_supervised(Caretaker.TR181.Store)
    :ok
  end

  test "Inform -> Store GPV response into TR-181 store and 204" do
    # 1) Inform
    xml = File.read!("test/fixtures/tr069/inform.xml")
    conn1 = conn(:post, "/cwmp", xml)
    conn1 = Caretaker.ACS.Server.call(conn1, Caretaker.ACS.Server.init([]))
    assert conn1.status == 200

    # 2) Device posts GetParameterValuesResponse
    gpv_resp = %{parameters: [
      %{name: "Device.DeviceInfo.Manufacturer", value: "Acme", type: "xsd:string"},
      %{name: "Device.DeviceInfo.SerialNumber", value: "XYZ123", type: "xsd:string"}
    ]}
    {:ok, body} = GetParameterValuesResponse.encode(gpv_resp)
    {:ok, envelope} = SOAP.encode_envelope(body, %{id: "ID123", cwmp_ns: "urn:dslforum-org:cwmp-1-0"})

    conn2 = conn(:post, "/cwmp", IO.iodata_to_binary(envelope))
    conn2 = Caretaker.ACS.Server.call(conn2, Caretaker.ACS.Server.init([]))
    assert conn2.status == 204

    # 3) Verify stored model
    # Session bound to default 127.0.0.1; fetch dev_key via session API
    dev_key = Caretaker.ACS.Session.device_key_for_ip({127, 0, 0, 1})
    model = Caretaker.TR181.Store.get(dev_key)
    assert model["Device"]["DeviceInfo"]["Manufacturer"] == "Acme"
  end
end