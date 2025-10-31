# Caretaker Project Plan

A multi-phase plan to deliver an Elixir TR-069/TR-181 toolkit using Lather (SOAP), Plug + Bandit (ACS), Telemetry, and Logger.

## Module namespaces
- Caretaker
- Caretaker.CWMP
  - Caretaker.CWMP.SOAP
- Caretaker.TR069
  - Caretaker.TR069.Types
  - Caretaker.TR069.RPC.{Inform, InformResponse, GetParameterNames, GetParameterValues, SetParameterValues, AddObject, DeleteObject, Fault}
- Caretaker.ACS
  - Caretaker.ACS.Server
  - Caretaker.ACS.Telemetry
- Caretaker.CPE
  - Caretaker.CPE.Client (future)
- Caretaker.TR181
  - Caretaker.TR181.Model (future)

## Telemetry
- Library prefix: [:caretaker, ...]
- ACS: [:caretaker, :acs, :request, :start|:stop]
- TR-069 RPC encode/decode spans: implemented in core paths, expanding across newly added RPCs
  - [:caretaker, :tr069, :rpc, :encode, :start|:stop], meta: %{rpc: atom(), id: String.t()}
  - [:caretaker, :tr069, :rpc, :decode, :start|:stop], meta: %{rpc: atom(), id: String.t()}

## Phase 0 — Scaffolding (DONE)
Goals
- Mix project, deps (lather, plug, bandit, telemetry, ex_doc), Logger config, LICENSE, README, AGENTS.md.
- Namespaces and stubs compile and tests run.
Deliverables
- Compilable project; README with roadmap.
Acceptance
- mix test passes (with intentional skips allowed), ex_doc builds.

## Phase 1 — TR-069 Core (Inform/InformResponse with Lather)
Goals
- Implement CWMP envelope/header helpers with Lather.
- Implement RPC encode/decode for Inform and InformResponse.
- Introduce RPC registry and type validations.
- Emit TR-069 encode/decode telemetry; add fixtures and round-trip tests.

Status (completed)
- DONE: Spec-driven SOAP 1.1 helpers (encode_envelope/2, decode_envelope/1)
- DONE: Inform and InformResponse structs with encode/1 and decode/1
- DONE: RPC registry (Inform, InformResponse)
- DONE: Fixtures and round-trip test (Inform -> InformResponse)
- DONE: Internal PubSub topic for Inform and MQTT bridge publisher
- DONE: Replaced regex/SweetXml parsing in core paths with Lather builders/parsers (ACS.Server/CPE.Client/Inform/GPN/Fault)
- IN PROGRESS: Expand TR-069 telemetry spans across all RPC encode/decode paths

Tasks
- Caretaker.CWMP.SOAP: encode_envelope/2, decode_envelope/1 (swap to Lather when ready).
- Caretaker.TR069.RPC.{Inform, InformResponse}: encode/1, decode/1 (instrument telemetry).
- Registry: map XML RPC names <-> modules.
- Test fixtures: sample Inform and InformResponse envelopes; round-trip tests.

Deliverables
- Working round-trip (Inform -> InformResponse) with fixtures.

Acceptance
- Tests for encode/decode and registry pass; telemetry events observed in tests.

## Phase 2 — Minimal ACS (Plug + Bandit)
Goals
- POST /cwmp endpoint that decodes CWMP SOAP via Lather and routes to RPC handlers.
- Respond to Inform with InformResponse (CWMP ID correlation).
- Structured logging + request timing telemetry.

Status (completed minimal scope)
- DONE: ACS.Server decodes Inform, publishes to PubSub, responds with InformResponse (echo cwmp:ID; mirror CWMP ns; text/xml)
- DONE: ACS.Session global FIFO queue; empty POST returns next queued command or 204
- DONE: Queue GetParameterValues("Device.DeviceInfo.") after Inform
- DONE: Integration tests for Inform -> InformResponse and empty POST flow
- DONE: Robust SOAP decode via Lather; graceful error handling
- DONE: Error handling paths (400 on malformed/unknown RPC) with tests
- DONE: Telemetry around Inform encode/decode and ACS queue/inform events
- DONE: 415 on unsupported content-type
- PENDING: Per-device sessions keyed by DeviceId; broaden telemetry spans

Tasks
- Expand Caretaker.ACS.Server: body parsing, content-type, error handling, ID correlation.
- Response via CWMP envelope build; return text/xml; charset=utf-8.
- Integration tests using Plug.Test; fixture-driven Inform request -> InformResponse.

Deliverables
- Minimal working ACS that can receive Inform and respond.

Acceptance
- Integration tests pass; verified content-type and valid SOAP structure.

## Phase 3 — Additional TR-069 RPCs
Goals
- Implement GetParameterNames, GetParameterValues, SetParameterValues, AddObject, DeleteObject.
- Fault handling end-to-end.

Status (completed and expanded)
- DONE: Lather-based encoders/decoders for GetParameterNames(+Response), GetParameterValues(+Response), SetParameterValues(+Response), AddObject(+Response), DeleteObject(+Response)
- DONE: Added codecs + tests: Download(+Response), Upload(+Response), TransferComplete(+Response), AutonomousTransferComplete(+Response), Reboot(+Response), FactoryReset(+Response), GetRPCMethods(+Response), GetParameterAttributes(+Response), SetParameterAttributes(+Response), ScheduleInform(+Response), ScheduleDownload(+Response), GetQueuedTransfers(+Response), CancelTransfer(+Response), RequestDownload(+Response)
- DONE: Fault decoder for cwmp and SOAP Faults
- DONE: Registry entries + fixtures and round-trip tests

Tasks
- Structs, encode/decoders; extend registry; error/fault mapping.
- Fixtures and tests for each RPC.

Deliverables
- RPC coverage for common provisioning flows; fault round-trips.

Acceptance
- Unit/integration tests pass; fault scenarios covered.

## Phase 4 — TR-181 Model

Diagnostics helpers (added)
- Added helpers to build SetParameterValues for TR-181 diagnostics: Ping, TraceRoute, NSLookup (Requested state)
Goals
- Core parameter model primitives and constraints.
- Mapping between TR-069 ParameterValueStruct and TR-181 params.

Status (completed)
- DONE: TR-181 Model helpers (types/cast, path normalization, round-trip)
- DONE: Validation rules and tests (required, type, min/max, enum)
- DONE: TR-181 Store merge/deep-merge tests
- DONE: ACS integration test mapping GetParameterValuesResponse -> TR-181 Store
- DONE: Fixture for GetParameterValuesResponse

Tasks
- Caretaker.TR181.Model: types, validation helpers, normalization.
- Mappers between TR-069 RPC payloads and TR-181 structures.
Deliverables
- Utility API for working with TR-181 params.
Acceptance
- Tests for type validation and mapping correctness.

## Phase 5 — CPE Client
Goals
- Minimal client capable of initiating session and sending Inform to an ACS.
- Retries/backoff and telemetry.
- Fetch next RPC (empty POST) and respond to simple RPCs.

Status (completed)
- DONE: Finch-based HTTP transport and supervision
- DONE: One-shot session: Inform -> InformResponse -> empty POST fetch
- DONE: Namespace robustness (soapenv/xsi/xsd declarations)
- DONE: Telemetry for session/http/retry; Logger-only logging
- DONE: Integration test using Bandit ACS.Server
- DONE: Minimal GPV Response from client using device_id fields
- DONE: Full RPC loop until 204 with GPV response

Tasks
- N/A (completed)

Deliverables
- Library-level client API with session start and initial RPC handling.

Acceptance
- Integration tests pass for Inform round-trip and RPC (GPV) response; telemetry asserted.

## Phase 6 — Docs & Release
Goals
- ExDoc guides, examples, README polish
- Prepare for Hex release v0.1.0

Status (in progress)
- DONE: Initial CPE client guide stub
- DONE: Telemetry guide
- PENDING: README polish; release checklist run-through

Tasks
- Add docs/phase-5-cpe-client.md with usage and telemetry events
- Update README Features/Roadmap to reflect Phase 4–5 completion
- Verify mix docs builds; ensure docs.extras includes new guides
- Prepare release checklist: version bump, changelog, hex metadata review

Deliverables
- Published docs with CPE example and telemetry

Acceptance
- mix docs builds; README and guides reflect current capabilities

## Phase 6 — Docs & Release
Goals
- ExDoc guides, examples, and README polish.
- Hex release v0.1.0.
Tasks
- Guides: ACS setup, Inform round-trip, adding RPCs, telemetry hooks.
- Changelog, version bump, hex metadata review.
Deliverables
- Published package and docs.
Acceptance
- mix hex.publish dry-run passes; docs build; README badges.

## Non-goals (initial)
- Full TR-069/TR-181 coverage; device-specific quirks; persistent storage; high-availability ACS.

## Risks & mitigations
- SOAP/XML edge cases: rely on Lather + fixtures; build strict tests.
- Interop variance: focus on spec-conformant fixtures first; add adapters later.

## Testing strategy
- Unit tests for encode/decode and types.
- Fixture-driven integration tests for ACS endpoint with Plug.Test.
- Telemetry assertions via :telemetry.attach handlers in tests.

## Versioning & Milestones
- v0.1.0: Phases 0–2 (scaffold, Inform/InformResponse, minimal ACS).
- v0.2.x: Phase 3 (additional RPCs) + part of Phase 4.
- v0.3.x: Phase 4 completion + Phase 5 (client).
- v0.4.x: Expanded RPC set (firmware, attributes, scheduling, transfer ops), diagnostics helpers, header compliance tests.

## Release checklist
- All tests green; dialyzer (optional) clean; formatted.
- Docs: README, guides, examples updated.
- mix.exs metadata verified (license, links, description).
- Tag release; mix hex.publish.
