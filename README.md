# Caretaker

An Elixir TR-069/TR-369/TR-181 toolkit for device management.

## Features

### TR-069 (CWMP)
- TR-069 RPC structs and codecs powered by Lather (SOAP 1.1)
- Full-featured ACS server (Plug + Bandit) with spec-driven envelopes and CWMP headers
- Full-featured CPE client (Finch): Inform session loop, RPC handling (GPV, SPV, Download, Reboot, etc.)
- Diagnostics helpers (build SPV bodies): Ping, TraceRoute, NSLookup

### TR-369 (USP)
- Protocol Buffers message encoding/decoding
- USP Agent (device-side) with TR-181 data model integration
- USP Controller (server-side) with session and command queue management
- WebSocket transport (Bandit server + Mint.WebSocket client)
- MQTT transport (Tortoise311 client)
- Full message type support: Get, Set, Add, Delete, Operate, Notify, Register

### Shared Components
- Telemetry-first design `[:caretaker, ...]`
- Logger-based logging (no IO.puts or IO.inspect)
- TR-181 model primitives and store mapping
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

## USP Quick Start

### USP Agent (Device-side)

```elixir
alias Caretaker.USP.{Agent, Proto}

# Start an agent with device data
{:ok, agent} = Agent.start_link(
  endpoint_id: "os::ACME-Router-001",
  initial_data: %{
    "Device" => %{
      "DeviceInfo" => %{
        "Manufacturer" => "ACME Corp",
        "ModelName" => "Router-X100",
        "SerialNumber" => "SN-001"
      }
    }
  }
)

# Handle a Get request
get_msg = Proto.build_get(["Device.DeviceInfo.Manufacturer"])
{:ok, response} = Agent.handle_message(agent, get_msg)
```

### USP Controller (Server-side)

```elixir
alias Caretaker.USP.{Controller, Proto}

# Start a controller
{:ok, controller} = Controller.start_link(
  endpoint_id: "self::acs.example.com"
)

# Queue a command for an agent
get_cmd = Proto.build_get(["Device.DeviceInfo."])
Controller.queue_command(controller, "os::device-001", get_cmd)
```

### WebSocket Transport

```elixir
alias Caretaker.USP.Transport.WebSocket.{Paths, Server}

# Controller WebSocket path
path = Paths.controller_path("self::acs.example.com")
# => "/usp/controller/self::acs.example.com"

# Start WebSocket server (requires a running Controller)
# {:ok, server} = Server.start_link(controller: controller, port: 8080)
```

### MQTT Transport

```elixir
alias Caretaker.USP.Transport.MQTT.Topics

# Agent request topic
Topics.agent_request("os::device-001")
# => "usp/agent/os::device-001/request"

# Controller subscribes to all agent notifications
Topics.controller_notify_subscription()
# => "usp/agent/+/notify"
```

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

## Documentation

### Livebooks

Interactive documentation is available in the `livebook/` directory:

**TR-069/TR-181:**
- `01_basic_inform.livemd` - Basic Inform/InformResponse
- `02_rpc_handling.livemd` - RPC request/response handling
- `03_telemetry.livemd` - Telemetry events
- `04_tr181_mapping.livemd` - TR-181 data model
- `05_device_state.livemd` - Device state management
- `06_dynamic_behaviors.livemd` - Dynamic behavior simulation
- `07_device_profiles.livemd` - Device profile configuration
- `08_connection_request_server.livemd` - Connection request handling

**TR-369 (USP):**
- `14_usp_basics.livemd` - Protocol Buffers and message types
- `15_usp_agent.livemd` - USP Agent implementation
- `16_usp_controller.livemd` - USP Controller implementation
- `17_usp_transports.livemd` - WebSocket and MQTT transports

### Additional Docs

- `docs/telemetry.md` - Telemetry event reference
- `docs/adding_tr369.md` - TR-369 implementation details

## Logging

All logging uses Elixir Logger. Configure level in `config/config.exs`. No IO.puts or IO.inspect are used.

## Roadmap

### TR-069 Phases (Complete)
- Phase 0: Scaffolding, README, License, initial stubs, compile and test
- Phase 1: TR-069 core (Inform/InformResponse with Lather), RPC registry, fixtures & tests
- Phase 2: Minimal ACS (Plug + Bandit), parse Inform and respond; telemetry timing; integration tests
- Phase 3: Expanded RPCs and fault handling
- Phase 4: TR-181 model primitives, device simulation, and event generation
- Phase 5: CPE client, fleet management, ACS device detection
- Phase 6: Device integration tests, docs, Hex release v0.2.0

### TR-369 Phases (Complete)
- USP Phase 1: Protocol Buffers foundation, proto files, code generation
- USP Phase 2: USP message types and Record wrapper
- USP Phase 3: USP Agent (device-side) with DeviceState integration
- USP Phase 4: USP Controller (server-side) with session/queue management
- USP Phase 5: WebSocket transport (Server + Client)
- USP Phase 6: MQTT transport (via Tortoise311)
- USP Phase 7: Integration testing and Livebook documentation

## Contributing

- Read `AGENTS.md` and follow it exactly
- Always stage all files with `git add -A` before committing
- Run `mix format` and `mix test` before submitting

## License

MIT, see `LICENSE`
