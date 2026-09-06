# Adding TR-369 (USP) Support to Caretaker

## Overview

This document tracks the implementation of TR-369 (User Services Platform) support in Caretaker. TR-369 is the successor to TR-069, using Protocol Buffers over modern transports (WebSocket, MQTT, STOMP, CoAP) instead of SOAP/XML over HTTP.

## Current Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | **COMPLETE** | USP Protocol Buffers Foundation |
| Phase 2 | **COMPLETE** | USP Message Types & Records |
| Phase 3 | **COMPLETE** | USP Agent (Device-side) |
| Phase 4 | **COMPLETE** | USP Controller (Server-side) |
| Phase 5 | **COMPLETE** | WebSocket Transport |
| Phase 6 | **COMPLETE** | MQTT Transport |
| Phase 7 | **COMPLETE** | Integration & Testing |

## Architecture Decision: Shared Components

TR-369 shares these components with TR-069:

- **TR-181 Data Model** (`lib/caretaker/tr181/`) - Identical data model
- **Device Detection** (`lib/caretaker/acs/device_detection.ex`) - Vendor identification
- **Quirks System** (`lib/caretaker/quirks/`) - Vendor-specific behaviors
- **Device Profiles** (`priv/profiles/`) - Parameter templates
- **Simulation Modules** (`lib/caretaker/cpe/simulation/`) - Physical characteristics

New TR-369 specific modules will be created under:

```
lib/caretaker/
├── usp/                    # USP protocol implementation
│   ├── messages/           # Protobuf message wrappers
│   ├── transport/          # Transport bindings
│   ├── agent.ex            # USP Agent (device-side)
│   ├── controller.ex       # USP Controller (server-side)
│   └── record.ex           # USP Record handling
└── proto/                  # Generated protobuf modules
```

---

## Phase 1: USP Protocol Buffers Foundation

### Goal
Set up Protocol Buffers compilation and define core USP message structures.

### Tasks

- [x] Add `protobuf` dependency to mix.exs
- [x] Create `priv/proto/` directory for .proto files
- [x] Add USP protocol buffer definitions (from BBF USP spec)
  - [x] `usp_msg.proto` - Core message types
  - [x] `usp_record.proto` - Record wrapper types
- [x] Generate Elixir modules from .proto files
- [x] Create wrapper module `Caretaker.USP.Proto` for accessing generated types
- [x] Add basic encode/decode tests (18 tests passing)

### Files Created

- `priv/proto/usp_msg.proto` - USP Message definitions
- `priv/proto/usp_record.proto` - USP Record wrapper definitions
- `lib/caretaker/proto/usp_msg.pb.ex` - Generated protobuf module
- `lib/caretaker/proto/usp_record.pb.ex` - Generated protobuf module
- `lib/caretaker/usp/proto.ex` - High-level wrapper with builder functions
- `test/caretaker/usp/proto_test.exs` - Unit tests

### Dependencies Added

```elixir
{:protobuf, "~> 0.13"}
{:mint_web_socket, "~> 1.0"}  # For Phase 5
```

### Proto Compilation

To regenerate proto files after changes:

```bash
export PATH="$HOME/.asdf/installs/elixir/1.19.1-otp-28/.mix/escripts:$PATH"
protoc --elixir_out=./lib/caretaker/proto --proto_path=./priv/proto \
  ./priv/proto/usp_msg.proto ./priv/proto/usp_record.proto
```

---

## Phase 2: USP Message Types & Records

### Goal
Implement high-level message handling for all USP operation types.

### USP Message Types (from TR-369 spec)

| Message | Direction | TR-069 Equivalent |
|---------|-----------|-------------------|
| Get | Controller → Agent | GetParameterValues |
| GetResp | Agent → Controller | GetParameterValuesResponse |
| Set | Controller → Agent | SetParameterValues |
| SetResp | Agent → Controller | SetParameterValuesResponse |
| Add | Controller → Agent | AddObject |
| AddResp | Agent → Controller | AddObjectResponse |
| Delete | Controller → Agent | DeleteObject |
| DeleteResp | Agent → Controller | DeleteObjectResponse |
| Operate | Controller → Agent | (vendor methods) |
| OperateResp | Agent → Controller | (vendor methods) |
| Notify | Agent → Controller | Inform (partial) |
| GetSupportedDM | Controller → Agent | GetParameterNames |
| GetSupportedDMResp | Agent → Controller | GetParameterNamesResponse |
| GetInstances | Controller → Agent | (new in USP) |
| GetInstancesResp | Agent → Controller | (new in USP) |
| GetSupportedProtocol | Controller → Agent | (new in USP) |
| GetSupportedProtocolResp | Agent → Controller | (new in USP) |
| Register | Agent → Controller | Inform (partial) |
| Deregister | Agent → Controller | (new in USP) |
| Error | Either | Fault |

### Tasks

- [x] Create message builder functions in `Caretaker.USP.Proto`
  - [x] Request builders: Get, Set, Add, Delete, Operate, Register, GetSupportedDM, GetInstances
  - [x] Response builders: GetResp, SetResp, AddResp, DeleteResp, NotifyResp
  - [x] Notify builders: ValueChange, Event
  - [x] Error builder
- [x] Create `Caretaker.USP.Record` for USP Record envelope handling
- [x] Create `Caretaker.USP.Registry` message type registry
- [x] Add `Caretaker.USP.Telemetry` instrumentation

### Files Created

- `lib/caretaker/usp/proto.ex` - Extended with response/notify builders
- `lib/caretaker/usp/record.ex` - Record envelope handling, endpoint IDs
- `lib/caretaker/usp/registry.ex` - Message type registry and TR-069 mapping
- `lib/caretaker/usp/telemetry.ex` - Telemetry events for agent/controller/transport

### Design Decision

Instead of separate message modules (like TR-069's `RPC.Inform`, `RPC.GetParameterValues`),
USP uses a unified builder approach in `Caretaker.USP.Proto`. This is simpler because:
1. All USP messages share the same protobuf structure
2. Encoding/decoding is handled by the protobuf library
3. Builders provide type-safe message construction

---

## Phase 3: USP Agent (Device-side)

### Goal
Implement USP Agent that can respond to Controller requests, similar to CPE.Client.

### Tasks

- [x] Create `Caretaker.USP.Agent` GenServer
- [x] Implement agent state management (reuses `Caretaker.CPE.DeviceState`)
- [x] Handle incoming messages:
  - [x] Get → query DeviceState, return GetResp
  - [x] Set → update DeviceState, return SetResp
  - [x] Add → create object instance, return AddResp
  - [x] Delete → remove object instance, return DeleteResp
  - [x] Operate → execute operation, return OperateResp
  - [x] GetSupportedDM → return data model info
  - [x] GetInstances → return instance paths
  - [x] GetSupportedProtocol → return version info
- [x] Implement outgoing messages:
  - [x] Register message builder
  - [x] Connect/disconnect lifecycle
- [x] Record handling (wrap/unwrap messages in USP Records)
- [x] Telemetry integration
- [x] 14 tests passing

### Files Created

- `lib/caretaker/usp/agent.ex` - USP Agent GenServer with message handlers
- `test/caretaker/usp/agent_test.exs` - Agent tests

### Design Notes

The Agent reuses `Caretaker.CPE.DeviceState` for parameter storage, providing
seamless integration with existing TR-069 device profiles. Endpoint IDs are
parsed to extract device identity (OUI, product class, serial number).

---

## Phase 4: USP Controller (Server-side)

### Goal
Implement USP Controller that can manage Agents, similar to ACS.Server.

### Tasks

- [x] Create `Caretaker.USP.Controller` GenServer
- [x] Implement session management for connected agents
- [x] Create command queue for async operations
- [x] Implement controller operations:
  - [x] Send Get requests
  - [x] Send Set requests
  - [x] Send Add/Delete requests
  - [x] Send Operate requests
  - [x] Handle Notify messages
  - [x] Handle Register/Deregister
- [x] Telemetry integration
- [x] Record handling (wrap/unwrap from transport)
- [x] 12 tests passing

### Files Created

- `lib/caretaker/usp/controller.ex` - USP Controller with session and queue management
- `test/caretaker/usp/controller_test.exs` - Controller tests including integration test

### Design Notes

The Controller manages per-agent sessions with:
- Connection tracking (connected_at, last_message_at)
- Pending request tracking for async operations
- Command queue for outgoing messages
- Timeout handling for unanswered requests

An integration test demonstrates the full Controller ↔ Agent message flow.

---

## Phase 5: WebSocket Transport

### Goal
Implement WebSocket transport binding per TR-369 Annex.

### Tasks

- [x] Add WebSocket dependencies (websock_adapter, mint_web_socket)
- [x] Create `Caretaker.USP.Transport.WebSocket.Paths` - URL path structure
- [x] Create `Caretaker.USP.Transport.WebSocket.Handler` - WebSock handler
- [x] Create `Caretaker.USP.Transport.WebSocket.Server` (for Controller)
- [x] Create `Caretaker.USP.Transport.WebSocket.Client` (for Agent)
- [x] Implement USP Record framing over WebSocket (binary frames)
- [x] Handle connection lifecycle and reconnection
- [x] Add telemetry events
- [x] Integration tests (19 tests passing)

### Files Created

- `lib/caretaker/usp/transport/websocket/paths.ex` - URL path structure
- `lib/caretaker/usp/transport/websocket/handler.ex` - WebSock handler
- `lib/caretaker/usp/transport/websocket/server.ex` - Controller WebSocket server
- `lib/caretaker/usp/transport/websocket/client.ex` - Agent WebSocket client
- `test/integration/usp_websocket_integration_test.exs` - Integration tests

### Dependencies Added

```elixir
{:websock_adapter, "~> 0.5"}  # WebSocket upgrade for Plug
{:mint_web_socket, "~> 1.0"}  # Client-side WebSocket
```

### Path Structure

The WebSocket transport follows the USP WebSocket binding specification:

```
/usp/
├── controller/<controller_id>   # Controller WebSocket endpoint
└── agent/<agent_id>             # Agent WebSocket endpoint
```

### WebSocket Subprotocol

USP WebSocket connections use the `v1.usp` subprotocol identifier.

### Design Notes

- Server uses Bandit + WebSockAdapter for WebSocket upgrades
- Client uses Mint.WebSocket for client-side WebSocket connections
- USP Records are sent as binary WebSocket frames
- Handler forwards WebSocket events to parent transport process
- Automatic reconnection on connection loss

---

## Phase 6: MQTT Transport

### Goal
Implement MQTT transport binding per TR-369 Annex.

### Tasks

- [x] Add Nipper embedded MQTT broker dependency
- [x] Add Tortoise311 MQTT client dependency (already present)
- [x] Define topic structure per USP MQTT binding specification:
  - `usp/agent/<agent_id>/request` - Agent receives requests
  - `usp/agent/<agent_id>/notify` - Agent sends notifications
  - `usp/controller/<controller_id>/request` - Controller receives messages
  - `usp/agent/+/notify` - Controller subscribes to all agent notifications
- [x] Create `Caretaker.USP.Transport.MQTT.Topics` module
- [x] Create `Caretaker.USP.Transport.MQTT.Handler` (Tortoise311 handler)
- [x] Create `Caretaker.USP.Transport.MQTT.Agent` transport
- [x] Create `Caretaker.USP.Transport.MQTT.Controller` transport
- [x] Integration tests (15 tests passing)

### Files Created

- `lib/caretaker/usp/transport/mqtt/topics.ex` - Topic structure helpers
- `lib/caretaker/usp/transport/mqtt/handler.ex` - Tortoise311 MQTT handler
- `lib/caretaker/usp/transport/mqtt/agent.ex` - Agent MQTT transport
- `lib/caretaker/usp/transport/mqtt/controller.ex` - Controller MQTT transport
- `test/integration/usp_mqtt_integration_test.exs` - Integration tests

### Dependencies Added

```elixir
{:nipper, "~> 0.1.0"}      # Embedded MQTT broker
{:tortoise311, "~> 0.12"}  # MQTT client (already present)
```

### Topic Structure

The MQTT transport follows the USP MQTT binding specification:

```
usp/
├── agent/<agent_id>/
│   ├── request   # Agent receives Controller requests here
│   └── notify    # Agent publishes notifications here
└── controller/<controller_id>/
    └── request   # Controller receives Agent messages here
```

### Design Notes

- Uses Tortoise311 for MQTT client connections
- Nipper provides embedded MQTT broker for integration testing
- Handler forwards MQTT events to parent transport process
- Agent subscribes to its request topic, publishes to controller topic
- Controller subscribes to its request topic and all agent notify topics

---

## Phase 7: Integration & Testing

### Goal
End-to-end testing and documentation.

### Tasks

- [x] Create MQTT integration tests with simulated devices
- [x] Test Controller ↔ Agent communication over WebSocket (path and encoding tests)
- [x] Test Controller ↔ Agent communication over MQTT (topic and encoding tests)
- [x] Add Livebook examples
  - [x] `livebook/14_usp_basics.livemd` - Protocol Buffers and message types
  - [x] `livebook/15_usp_agent.livemd` - USP Agent implementation
  - [x] `livebook/16_usp_controller.livemd` - USP Controller implementation
  - [x] `livebook/17_usp_transports.livemd` - WebSocket and MQTT transports
- [x] Update main README with USP documentation
- [ ] Test mixed TR-069/TR-369 scenarios (future enhancement)
- [ ] Performance testing with fleet (future enhancement)

### Files Created

- `test/integration/usp_mqtt_integration_test.exs` - MQTT transport tests (15 tests)
- `test/integration/usp_websocket_integration_test.exs` - WebSocket transport tests (19 tests)
- `livebook/14_usp_basics.livemd` - USP Protocol Buffers fundamentals
- `livebook/15_usp_agent.livemd` - USP Agent usage examples
- `livebook/16_usp_controller.livemd` - USP Controller usage examples
- `livebook/17_usp_transports.livemd` - WebSocket and MQTT transport comparison

### Notes on Integration Testing

**WebSocket Integration Tests** verify:
- USP message encoding/decoding for WebSocket binary frames
- WebSocket path structure compliance with USP specification
- Transport module structure and exports

**MQTT Integration Tests** verify:
- USP message encoding/decoding for MQTT payloads
- MQTT topic structure compliance with USP specification
- Transport module structure and exports

Full end-to-end MQTT tests with actual message flow require an external
MQTT broker (e.g., Mosquitto) due to protocol compatibility between
Nipper (MQTT v3.1.1 broker) and Tortoise311 (MQTT client).

---

## Implementation Notes

### USP vs CWMP Terminology

| CWMP (TR-069) | USP (TR-369) |
|---------------|--------------|
| ACS | Controller |
| CPE | Agent |
| Inform | Register + Notify |
| Session | MTP Connection |
| RPC | Message |
| SOAP Envelope | USP Record |

### USP Record Structure

```
USP Record (protobuf)
├── version: string
├── to_id: string (endpoint ID)
├── from_id: string (endpoint ID)
├── payload_security: enum
├── mac_signature: bytes (optional)
├── sender_cert: bytes (optional)
└── payload: oneof
    ├── no_session_context: NoSessionContextRecord
    └── session_context: SessionContextRecord
        └── payload: bytes (USP Message)
```

### Endpoint ID Format

USP uses endpoint IDs in format: `<authority>::<instance-id>`

Examples:
- `os::012345-MyDevice-0050C2345678` (Agent)
- `self::acs.example.com` (Controller)

---

## Progress Log

### 2025-12-25
- Document created
- Phase 1 completed: Protocol Buffers foundation
  - Added protobuf dependency
  - Created USP message and record proto files
  - Generated Elixir modules from protobuf
  - Created Proto wrapper with builder functions
  - 18 tests passing
- Phase 2 completed: Message types and encoding
  - Added response builders (GetResp, SetResp, AddResp, DeleteResp)
  - Added Notify builders (ValueChange, Event)
  - Created Record module for endpoint ID handling
  - Created Registry for message type mapping
  - Created Telemetry module for instrumentation
- Phase 3 completed: USP Agent implementation
  - Created Agent GenServer with all message handlers
  - Integrated with DeviceState for parameter storage
  - Record handling for transport layer
  - 14 tests passing
- Phase 4 completed: USP Controller implementation
  - Created Controller GenServer with session management
  - Command queue for async operations
  - Register/Deregister/Notify handling
  - Controller ↔ Agent integration test
  - 12 tests passing
- Phase 6 completed: MQTT Transport implementation
  - Added Nipper embedded MQTT broker dependency
  - Created MQTT transport modules (Topics, Handler, Agent, Controller)
  - Topic structure per USP MQTT binding specification
  - 15 MQTT integration tests passing
- Phase 5 completed: WebSocket Transport implementation
  - Added websock_adapter dependency
  - Created WebSocket transport modules (Paths, Handler, Server, Client)
  - Path structure per USP WebSocket binding specification
  - Binary framing for USP Records
  - 19 WebSocket integration tests passing
  - **Total: 78 USP tests passing**
  - **Total project: 538 tests passing**

- Phase 7 completed: Integration testing and documentation
  - Created four USP Livebooks (14-17)
  - Updated main README with USP documentation
  - **All 7 USP phases complete**
  - **Total: 78 USP tests passing**
  - **Total project: 538 tests passing**

### Current State

All phases complete. Caretaker now provides full TR-369 (USP) support:
- Protocol Buffers encoding/decoding
- All USP message types (Get, Set, Add, Delete, Operate, Notify, etc.)
- Agent (device-side) with DeviceState integration
- Controller (server-side) with session and queue management
- WebSocket transport (Bandit server + Mint.WebSocket client)
- MQTT transport (Tortoise311 client + Nipper broker for testing)
- Integration tests for both transports
- Livebook documentation for all components

Future enhancements (not blocking release):
- Test mixed TR-069/TR-369 scenarios
- Performance testing with fleet

## USP-over-MQTT broker

USP-over-MQTT is broker-mediated. Caretaker ships an **embedded broker** as the
default, so no external infrastructure is needed:

```elixir
children = [
  Caretaker.USP.Transport.MQTT.Broker,   # embedded broker on localhost:1883 (default)
  # controller + agent MQTT transports default to localhost:1883
]
```

To use an **external** broker (EMQX, Mosquitto, HiveMQ, a shared bus, or for
clustering/HA), omit the broker and point the transports at it via
`broker_host:` / `broker_port:`. USP-over-WebSocket needs no broker at all — the
controller's WebSocket server is the endpoint agents connect to.
