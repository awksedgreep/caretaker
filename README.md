# Caretaker

An Elixir TR-069/TR-181 toolkit.

## Features

- TR-069 RPC structs and codecs powered by Lather (SOAP 1.1)
- Full-featured ACS server (Plug + Bandit) with spec-driven envelopes and CWMP headers
- Telemetry-first design `[:caretaker, ...]`
- Logger-based logging (no IO.puts or IO.inspect)
- TR-181 model primitives and store mapping
- Full-featured CPE client (Finch): Inform session loop, RPC handling (GPV, SPV, Download, Reboot, etc.)
- Diagnostics helpers (build SPV bodies): Ping, TraceRoute, NSLookup
- MQTT integration: PubSub for internal events, MQTT.Bridge for Inform broadcasting via tortoise311
- Device simulation: DeviceState for TR-181 parameter storage, device profiles (fiber ONT, cable modem)
- Fleet management: Load testing with 100+ simulated devices, staggered spawning, aggregate metrics
- Firmware simulation: FirmwareSimulator for upgrade lifecycle testing (download, apply, reboot)
- Device quirks: Vendor-specific behavior handling (e.g., MikroTik RouterOS)
- Connection request server: HTTP endpoint for ACS-initiated connections

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:caretaker, "~> 0.2"}
  ]
end
```

Caretaker depends on `:lather` (pulled from Hex).

## Quick start

Start a minimal ACS in a supervision tree:

```elixir
children = [
  {Bandit, plug: Caretaker.ACS.Server, port: 4000}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

Then POST CWMP SOAP to `http://localhost:4000/cwmp`.

## Telemetry

Caretaker emits server/client/RPC telemetry. See `docs/telemetry.md` for the full event reference.

## Supported RPCs

Implemented encoders/decoders (spec-driven, partial list):
- Core: Inform, InformResponse, Fault (cwmp and SOAP)
- Parameters: GetParameterNames(+Response), GetParameterValues(+Response), SetParameterValues(+Response)
- Objects: AddObject(+Response), DeleteObject(+Response)
- Firmware/Transfers: Download(+Response), Upload(+Response), TransferComplete(+Response), AutonomousTransferComplete(+Response), ScheduleDownload(+Response), GetQueuedTransfers(+Response), CancelTransfer(+Response), RequestDownload(+Response)
- Attributes/Scheduling: GetRPCMethods(+Response), GetParameterAttributes(+Response), SetParameterAttributes(+Response), ScheduleInform(+Response)

## CPE client usage

See `docs/phase-5-cpe-client.md` for a guide and telemetry events.

A minimal client is included to initiate a session and handle basic RPCs.

```elixir
children = [
  {Bandit, plug: Caretaker.ACS.Server, port: 4000},
  {Finch, name: Caretaker.Finch}
]
Supervisor.start_link(children, strategy: :one_for_one)

{:ok, result} =
  Caretaker.CPE.Client.run_session("http://localhost:4000/cwmp",
    device_id: %{
      manufacturer: "Acme",
      oui: "A1B2C3",
      product_class: "Router",
      serial_number: "XYZ123"
    }
  )

# The client will:
# - Send Inform and await InformResponse
# - POST empty to fetch next RPC
# - Respond minimally to GetParameterValues (using device_id) and SetParameterValues (status 0)
```

## Logging

All logging uses Elixir Logger. Configure level in `config/config.exs`. No IO.puts or IO.inspect are used.

## Roadmap

- Phase 0: Scaffolding, README, License, initial stubs, compile and test (done)
- Phase 1: TR-069 core (Inform/InformResponse with Lather), RPC registry, fixtures & tests (done)
- Phase 2: Minimal ACS (Plug + Bandit), parse Inform and respond; telemetry timing; integration tests (done)
- Phase 3: Expanded RPCs and fault handling (done)
- Phase 4: TR-181 model primitives, device simulation, and event generation (done)
- Phase 5: CPE client, fleet management, ACS device detection (done)
- Phase 6: Device integration tests, docs, Hex release v0.2.0 (done)

## Contributing

- Read `AGENTS.md` and follow it exactly
- Always stage all files with `git add -A` before committing
- Run `mix format` and `mix test` before submitting

## License

MIT, see `LICENSE`
