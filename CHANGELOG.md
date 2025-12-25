# Changelog

All notable changes to this project will be documented in this file.

## v0.2.0

### Added
- Simulated CPE client with full TR-069 compliance
- Phase 1: Stateful Device Model with persistent parameter storage (DeviceState)
- Phase 2: Full RPC Support (GetParameterNames, GetRPCMethods handlers)
- Phase 3: Firmware Upgrade Simulation (FirmwareSimulator)
- Phase 4: Dynamic Behaviors for CPE client (DynamicBehavior, device events)
- Phase 5: Fleet Management capabilities (spawn 100+ devices, staggered timing)
- Phase 8: Connection Request Server
- Device profiles: fiber_ont.json, cable_modem.json, mikrotik.json
- Device-specific event simulation (DOCSIS, PON, Router events)
- ACS-side device detection and parameter mapping
- Quirks system for vendor-specific behaviors (MikroTik)
- Livebooks for Phase 4, 5, and 8 features
- Device integration tests (GPON, DOCSIS, Mikrotik)

### Fixed
- RPC suite tests: match device_id between test and client

## v0.1.3

- Maintenance release (no functional changes)

## v0.1.2

### Added
- TR-069 RPC codecs: Download, Reboot, FactoryReset, TransferComplete
- TR-069 RPC codecs: Upload, GetRPCMethods, Get/SetParameterAttributes, ScheduleInform
- TR-069 RPC codecs: ScheduleDownload, GetQueuedTransfers, CancelTransfer
- TR-069 RPC codecs: AutonomousTransferComplete, RequestDownload
- Diagnostics helpers for Ping/TraceRoute/NSLookup

### Changed
- Migrated remaining encoders to Lather
- Added xsi/xsd namespace support in SOAP envelope

## v0.1.1

### Added
- Livebooks for interactive exploration

## v0.1.0

- TR-069 core: Inform/InformResponse (Lather), RPC registry, fixtures, and tests
- Minimal ACS (Plug + Bandit): Inform handling, queued command flow, content-type guards
- Additional RPCs: GetParameterNames/Values, SetParameterValues, AddObject, DeleteObject; Fault decoding
- TR-181: model helpers, validation, and Store integration; mapping GPV responses
- CWMP/SOAP: spec-driven helpers; namespace robustness (soapenv/xsi/xsd)
- Telemetry: ACS request timing, TR-069 encode/decode spans, TR-181 store updates; CPE client session/http/retry/rpc events
- Minimal CPE client (Finch): Inform → InformResponse → empty POST loop; basic GPV response
- Docs: CPE client guide, telemetry reference, release checklist; README updates
