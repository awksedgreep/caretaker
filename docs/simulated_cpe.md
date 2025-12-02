# Simulated CPE Enhancement Plan

This document outlines a multi-phase plan to enhance the CPE client simulator for comprehensive ACS and TR-181 testing.

## Current State (Phase 0)

**Implemented:**
- ✅ Basic HTTP client using Finch
- ✅ Inform/InformResponse flow
- ✅ Empty POST loop to fetch queued RPCs
- ✅ GetParameterValues response (2 hardcoded parameters)
- ✅ SetParameterValues response (always succeeds with status 0)
- ✅ HTTP retry logic with exponential backoff
- ✅ Telemetry instrumentation
- ✅ Load testing capability (100+ concurrent clients)
- ✅ Memory footprint: ~388 KB/session

**Limitations:**
- ❌ No stateful TR-181 data model per device
- ❌ No parameter persistence across sessions
- ❌ Limited RPC support (only 2 RPCs with minimal logic)
- ❌ No firmware upgrade simulation
- ❌ No realistic device behaviors
- ❌ No connection request server
- ❌ No advanced telemetry/metrics aggregation

**Use Cases Supported:**
- Basic ACS connection testing
- Load testing (multiple concurrent devices)
- Simple RPC flow validation

---

## Phase 1: Stateful Device Model ✅ COMPLETE

**Goal:** Each simulated device maintains its own TR-181 parameter store with configurable initial state.

**Status:** ✅ All deliverables complete. Full test suite passing (111 tests).

### Deliverables

#### 1.1 Device State Module ✅ COMPLETE
```elixir
Caretaker.CPE.DeviceState
```

**Features:** ✅ All implemented
- ✅ Per-device TR-181 parameter storage (Agent-backed)
- ✅ Initialize from JSON/map profiles
- ✅ Get/set parameters with validation
- ✅ Support for nested TR-181 paths (e.g., `Device.IP.Interface.1.IPv4Address.1.IPAddress`)
- ✅ Type awareness (string, int, boolean, dateTime, etc.)
- ✅ Load profiles from JSON files
- ✅ Flatten/unflatten parameters for TR-069 RPCs
- ✅ Unit tests: 13/13 passing

**Example:**
```elixir
{:ok, state} = DeviceState.start_link(
  device_id: %{oui: "A1B2C3", product_class: "CPE", serial_number: "123"},
  params: %{}
)

DeviceState.load_profile(state, "priv/profiles/fiber_ont.json")

DeviceState.get(state, "Device.DeviceInfo.SoftwareVersion")
# => "1.0.0"

DeviceState.set(state, "Device.DeviceInfo.SoftwareVersion", "1.1.0")
```

#### 1.2 Enhanced GetParameterValues Handler ✅ COMPLETE
- ✅ Query device state instead of hardcoded values
- ✅ Parse incoming GetParameterValues RPC XML to extract parameter names
- ✅ Support wildcard queries (e.g., `Device.DeviceInfo.`)
- ✅ Return full parameter lists with correct types
- ✅ Fallback to hardcoded values if device_state not provided
- ✅ Integration test: Returns 15+ parameters from profile

#### 1.3 Enhanced SetParameterValues Handler ✅ COMPLETE
- ✅ Parse incoming SetParameterValues RPC XML
- ✅ Extract parameter names, values, and types
- ✅ Update device state via DeviceState.update_parameters/2
- ✅ Return appropriate status codes
- ✅ Telemetry event for parameter updates

#### 1.4 Device Profiles ✅ COMPLETE
Pre-defined JSON profiles for common device types:
- ✅ `priv/profiles/fiber_ont.json` - GPON ONU with typical parameters (67 parameters)
- ✅ `priv/profiles/cable_modem.json` - DOCSIS cable modem (53 parameters)
- ⏳ `profiles/router.json` - Generic home gateway (future Phase 2)
- ⏳ `profiles/mikrotik.json` - Mikrotik RouterOS device (future Phase 2)

**Success Criteria:**
- ✅ Devices respond with realistic, configurable parameter sets
- ✅ Parameters persist for the duration of the session
- ✅ SetParameterValues updates are reflected in subsequent GetParameterValues
- ✅ All tests pass (111 tests, 0 failures)
- ✅ Integration test validates stateful session behavior

**Actual Effort:** 1 day (estimated 2-3 days)

**Files Created/Modified:**
- `lib/caretaker/cpe/device_state.ex` (NEW: 241 lines)
- `lib/caretaker/cpe/client.ex` (MODIFIED: Added device_state integration + XML parsing)
- `priv/profiles/fiber_ont.json` (NEW: 67 parameters)
- `priv/profiles/cable_modem.json` (NEW: 53 parameters)
- `test/cpe_device_state_test.exs` (NEW: 13 tests)
- `test/cpe_stateful_session_test.exs` (NEW: 2 integration tests)

---

## Phase 2: Full RPC Support

**Goal:** Implement handlers for all commonly-used TR-069 RPCs with realistic behavior.

### Deliverables

#### 2.1 Parameter RPCs
- ✅ GetParameterValues (enhanced in Phase 1)
- ✅ SetParameterValues (enhanced in Phase 1)
- 🆕 GetParameterNames
- 🆕 GetParameterAttributes
- 🆕 SetParameterAttributes

#### 2.2 Object Management RPCs
- 🆕 AddObject (create numbered instances)
- 🆕 DeleteObject (remove instances)

#### 2.3 Diagnostic RPCs
- 🆕 GetRPCMethods (return list of supported RPCs)

#### 2.4 Response Behavior
- Parse incoming RPC XML to extract parameters
- Generate appropriate responses based on device state
- Handle malformed requests gracefully

**Example Enhancements:**
```elixir
# GetParameterNames with NextLevel support
respond_to_rpc("GetParameterNames", %{path: "Device.IP.", next_level: true})
# => Returns only Device.IP.Interface., Device.IP.Diagnostics., etc.

# AddObject creates new instance
respond_to_rpc("AddObject", %{path: "Device.IP.Interface."})
# => Creates Device.IP.Interface.3., returns instance number and status
```

**Success Criteria:**
- Support 10+ TR-069 RPCs with realistic behavior
- Devices maintain object instance state
- Proper error handling and fault codes

**Estimated Effort:** 3-4 days

---

## Phase 3: Firmware Upgrade Simulation

**Goal:** Complete end-to-end firmware upgrade flow simulation.

### Deliverables

#### 3.1 Firmware Simulator Module
```elixir
Caretaker.CPE.FirmwareSimulator
```

**Features:**
- State machine: idle → downloading → downloaded → rebooting → upgraded
- Configurable download duration (simulate slow downloads)
- Configurable reboot delay
- Version tracking (current → target)

#### 3.2 Download RPC Handler
- Parse Download RPC (URL, file_type, command_key, etc.)
- Respond with DownloadResponse (status 1 = will download)
- Simulate download progress in background
- Support for username/password (ignored in simulation)
- Support for DelaySeconds

#### 3.3 TransferComplete Flow
- After simulated download completes, send TransferComplete
- Include command_key correlation
- Report fault codes for failed downloads (optional)
- Update device state with new firmware version

#### 3.4 Reboot Simulation
- Handle Reboot RPC
- Respond with RebootResponse
- Close current session
- Wait for reboot_delay
- Initiate new session with "1 BOOT" event
- Report updated SoftwareVersion in parameters

#### 3.5 Telemetry Events
```elixir
[:caretaker, :firmware, :download, :start]
[:caretaker, :firmware, :download, :progress]  # optional
[:caretaker, :firmware, :download, :complete]
[:caretaker, :firmware, :transfer_complete, :sent]
[:caretaker, :firmware, :reboot, :start]
[:caretaker, :firmware, :reboot, :complete]
[:caretaker, :firmware, :upgraded]
```

**Example Usage:**
```elixir
# Start device with firmware simulation
run_session(url,
  device_id: %{...},
  firmware: %{
    current_version: "1.0.0",
    download_duration: 10_000,  # 10 seconds
    reboot_delay: 5_000         # 5 seconds
  }
)

# ACS sends Download RPC → device accepts
# ... 10 seconds pass ...
# Device sends TransferComplete
# ACS sends Reboot RPC → device accepts
# ... 5 seconds pass ...
# Device reconnects with "1 BOOT" and version "2.0.0"
```

**Success Criteria:**
- Complete firmware upgrade flow works end-to-end
- Proper correlation using command_key
- Device state reflects version changes
- Telemetry tracks all upgrade stages

**Estimated Effort:** 3-4 days

---

## Phase 4: Dynamic Behaviors

**Goal:** Simulate realistic device behaviors beyond simple request/response.

### Deliverables

#### 4.1 Periodic Inform
- Devices send periodic Inform messages (configurable interval)
- Include "2 PERIODIC" event code
- Jitter support to avoid thundering herd

#### 4.2 Dynamic Parameters
- UpTime increments automatically
- Simulated interface statistics (bytes sent/received)
- Connection status changes
- Optional: realistic value drift (temperature, signal strength)

#### 4.3 Event Generation
- "4 VALUE CHANGE" when parameters modified
- "6 CONNECTION REQUEST" (if connection request server implemented)
- "3 SCHEDULED" for scheduled informs
- Custom event triggers

#### 4.4 Behavior Configuration
```elixir
run_session(url,
  device_id: %{...},
  behaviors: [
    periodic_inform: [interval: 300_000, jitter: 30_000],
    dynamic_params: ["Device.DeviceInfo.UpTime"],
    value_change_events: true
  ]
)
```

**Success Criteria:**
- Devices exhibit realistic behavior patterns
- Periodic informs work correctly
- Dynamic parameters update over time
- Events trigger properly

**Estimated Effort:** 2-3 days

---

## Phase 5: Fleet Management

**Goal:** Simplify management of multiple simulated devices.

### Deliverables

#### 5.1 Fleet Manager Module
```elixir
Caretaker.CPE.Fleet
```

**Features:**
- Spawn N devices with different profiles
- Staggered connection timing
- Fleet-wide operations (stop all, trigger inform, etc.)
- Per-device and aggregate metrics

#### 5.2 Device Profiles
- Load multiple device types from configuration
- Mix of vendors, models, firmware versions
- Realistic serial number generation

#### 5.3 Fleet Control
```elixir
# Start 100 devices
{:ok, fleet} = Fleet.start(
  acs_url: "http://localhost:4000/cwmp",
  count: 100,
  profiles: [
    {60, "fiber_ont"},
    {40, "cable_modem"}
  ],
  connection_delay: 100..500  # ms between connections
)

# Control operations
Fleet.stop_device(fleet, "SN-050")
Fleet.trigger_inform(fleet, "SN-023", ["4 VALUE CHANGE"])
Fleet.update_param(fleet, "SN-010", "Device.DeviceInfo.Description", "Test Device")

# Metrics
Fleet.stats(fleet)
# => %{total: 100, connected: 98, sessions: 450, avg_latency: 45ms}
```

**Success Criteria:**
- Spawn 100+ devices easily
- Fleet-wide operations work
- Aggregate metrics available
- Memory usage remains reasonable (< 50 MB for 100 devices)

**Estimated Effort:** 2-3 days

---

## Phase 6: Advanced Testing Features

**Goal:** Tools for sophisticated ACS testing scenarios.

### Deliverables

#### 6.1 Scenario Engine
Pre-defined test scenarios:
```elixir
Caretaker.CPE.Scenario.run(:firmware_upgrade,
  devices: 10,
  steps: [
    {:connect, delay: 100},
    {:wait_for_rpc, "Download", timeout: 5_000},
    {:simulate_download, duration: 10_000},
    {:send, "TransferComplete"},
    {:wait_for_rpc, "Reboot"},
    {:simulate_reboot, delay: 5_000},
    {:reconnect, event: "1 BOOT"},
    {:assert_param, "Device.DeviceInfo.SoftwareVersion", "2.0.0"}
  ]
)
```

Common scenarios:
- `firmware_upgrade` - Complete firmware update flow
- `param_sync` - Parameter read/write operations
- `mass_inform` - Simultaneous informs from many devices
- `connection_recovery` - Reconnection after failure
- `diagnostic_flow` - Run ping/traceroute diagnostics

#### 6.2 Failure Injection
```elixir
Device.inject_failures(
  disconnect: %{probability: 0.05, timing: :during_rpc},
  corrupt_xml: %{probability: 0.01},
  timeout: %{probability: 0.03, delay: 30_000},
  fault_response: %{code: 9002, probability: 0.02}
)
```

#### 6.3 Network Simulation
- Latency injection (min/max range)
- Packet loss simulation
- Bandwidth throttling

#### 6.4 Performance Profiling
```elixir
{:ok, profile} = LoadTest.run(
  clients: 500,
  duration: :timer.minutes(10),
  ramp_up: :timer.seconds(30),
  profile: :realistic,
  
  collect: [:response_times, :error_rates, :throughput]
)

# Generate HTML report
LoadTest.report(profile, output: "load_test_report.html")
```

**Success Criteria:**
- Scenario engine executes complex flows
- Failure injection works reliably
- Network conditions can be simulated
- Performance reports are actionable

**Estimated Effort:** 4-5 days

---

## Phase 7: Enhanced Telemetry & Observability

**Goal:** Rich metrics collection and analysis for ACS performance testing.

### Deliverables

#### 7.1 Metrics Aggregation
```elixir
Caretaker.CPE.Metrics
```

**Features:**
- Per-device metrics (session count, RPC counts, latencies)
- Aggregate metrics (success rate, p50/p95/p99 latencies)
- Time-series data collection
- Export to Prometheus, InfluxDB, or JSON

#### 7.2 Enhanced Telemetry Events
```elixir
# Device lifecycle
[:cpe_device, :started]
[:cpe_device, :stopped]
[:cpe_device, :session, :start]
[:cpe_device, :session, :end]

# Parameter operations
[:cpe_device, :param, :read, :start|:stop]
[:cpe_device, :param, :written]

# RPC timing
[:cpe_device, :rpc, :received]
[:cpe_device, :rpc, :processing]
[:cpe_device, :rpc, :responded]

# Transfers
[:cpe_device, :download, :progress]
[:cpe_device, :upload, :progress]
```

#### 7.3 Real-time Dashboards
- Integration with Grafana/Prometheus
- Live metrics during load tests
- Alert conditions (error rate, latency thresholds)

#### 7.4 Test Reports
```elixir
Report.generate(test_run,
  format: :html,
  include: [
    :summary,           # Total sessions, success rate, duration
    :latency_histogram, # Response time distribution
    :error_breakdown,   # Error types and counts
    :timeline,          # Events over time
    :recommendations    # Performance tuning suggestions
  ]
)
```

**Success Criteria:**
- Comprehensive metrics available
- Real-time monitoring during tests
- Actionable performance reports
- Export to common monitoring tools

**Estimated Effort:** 3-4 days

---

## Phase 8 (Optional): Connection Request Server

**Goal:** Support ACS-initiated connections (connection request URL).

### Deliverables

#### 8.1 Connection Request Listener
```elixir
Caretaker.CPE.ConnectionRequestServer
```

**Features:**
- HTTP server listening on per-device port or path
- Authentication (username/password)
- Respond to connection requests
- Trigger new Inform session

#### 8.2 Integration with Device
- Each device exposes ConnectionRequestURL in Inform
- Devices maintain persistent connection request listener
- Handle connection requests while idle

#### 8.3 URL Management
```elixir
# Dynamic port allocation per device
device = Device.new(
  connection_request: %{
    enabled: true,
    port: :auto,  # or specific port
    auth: %{username: "admin", password: "secret"}
  }
)

# URL reported in Inform
# => "http://192.168.1.100:7547/connection_request"
```

**Success Criteria:**
- ACS can initiate contact with idle devices
- Connection request triggers new session
- Authentication works correctly
- No port conflicts with multiple devices

**Estimated Effort:** 3-4 days

---

## Implementation Priority

### High Priority (Core Testing Needs)
1. **Phase 1** - Stateful Device Model (critical for realistic testing)
2. **Phase 2** - Full RPC Support (enables comprehensive ACS testing)
3. **Phase 3** - Firmware Upgrade Simulation (key workflow to validate)

### Medium Priority (Enhanced Testing)
4. **Phase 5** - Fleet Management (simplifies multi-device testing)
5. **Phase 4** - Dynamic Behaviors (more realistic simulation)
6. **Phase 6** - Advanced Testing Features (scenario testing)

### Low Priority (Nice to Have)
7. **Phase 7** - Enhanced Telemetry (better observability)
8. **Phase 8** - Connection Request Server (rarely tested in practice)

---

## Memory & Performance Considerations

**Current:** ~388 KB per session (100 concurrent = ~40 MB)

**Projected with Phases 1-3:**
- Device state storage: +100-200 KB per device
- Firmware simulator state: +50 KB per device
- **Estimated:** ~600-700 KB per active device

**Feasibility:**
- 100 devices: ~70 MB ✅ Excellent
- 500 devices: ~350 MB ✅ Good
- 1000 devices: ~700 MB ⚠️ Moderate (batch recommended)

**Optimization Strategies:**
- Use ETS instead of Agent for device state (shared memory)
- Lazy-load device profiles (only when needed)
- Pool Finch connections efficiently
- Implement device hibernation for idle devices

---

## Testing Strategy

Each phase should include:

### Unit Tests
- Module-level tests for new functionality
- Edge cases and error conditions
- Validate against TR-069 spec

### Integration Tests
- End-to-end flows (e.g., full firmware upgrade)
- Multi-device scenarios
- ACS integration tests

### Load Tests
- Performance impact of new features
- Memory usage validation
- Scalability verification

### Telemetry Tests
- Validate all events fire correctly
- Verify event metadata completeness
- Test telemetry handlers

---

## Documentation Requirements

For each phase:
- Update `docs/phase-5-cpe-client.md` with new features
- Add usage examples to README
- Document telemetry events in `docs/telemetry.md`
- Update CHANGELOG.md
- Add code examples in `livebook/` if applicable

---

## Success Metrics

**Phase 1-3 Complete:**
- ✅ Simulate 100+ devices with unique TR-181 models
- ✅ Support 10+ TR-069 RPCs with realistic behavior
- ✅ Complete firmware upgrade workflow end-to-end
- ✅ Memory usage < 100 MB for 100 devices
- ✅ All phases fully tested

**Phase 4-6 Complete:**
- ✅ Realistic device behaviors (periodic inform, dynamic params)
- ✅ Fleet management for 500+ devices
- ✅ Scenario-based testing framework
- ✅ Comprehensive load testing capability

**Phase 7-8 Complete:**
- ✅ Production-grade telemetry and observability
- ✅ Connection request support
- ✅ Grafana/Prometheus integration
- ✅ Commercial-quality testing framework

---

## Timeline Estimates

**Phases 1-3 (Core):** 8-11 days
**Phases 4-6 (Enhanced):** 8-11 days  
**Phases 7-8 (Advanced):** 6-8 days

**Total for complete implementation:** 22-30 days

**Recommended MVP:** Phases 1-3 only (8-11 days)

---

## Dependencies

**External:**
- None (all functionality can be implemented with existing deps)

**Internal:**
- Phases 2+ depend on Phase 1 (device state)
- Phase 3 depends on Phase 2 (Download/Reboot RPCs)
- Phase 5 depends on Phases 1-3 (full device simulation)
- Phase 7 depends on all prior phases (comprehensive telemetry)

---

## Questions to Answer

1. **Persistence:** Should device state persist between process restarts?
2. **Profiles:** Should we include real device profiles from vendors?
3. **Scale Target:** What's the maximum device count we need to support?
4. **Monitoring:** Which metrics backend is preferred (Prometheus, InfluxDB, both)?
5. **Distribution:** Should we support distributed testing (devices across multiple nodes)?

---

## Conclusion

This plan transforms the CPE client from a basic connectivity tester into a comprehensive ACS testing framework. The phased approach allows incremental value delivery while maintaining project stability.

**Recommended next steps:**
1. Review and approve phases 1-3 as MVP
2. Prioritize specific use cases for later phases
3. Create GitHub issues for each phase
4. Begin Phase 1 implementation
