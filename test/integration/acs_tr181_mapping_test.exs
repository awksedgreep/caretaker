defmodule Caretaker.Integration.ACSTR181MappingTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  alias Caretaker.ACS.Session
  alias Caretaker.ACS.Server
  alias Caretaker.TR181.Store

  setup do
    start_supervised!(Session)
    start_supervised!(Store)
    :ok
  end

  test "POST GetParameterValuesResponse maps into TR-181 store and emits telemetry" do
    # Bind IP -> device session
    ip = {127, 0, 0, 1}

    device_id = %{
      manufacturer: "ACME",
      oui: "A1B2C3",
      product_class: "PC",
      serial_number: "SN123"
    }

    :ok = Session.upsert_from_ip(ip, device_id, "urn:dslforum-org:cwmp-1-0")

    # Attach telemetry
    parent = self()
    handler_id = {__MODULE__, :tr181_updated}

    :telemetry.attach(
      handler_id,
      [:caretaker, :tr181, :store, :updated],
      fn _e, _m, _meta, _cfg ->
        send(parent, :tr181_updated)
      end,
      %{}
    )

    # Load fixture and POST
    xml =
      File.read!(
        Path.expand("../../test/fixtures/tr069/get_parameter_values_response.xml", __DIR__)
      )

    conn =
      conn(:post, "/cwmp", xml)
      |> put_req_header("content-type", "text/xml; charset=utf-8")

    conn = Server.call(conn, [])

    assert conn.status == 204

    dev_key = {"A1B2C3", "PC", "SN123"}
    model = Store.get(dev_key)

    assert get_in(model, ["Device", "DeviceInfo", "Manufacturer"]) == "ACME"
    assert get_in(model, ["Device", "DeviceInfo", "SerialNumber"]) == "ABC123456"
    assert get_in(model, ["Device", "DeviceInfo", "UpTime"]) == 3600

    # Telemetry fired
    assert_receive :tr181_updated, 200

    :telemetry.detach(handler_id)
  end
end
