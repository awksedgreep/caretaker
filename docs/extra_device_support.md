# Enhanced Device Support Plan

This document outlines the work required to better support specific device types in both the CPE Simulator and the ACS library components of Caretaker.

## Current State

Caretaker provides a **generic TR-069/CWMP implementation** that works with any compliant device. However, real-world deployments often involve device-specific behaviors, parameter sets, and quirks that benefit from explicit support.

### Supported Device Types (Current)
| Device Type | Profile | Simulator | ACS | Notes |
|-------------|---------|-----------|-----|-------|
| Generic TR-069 | ✅ | ✅ Full | ✅ Full | Reference implementation |
| Fiber ONT (GPON) | ✅ Basic | ✅ Good | ✅ Good | Missing PON-specific params |
| Cable Modem (DOCSIS) | ✅ Basic | ✅ Good | ✅ Good | Missing DOCSIS params |
| Mikrotik RouterOS | ❌ None | ⚠️ Partial | ⚠️ Partial | Needs profile and quirks |

---

## Phase 1: Enhanced Device Profiles

**Goal:** Create comprehensive TR-181 parameter profiles for each device type.

**Effort:** 2-3 days

### 1.1 GPON/XGPON ONT Profile Enhancement

Enhance `priv/profiles/fiber_ont.json` with PON-specific parameters:

```json
{
  "Device.Optical.Interface.1.Enable": "true",
  "Device.Optical.Interface.1.Status": "Up",
  "Device.Optical.Interface.1.OpticalSignalLevel": "-18.5",
  "Device.Optical.Interface.1.TransmitOpticalLevel": "2.3",
  "Device.Optical.Interface.1.LowerOpticalThreshold": "-27.0",
  "Device.Optical.Interface.1.UpperOpticalThreshold": "-8.0",
  "Device.Optical.Interface.1.Temperature": "45",
  
  "Device.Ethernet.Interface.1.Enable": "true",
  "Device.Ethernet.Interface.1.Status": "Up",
  "Device.Ethernet.Interface.1.MACAddress": "AA:BB:CC:DD:EE:FF",
  "Device.Ethernet.Interface.1.MaxBitRate": "1000",
  "Device.Ethernet.Interface.1.DuplexMode": "Full",
  
  "Device.WiFi.Radio.1.Enable": "true",
  "Device.WiFi.Radio.1.Status": "Up",
  "Device.WiFi.Radio.1.Channel": "6",
  "Device.WiFi.Radio.1.OperatingFrequencyBand": "2.4GHz",
  
  "Device.WiFi.SSID.1.Enable": "true",
  "Device.WiFi.SSID.1.SSID": "HomeNetwork",
  "Device.WiFi.SSID.1.BSSID": "AA:BB:CC:DD:EE:F0"
}
```

**PON-Specific Parameters to Add:**
- `Device.Optical.*` - Optical signal levels, thresholds, alarms
- `Device.X_VENDOR_PON.*` - Vendor-specific PON extensions (ONU ID, VLAN mappings)
- `Device.Bridging.*` - Bridge configurations for VLAN handling
- `Device.QoS.*` - Traffic management and queuing

### 1.2 DOCSIS Cable Modem Profile Enhancement

Enhance `priv/profiles/cable_modem.json` with DOCSIS-specific parameters:

```json
{
  "Device.Docsis.Status": "Operational",
  "Device.Docsis.BootState": "Operational",
  "Device.Docsis.DownstreamNumberOfEntries": "32",
  "Device.Docsis.UpstreamNumberOfEntries": "8",
  
  "Device.Docsis.Downstream.1.Frequency": "699000000",
  "Device.Docsis.Downstream.1.Power": "2.5",
  "Device.Docsis.Downstream.1.SNR": "38.5",
  "Device.Docsis.Downstream.1.Modulation": "256QAM",
  "Device.Docsis.Downstream.1.LockStatus": "Locked",
  
  "Device.Docsis.Upstream.1.Frequency": "36500000",
  "Device.Docsis.Upstream.1.Power": "42.0",
  "Device.Docsis.Upstream.1.Modulation": "64QAM",
  "Device.Docsis.Upstream.1.LockStatus": "Locked",
  
  "Device.Docsis.Interface.1.CMTSMACAddress": "00:11:22:33:44:55",
  "Device.Docsis.Interface.1.ConfigFileName": "gold.cfg"
}
```

**DOCSIS-Specific Parameters to Add:**
- `Device.Docsis.*` - CM status, channel information
- `Device.Docsis.Downstream.*` - Per-channel downstream stats
- `Device.Docsis.Upstream.*` - Per-channel upstream stats
- SNMP-to-TR-069 mapped parameters (common in cable deployments)

### 1.3 New Mikrotik RouterOS Profile

Create `priv/profiles/mikrotik.json`:

```json
{
  "Device.DeviceInfo.Manufacturer": "MikroTik",
  "Device.DeviceInfo.ManufacturerOUI": "D4CA6D",
  "Device.DeviceInfo.ModelName": "RB4011iGS+",
  "Device.DeviceInfo.ProductClass": "RouterOS",
  "Device.DeviceInfo.SoftwareVersion": "7.12.1",
  "Device.DeviceInfo.HardwareVersion": "r2",
  
  "Device.DeviceInfo.X_MIKROTIK_BoardName": "RB4011iGS+",
  "Device.DeviceInfo.X_MIKROTIK_Architecture": "arm",
  "Device.DeviceInfo.X_MIKROTIK_License": "6",
  
  "Device.Ethernet.InterfaceNumberOfEntries": "10",
  "Device.Ethernet.Interface.1.Enable": "true",
  "Device.Ethernet.Interface.1.Status": "Up",
  "Device.Ethernet.Interface.1.Name": "ether1",
  
  "Device.IP.Interface.1.Enable": "true",
  "Device.IP.Interface.1.IPv4AddressNumberOfEntries": "1",
  "Device.IP.Interface.1.IPv4Address.1.IPAddress": "192.168.88.1",
  "Device.IP.Interface.1.IPv4Address.1.SubnetMask": "255.255.255.0",
  
  "Device.Routing.Router.1.IPv4Forwarding.1.Enable": "true",
  "Device.Routing.Router.1.IPv4Forwarding.1.DestIPAddress": "0.0.0.0",
  "Device.Routing.Router.1.IPv4Forwarding.1.GatewayIPAddress": "10.0.0.1"
}
```

**Mikrotik-Specific Considerations:**
- RouterOS TR-069 package has limited parameter support
- Many features require script execution via vendor extensions
- `X_MIKROTIK_*` vendor-specific parameters
- Firewall rules typically managed via scripts, not TR-181 objects

### 1.4 Deliverables

- [ ] `priv/profiles/fiber_ont_full.json` - Comprehensive GPON/XGPON profile (150+ params)
- [ ] `priv/profiles/cable_modem_full.json` - Comprehensive DOCSIS profile (100+ params)
- [ ] `priv/profiles/mikrotik.json` - Mikrotik RouterOS profile (80+ params)
- [ ] `priv/profiles/xgspon_ont.json` - XGS-PON specific variant
- [ ] Profile documentation in each file (comments or companion .md)

---

## Phase 2: Dynamic Parameter Simulation

**Goal:** Simulate realistic, time-varying parameters for each device type.

**Effort:** 3-4 days

### 2.1 PON Signal Simulation

```elixir
defmodule Caretaker.CPE.Simulation.OpticalSignal do
  @moduledoc """
  Simulates realistic optical signal levels for PON devices.
  """
  
  def update_optical_params(device_state) do
    # Simulate slight variations in optical power
    current_rx = get_param(device_state, "Device.Optical.Interface.1.OpticalSignalLevel")
    new_rx = simulate_power_variation(current_rx, noise: 0.5)
    
    # Temperature affects optical power
    temp = get_param(device_state, "Device.Optical.Interface.1.Temperature")
    new_temp = simulate_temperature(temp, ambient: 25, load_factor: 0.3)
    
    device_state
    |> set_param("Device.Optical.Interface.1.OpticalSignalLevel", new_rx)
    |> set_param("Device.Optical.Interface.1.Temperature", new_temp)
  end
  
  defp simulate_power_variation(current, opts) do
    noise = Keyword.get(opts, :noise, 0.5)
    variation = :rand.normal() * noise
    Float.round(current + variation, 1)
  end
end
```

**Simulated Behaviors:**
- Optical signal level fluctuations (±0.5 dB normal, larger during issues)
- Temperature variations based on load and ambient
- Alarm triggering when thresholds exceeded
- ONU registration state changes

### 2.2 DOCSIS Channel Simulation

```elixir
defmodule Caretaker.CPE.Simulation.DocsisChannel do
  @moduledoc """
  Simulates DOCSIS downstream/upstream channel conditions.
  """
  
  def update_channel_stats(device_state) do
    # Downstream channels - slight SNR variations
    Enum.reduce(1..32, device_state, fn ch, state ->
      path = "Device.Docsis.Downstream.#{ch}"
      current_snr = get_param(state, "#{path}.SNR")
      new_snr = simulate_snr_variation(current_snr)
      set_param(state, "#{path}.SNR", new_snr)
    end)
  end
  
  def simulate_plant_issue(device_state, severity) do
    # Simulate ingress noise affecting upstream
    # Drop SNR, increase error counts
  end
end
```

**Simulated Behaviors:**
- Channel SNR variations
- Power level adjustments (T3/T4 timeouts)
- Partial service (some channels locked, some not)
- Upstream power limiting simulation

### 2.3 Mikrotik Resource Simulation

```elixir
defmodule Caretaker.CPE.Simulation.RouterResources do
  @moduledoc """
  Simulates router resource usage (CPU, memory, connections).
  """
  
  def update_resources(device_state, load_profile) do
    cpu_usage = simulate_cpu(load_profile)
    memory_usage = simulate_memory(load_profile)
    connection_count = simulate_connections(load_profile)
    
    device_state
    |> set_param("Device.DeviceInfo.ProcessStatus.CPUUsage", cpu_usage)
    |> set_param("Device.DeviceInfo.MemoryStatus.Free", memory_usage)
  end
end
```

### 2.4 Deliverables

- [ ] `lib/caretaker/cpe/simulation/optical_signal.ex` - PON signal simulation
- [ ] `lib/caretaker/cpe/simulation/docsis_channel.ex` - DOCSIS channel simulation
- [ ] `lib/caretaker/cpe/simulation/router_resources.ex` - Router resource simulation
- [ ] Integration with DynamicBehavior module
- [ ] Configurable simulation profiles (normal, degraded, failing)

---

## Phase 3: Vendor Quirks and Compatibility Layer

**Goal:** Handle known vendor-specific deviations from TR-069 spec.

**Effort:** 2-3 days

### 3.1 Quirks Module Architecture

```elixir
defmodule Caretaker.Quirks do
  @moduledoc """
  Vendor-specific compatibility adjustments.
  """
  
  @quirks %{
    # Mikrotik uses different parameter paths for some features
    "D4CA6D" => Caretaker.Quirks.Mikrotik,
    
    # Some Huawei ONTs have envelope encoding quirks
    "00E0FC" => Caretaker.Quirks.Huawei,
    
    # ZTE ONTs sometimes omit optional fields
    "001E58" => Caretaker.Quirks.ZTE,
    
    # Arris cable modems have specific parameter mappings
    "0015A4" => Caretaker.Quirks.Arris
  }
  
  def get_quirks(oui), do: Map.get(@quirks, String.upcase(oui))
  
  def apply_request_quirks(envelope, oui) do
    case get_quirks(oui) do
      nil -> envelope
      mod -> mod.transform_request(envelope)
    end
  end
  
  def apply_response_quirks(envelope, oui) do
    case get_quirks(oui) do
      nil -> envelope
      mod -> mod.transform_response(envelope)
    end
  end
end
```

### 3.2 Mikrotik Quirks

```elixir
defmodule Caretaker.Quirks.Mikrotik do
  @moduledoc """
  Mikrotik RouterOS TR-069 package quirks.
  
  Known issues:
  - Limited parameter set compared to full TR-181
  - Script execution for advanced configuration
  - Non-standard vendor extensions
  """
  
  @behaviour Caretaker.Quirks.Behaviour
  
  # Parameters that Mikrotik TR-069 package actually supports
  @supported_params [
    "Device.DeviceInfo.Manufacturer",
    "Device.DeviceInfo.ModelName",
    "Device.DeviceInfo.SoftwareVersion",
    "Device.DeviceInfo.UpTime",
    "Device.ManagementServer.URL",
    "Device.ManagementServer.Username",
    "Device.ManagementServer.Password",
    "Device.ManagementServer.PeriodicInformEnable",
    "Device.ManagementServer.PeriodicInformInterval",
    "Device.ManagementServer.ConnectionRequestURL",
    # ... limited set
  ]
  
  def supported_parameter?(path), do: path in @supported_params
  
  def transform_request(envelope) do
    # Mikrotik may need specific request formatting
    envelope
  end
  
  def transform_response(envelope) do
    # Handle Mikrotik-specific response quirks
    envelope
  end
  
  # Execute RouterOS script via vendor extension
  def execute_script(device, script) do
    # X_MIKROTIK_Script vendor extension
  end
end
```

### 3.3 Common ONT Quirks (Huawei, ZTE, Nokia)

```elixir
defmodule Caretaker.Quirks.HuaweiONT do
  @moduledoc """
  Huawei GPON ONT quirks.
  
  Known issues:
  - Some models encode empty strings as missing elements
  - Specific CWMP version requirements
  - Vendor-specific PON parameters
  """
  
  @vendor_params %{
    "Device.X_HW_VLANConfig" => :vlan_table,
    "Device.X_HW_GPON" => :pon_config
  }
  
  def transform_response(envelope) do
    # Normalize empty string handling
    envelope
  end
end
```

### 3.4 Deliverables

- [ ] `lib/caretaker/quirks.ex` - Quirks registry and dispatcher
- [ ] `lib/caretaker/quirks/behaviour.ex` - Quirks behaviour definition
- [ ] `lib/caretaker/quirks/mikrotik.ex` - Mikrotik-specific handling
- [ ] `lib/caretaker/quirks/huawei.ex` - Huawei ONT quirks
- [ ] `lib/caretaker/quirks/zte.ex` - ZTE ONT quirks
- [ ] `lib/caretaker/quirks/arris.ex` - Arris cable modem quirks
- [ ] Integration with SOAP encoder/decoder
- [ ] Documentation of known quirks per vendor

---

## Phase 4: Device-Specific Event Simulation

**Goal:** Generate realistic device events and alarms.

**Effort:** 2-3 days

### 4.1 PON Events

```elixir
defmodule Caretaker.CPE.Events.PON do
  @events [
    # Standard TR-069 events
    "1 BOOT",
    "2 PERIODIC",
    "4 VALUE CHANGE",
    "6 CONNECTION REQUEST",
    "7 TRANSFER COMPLETE",
    "8 DIAGNOSTICS COMPLETE",
    
    # PON-specific vendor events
    "X_ONU_REGISTRATION",
    "X_OPTICAL_ALARM",
    "X_DYING_GASP",
    "X_LINK_DOWN",
    "X_LINK_UP"
  ]
  
  def simulate_optical_alarm(device_state, alarm_type) do
    # Generate alarm event when optical power exceeds threshold
    rx_power = get_param(device_state, "Device.Optical.Interface.1.OpticalSignalLevel")
    threshold = get_param(device_state, "Device.Optical.Interface.1.LowerOpticalThreshold")
    
    if rx_power < threshold do
      add_event(device_state, "X_OPTICAL_ALARM", "low-rx-power")
    else
      device_state
    end
  end
  
  def simulate_dying_gasp(device_state) do
    # Power loss event - typically last message before device goes offline
    add_event(device_state, "X_DYING_GASP", "power-loss")
  end
end
```

### 4.2 DOCSIS Events

```elixir
defmodule Caretaker.CPE.Events.DOCSIS do
  @events [
    "X_CM_REGISTRATION",
    "X_CM_OPERATIONAL",
    "X_T3_TIMEOUT",
    "X_T4_TIMEOUT",
    "X_RANGING_FAILURE",
    "X_CONFIG_FILE_DOWNLOAD"
  ]
  
  def simulate_registration_flow(device_state) do
    # Simulate CM boot and registration sequence
    device_state
    |> set_param("Device.Docsis.Status", "Ranging")
    |> add_event("X_CM_REGISTRATION", "ranging")
    # ... progress through states
  end
end
```

### 4.3 Router Events

```elixir
defmodule Caretaker.CPE.Events.Router do
  @events [
    "X_FIRMWARE_UPGRADE",
    "X_CONFIG_CHANGE",
    "X_WAN_LINK_UP",
    "X_WAN_LINK_DOWN",
    "X_DHCP_LEASE_RENEWED"
  ]
end
```

### 4.4 Deliverables

- [ ] `lib/caretaker/cpe/events/pon.ex` - PON-specific events
- [ ] `lib/caretaker/cpe/events/docsis.ex` - DOCSIS-specific events
- [ ] `lib/caretaker/cpe/events/router.ex` - Router events
- [ ] Event triggering based on parameter changes
- [ ] Configurable event probability/frequency
- [ ] Alarm correlation (related events grouped)

---

## Phase 5: ACS-Side Device Support

**Goal:** Enhance ACS library to better handle device-specific responses.

**Effort:** 3-4 days

### 5.1 Device Detection

```elixir
defmodule Caretaker.ACS.DeviceDetection do
  @moduledoc """
  Detect device type from Inform message.
  """
  
  def detect(inform) do
    oui = inform.device_id.oui
    manufacturer = inform.device_id.manufacturer
    product_class = inform.device_id.product_class
    model = get_param(inform, "Device.DeviceInfo.ModelName")
    
    cond do
      is_mikrotik?(oui, manufacturer) -> {:mikrotik, detect_mikrotik_model(model)}
      is_gpon_ont?(oui, product_class) -> {:gpon_ont, detect_ont_vendor(oui)}
      is_cable_modem?(oui, product_class) -> {:cable_modem, detect_cm_vendor(oui)}
      true -> {:generic, :unknown}
    end
  end
  
  defp is_mikrotik?(oui, _), do: oui in ["D4CA6D", "2C:C8:1B", "E4:8D:8C"]
  defp is_gpon_ont?(_, product_class), do: String.contains?(product_class, ["ONT", "ONU", "GPON"])
  defp is_cable_modem?(_, product_class), do: String.contains?(product_class, ["CM", "Cable", "DOCSIS"])
end
```

### 5.2 Device-Aware Session Handling

```elixir
defmodule Caretaker.ACS.Session do
  # Enhanced session with device context
  
  def handle_inform(conn, inform) do
    device_type = DeviceDetection.detect(inform)
    quirks = Quirks.get_quirks(inform.device_id.oui)
    
    session = %Session{
      device_id: inform.device_id,
      device_type: device_type,
      quirks: quirks,
      cwmp_version: inform.cwmp_version
    }
    
    # Apply device-specific session handling
    case device_type do
      {:mikrotik, _} -> handle_mikrotik_session(session, inform)
      {:gpon_ont, vendor} -> handle_ont_session(session, inform, vendor)
      {:cable_modem, vendor} -> handle_cm_session(session, inform, vendor)
      _ -> handle_generic_session(session, inform)
    end
  end
end
```

### 5.3 Parameter Mapping

```elixir
defmodule Caretaker.ACS.ParameterMapping do
  @moduledoc """
  Map between canonical parameter names and device-specific paths.
  """
  
  # Canonical -> Device-specific mappings
  @mappings %{
    mikrotik: %{
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress",
      "WiFi.SSID" => "Device.WiFi.SSID.1.SSID"
      # Mikrotik has limited params, some concepts don't map
    },
    huawei_ont: %{
      "PON.RxPower" => "Device.Optical.Interface.1.OpticalSignalLevel",
      "PON.TxPower" => "Device.Optical.Interface.1.TransmitOpticalLevel",
      "WAN.IPAddress" => "Device.IP.Interface.1.IPv4Address.1.IPAddress"
    }
  }
  
  def to_device_path(canonical, device_type) do
    get_in(@mappings, [device_type, canonical]) || canonical
  end
  
  def from_device_path(device_path, device_type) do
    # Reverse lookup
  end
end
```

### 5.4 Deliverables

- [ ] `lib/caretaker/acs/device_detection.ex` - Device type detection
- [ ] `lib/caretaker/acs/parameter_mapping.ex` - Path translation
- [ ] Enhanced session handling with device context
- [ ] Device-specific RPC generation helpers
- [ ] Provisioning templates per device type

---

## Phase 6: Testing and Validation

**Goal:** Ensure device-specific implementations work correctly.

**Effort:** 2-3 days

### 6.1 Device-Specific Test Suites

```elixir
# test/devices/gpon_ont_test.exs
defmodule Caretaker.Devices.GPONONTTest do
  use ExUnit.Case
  
  describe "GPON ONT simulation" do
    test "optical signal parameters update correctly" do
      {:ok, state} = DeviceState.start_link(profile: :fiber_ont_full)
      {:ok, behavior} = DynamicBehavior.start_link(
        device_state: state,
        simulation: :optical_signal
      )
      
      # Verify optical levels vary realistically
      initial_rx = DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")
      Process.sleep(5000)
      later_rx = DeviceState.get(state, "Device.Optical.Interface.1.OpticalSignalLevel")
      
      assert initial_rx != later_rx
      assert later_rx > -30.0 and later_rx < 0.0
    end
    
    test "optical alarm triggers when threshold exceeded" do
      # ...
    end
  end
end
```

### 6.2 Integration Tests with Real Devices

**Status: ✅ COMPLETE (using simulator)**

```elixir
# test/integration/gpon_ont_integration_test.exs
defmodule Caretaker.Integration.GPONONTTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "Huawei GPON ONT simulation" do
    test "optical parameters simulation runs correctly"
    test "optical alarm triggers when signal degrades"
    test "dying gasp event on power loss"
    test "full ONT boot sequence with Inform"
  end

  describe "ZTE GPON ONT simulation" do
    test "ZTE ONT connects and reports parameters"
  end

  describe "XGS-PON ONT simulation" do
    test "XGS-PON ONT with higher speeds"
  end
end

# test/integration/cable_modem_integration_test.exs
defmodule Caretaker.Integration.CableModemTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "Arris cable modem simulation" do
    test "DOCSIS channels simulation runs correctly"
    test "RF plant issue simulation degrades channels"
    test "DOCSIS registration flow completes successfully"
    test "T3/T4 timeout events during upstream issues"
    test "full cable modem boot with Inform"
  end

  describe "Technicolor cable modem simulation" do
    test "Technicolor modem connects and reports DOCSIS stats"
  end

  describe "partial service simulation" do
    test "modem operates with subset of channels locked"
  end
end

# test/integration/mikrotik_integration_test.exs
defmodule Caretaker.Integration.MikrotikTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "Mikrotik RouterOS simulation" do
    test "RouterOS device connects with limited parameter set"
    test "resource usage simulation updates CPU and memory"
    test "script generation for WiFi configuration"
    test "script generation for firewall rules"
    test "WAN link events simulation"
    test "full Mikrotik boot sequence with Inform"
    test "version checking for adequate RouterOS version"
    test "alternative approach suggestions for unsupported parameters"
  end
end
```

**Implemented:** Comprehensive integration tests using the CPE simulator instead of physical devices

### 6.3 Deliverables

- [x] `test/integration/gpon_ont_integration_test.exs` - GPON/XGPON integration tests (6 tests)
- [x] `test/integration/cable_modem_integration_test.exs` - DOCSIS integration tests (8 tests)
- [x] `test/integration/mikrotik_integration_test.exs` - Mikrotik integration tests (8 tests)
- [x] `test/quirks/mikrotik_test.exs` - Quirks module tests (44 tests)
- [x] End-to-end device simulation with ACS communication
- [x] CI-ready tests (no physical hardware required)

**Total: 22 new integration tests + 44 quirks tests = 66 Phase 6 tests**

---

## Summary

### Total Effort Estimate

| Phase | Description | Effort | Priority |
|-------|-------------|--------|----------|
| 1 | Enhanced Device Profiles | 2-3 days | High |
| 2 | Dynamic Parameter Simulation | 3-4 days | Medium |
| 3 | Vendor Quirks Layer | 2-3 days | High |
| 4 | Device-Specific Events | 2-3 days | Medium |
| 5 | ACS-Side Device Support | 3-4 days | High |
| 6 | Testing and Validation | 2-3 days | High |
| **Total** | | **14-20 days** | |

### Recommended Implementation Order

1. **Phase 1** (Profiles) - Immediate value, enables testing
2. **Phase 3** (Quirks) - Critical for real device compatibility
3. **Phase 5** (ACS Support) - Enables production deployments
4. **Phase 6** (Testing) - Validate all implementations
5. **Phase 2** (Simulation) - Enhanced realism for testing
6. **Phase 4** (Events) - Advanced simulation scenarios

### Dependencies

```
Phase 1 (Profiles)
    ↓
Phase 2 (Simulation) ←──────┐
    ↓                       │
Phase 4 (Events) ───────────┤
                            │
Phase 3 (Quirks) ───────────┤
    ↓                       │
Phase 5 (ACS Support) ──────┤
    ↓                       │
Phase 6 (Testing) ──────────┘
```

### Success Criteria

- [ ] All major device types have comprehensive profiles (100+ params each)
- [ ] Simulator produces realistic, time-varying data
- [ ] Known vendor quirks are documented and handled
- [ ] ACS can detect and adapt to device types
- [ ] Test coverage for each device type
- [ ] Integration tests pass against real devices
- [ ] Documentation for device-specific behaviors
