# CPE Client Guide

This guide shows how to use the TR-069 CPE client included in Caretaker to initiate a session with the built-in ACS.

For a comprehensive overview of all simulated CPE features including FirmwareSimulator, DynamicBehavior, Fleet management, and ConnectionRequestServer, see [Simulated CPE Enhancement Plan](simulated_cpe.md).

## Overview

Flow:
- Build and send Inform to ACS
- Receive InformResponse
- Send empty POST to fetch next RPC (e.g., GetParameterValues)
- Respond to simple RPCs (currently GetParameterValues) and continue until 204

Defaults are conservative and spec-driven:
- SOAP 1.1 Envelope; `xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"`
- CWMP namespace mirrors peer; default `urn:dslforum-org:cwmp-1-0`
- Header includes `cwmp:ID` with `mustUnderstand="1"`

## Quick start

Start the ACS (Plug + Bandit) and the Finch HTTP pool, then run the client once.

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

# result = %{cwmp_id: ..., cwmp_ns: ..., inform_ack: true, rpc: "GetParameterValues" | nil}
```

## Stateful Device Simulation

The CPE client supports stateful TR-181 parameter storage via `DeviceState`. This allows simulated devices to maintain realistic parameter sets throughout the session.

### Using DeviceState with Device Profiles

```elixir
# Create device state with a pre-defined profile
{:ok, device_state} = Caretaker.CPE.DeviceState.start_link(
  device_id: %{oui: "A1B2C3", product_class: "FiberONT", serial_number: "SN001"}
)

# Load a profile (fiber ONU, cable modem, etc.)
:ok = Caretaker.CPE.DeviceState.load_profile(device_state, "priv/profiles/fiber_ont.json")

# Run session with stateful device
{:ok, result} = Caretaker.CPE.Client.run_session("http://localhost:4000/cwmp",
  device_state: device_state
)

# The device will now respond to GetParameterValues with actual profile data
# and SetParameterValues will update the device state
```

### Available Profiles

- `priv/profiles/fiber_ont.json` - GPON ONU with 67 TR-181 parameters
- `priv/profiles/cable_modem.json` - DOCSIS 3.1 cable modem with 53 parameters

### Manual Parameter Management

```elixir
# Get a specific parameter
version = Caretaker.CPE.DeviceState.get(device_state, "Device.DeviceInfo.SoftwareVersion")

# Set a parameter
:ok = Caretaker.CPE.DeviceState.set(device_state, "Device.DeviceInfo.SoftwareVersion", "2.0.0")

# Get all parameters under a path (returns nested map)
device_info = Caretaker.CPE.DeviceState.get_tree(device_state, "Device.DeviceInfo")

# Get parameters as TR-069 parameter list
params = Caretaker.CPE.DeviceState.get_parameters(device_state, "Device.ManagementServer.")
# => [%{name: "Device.ManagementServer.URL", value: "...", type: "xsd:string"}, ...]
```

### RPC Behavior with DeviceState

When `device_state` is provided to `run_session/2`:

**GetParameterValues:**
- Parses incoming RPC to extract requested parameter names
- Queries device state for matching parameters
- Returns complete parameter list with correct types from profile
- Supports wildcard queries (e.g., `Device.DeviceInfo.` returns all children)

**SetParameterValues:**
- Parses incoming RPC to extract parameters, values, and types
- Updates device state via `update_parameters/2`
- Emits telemetry event `[:caretaker, :cpe_client, :params, :updated]`
- Returns status 0 (success)

**Fallback Behavior:**
If no `device_state` is provided, the client uses hardcoded values (Manufacturer and SerialNumber from device_id).

## Telemetry

Events emitted by the client:
- `[:caretaker, :cpe_client, :session, :start|:stop]` — session lifecycle
- `[:caretaker, :cpe_client, :http, :request, :start|:stop]` — HTTP requests
- `[:caretaker, :cpe_client, :retry]` — retry with backoff
- `[:caretaker, :cpe_client, :rpc, :received]` — RPC received from ACS
- `[:caretaker, :cpe_client, :rpc, :responded]` — RPC responded by client (includes `param_count` for GetParameterValues)
- `[:caretaker, :cpe_client, :rpc, :unsupported]` — RPC not handled by client
- `[:caretaker, :cpe_client, :params, :updated]` — SetParameterValues updated device state (includes `count`)
- `[:caretaker, :cpe_client, :error]` — errors

Attach handlers in tests or your app to observe metrics and state.

## Timeouts and retries

Options:
- `timeout` (default: 5_000 ms)
- `max_retries` (default: 3)
- `backoff_base` (default: 200 ms), exponential with full jitter

## Notes

- Use Logger for all logging; never IO.puts or IO.inspect.
- The client currently implements a minimal responder for GetParameterValues and SetParameterValuesResponse; extend as needed.
- You can extend the responder with additional TR-069 RPCs following the same pattern.
