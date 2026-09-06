# Changelog

All notable changes to this project will be documented in this file.

## v0.4.0 - 2026-09-06

### Added
- MQTT consolidated on `mqttx` (client + broker); `nipper` and `tortoise311`
  dropped. New live USP-over-MQTT round-trip test through an embedded broker.
- Northbound API extended for the majordomo ACS integration: Reboot/Download/
  FactoryReset task submits, latest-known parameter cache
  (`Tasks.parameters/1`), device source IP + ConnectionRequestURL + WAN IP in
  presence, connection-request Basic/Digest auth, and `Tasks.snapshot/0` +
  `:restore` for surviving restarts.
- `Caretaker.ACS.Auth`: inbound Basic/Digest authentication for the ACS server
  (stateless nonces, optional per-device credential lookup), configured at mount.
- `Caretaker.ACS`: documented Inform-subscription API (`on_inform/2`,
  `subscribe_informs/0`) delivering `device_id`, events, `parameter_list` and
  `source_ip`.
- `[:caretaker, :acs, ...]` telemetry documented as a stable public contract.

## v0.3.0

### Added
- Northbound HTTP task API for external change agents (`Caretaker.ACS.Tasks`,
  `Caretaker.ACS.API`): submit set/get, task status, per-task and bulk-by-tag
  cancellation, task TTL, idempotency keys, device presence, connection
  requests, terminal-state webhooks, documented rate limits, and batch
  submission. See `docs/task_api.md`.
- `Caretaker.ACS.Session`: command TTL/expiry and tag/id-based cancellation.
- `Caretaker.HTTP` shared Finch pool and `Caretaker.HTTP.Auth` (Basic/Digest);
  the CPE client now echoes cookies and answers auth challenges.

### Changed
- Adopted lather 1.1 (repeated-sibling XML builder semantics); pinned `~> 1.1`.
- ACS answers a CPE RPC response by sending the next queued RPC (TR-069
  session flow), and returns CWMP SOAP Faults on errors.
- Dependencies upgraded to clear HTTP-stack security advisories.
- `nipper` is now a test-only dependency; its broker config moved to
  `config/test.exs` (migration to the mqttx broker tracked in #38).
- String parameter values are typed `xsd:string` rather than guessed numeric.

### Fixed
- Correctness and crash fixes across the ACS, CPE client, TR-069 codecs, USP
  agent/controller/transports, simulation, and fleet (see closed issues #1–#32).

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
