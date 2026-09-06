# Commercial-Quality Protocol Library Enhancements

Scope
- This document defines enhancements to make Caretaker a robust TR-069/CWMP protocol library. It applies to codecs, envelope handling, telemetry, tests, and docs.

Non-goals
- Transport/TLS configuration
- Persistence or data stores
- Admin UX or external operator APIs
- Multi-tenancy/RBAC
- Deployment/packaging concerns

Enhancements (with acceptance criteria)

Progress (completed)
- Lather-only parsing for key paths: Inform, GetParameterNames, Fault; ACS.Server dispatch via SOAP.decode_envelope; CPE.Client switched to SOAP.decode_envelope
- Header compliance: cwmp ns mirroring, cwmp:ID echo, optional HoldRequests/NoMoreRequests/SessionTimeout; tests added
- RPC codecs added with round-trip tests: Download(+Response), Upload(+Response), TransferComplete(+Response), AutonomousTransferComplete(+Response), Reboot(+Response), FactoryReset(+Response), GetRPCMethods(+Response), GetParameterAttributes(+Response), SetParameterAttributes(+Response), ScheduleInform(+Response), ScheduleDownload(+Response), GetQueuedTransfers(+Response), CancelTransfer(+Response)
- Interop list handling: normalized MethodList/ParameterNames/AccessList decoding across variations
- Example harnesses kept minimal and delegated decoding/encoding to library

Open items
- Diagnostics (Ping/TraceRoute/NSLookup) — codecs or guidance (likely parameter-model based rather than standalone RPCs)
- Multi-timewindow parity in ScheduleDownload decode (currently validated with single TimeWindow; expand test/decoder to fully support multiple windows)
- Docs/ExDoc polish: update README supported RPCs, namespace/version behavior, telemetry guide; add examples
- Telemetry audit to ensure all new RPCs emit encode/decode spans
- Consider proposing removal of SweetXml (post-migration) as a separate, approved change

1) Complete migration from SweetXml/regex parsing to Lather [DONE]
- Replace all RPC decoders and any XML parsing in examples/harness to rely on Lather (builders/parsers) only.
- Target modules/functions:
  - Caretaker.TR069.RPC.Inform.decode/1 (uses SweetXml)
  - Caretaker.TR069.RPC.GetParameterNames.decode/1 (uses SweetXml)
  - Caretaker.TR069.RPC.Fault.decode/1 (uses SweetXml + regex fallback)
  - Caretaker.ACS.Server: remove regex fast-paths for GetParameterValuesResponse; use SOAP.decode_envelope + RPC decoder
  - Caretaker.CPE.Client: replace regex extraction (cwmp ns, RPC name, cwmp:ID) with SOAP.decode_envelope
- Keep benign regex only for whitespace minification (not parsing) if desired.
- Acceptance:
  - No SweetXml usage remains in the above modules
  - No regex used to parse RPC names/IDs/body in ACS.Server or CPE.Client
  - All tests pass

2) Envelope handling and header compliance [DONE]
- Ensure encode/decode mirrors CWMP namespace from request; default to urn:dslforum-org:cwmp-1-0 when unknown.
- Always echo cwmp:ID with mustUnderstand="1" when an ID is present.
- Expose optional header fields in encode_envelope/2 (HoldRequests, NoMoreRequests, SessionTimeout) while keeping conservative defaults.
- Acceptance:
  - Unit/integration tests assert namespace mirroring and ID echo
  - New tests cover optional header flags round-trip

3) RPC coverage expansion (codecs only)
- Added: Download, Upload, TransferComplete, AutonomousTransferComplete, Reboot, FactoryReset, GetRPCMethods, GetParameterAttributes, SetParameterAttributes, ScheduleInform, ScheduleDownload, GetQueuedTransfers, CancelTransfer
- Pending: Diagnostics (Ping, TraceRoute, NSLookup), RequestDownload
- Acceptance:
  - Each RPC has: struct, encode/1, decode/1, fixtures, tests (positive + fault)

4) Fault handling via Lather [DONE]
- Decode SOAP Fault and cwmp:Fault strictly via Lather (no regex), mapping to a typed struct.
- Acceptance:
  - Fault fixtures (SOAP and CWMP) decode deterministically; unknown fields tolerated without crash

5) Interop robustness
- Tolerate varied XML prefixes, attribute order, whitespace, and cwmp version (1.0–1.4) during decode.
- Provide fixtures covering common variations; preserve spec-conformant output on encode.
- Acceptance:
  - Decode tests pass across variant fixtures; encode output validated against fixtures where applicable

6) Telemetry and logging hygiene
- Emit encode/decode spans uniformly: [:caretaker, :tr069, :rpc, :encode|:decode, :start|:stop] with rpc atom and optional id.
- Keep logs minimal and use Logger only; avoid logging device-specific identifiers by default.
- Acceptance:
  - Telemetry present for all RPC encode/decode paths; Logger calls audited for noise

7) Example harness alignment (kept minimal) [DONE]
- Keep ACS.Server and CPE.Client as examples/test harnesses only; delegate all XML handling to the library functions.
- Acceptance:
  - ACS.Server uses SOAP.decode_envelope and RPC decoders; CPE.Client uses SOAP.decode_envelope for response parsing; no ad-hoc regex/XML parsing

8) Documentation
- Update README and ExDoc to clearly state library scope, supported RPCs, namespace/version behavior, and telemetry events.
- Acceptance:
  - mix docs builds; README reflects current capabilities and scope

9) Dependencies and compatibility
- Do not add/remove dependencies in this task. After migration is complete, propose removal of SweetXml as a separate, approved change.
- Acceptance:
  - This document notes the constraint and defers any dep changes.

Appendix: Known parsing hotspots (addressed)
- lib/caretaker/acs/server.ex: removed regex fast-paths; unified on SOAP.decode_envelope
- lib/caretaker/cpe/client.ex: switched to SOAP.decode_envelope; removed regex parsing
- lib/caretaker/tr069/rpc/inform.ex: migrated to Lather
- lib/caretaker/tr069/rpc/get_parameter_names.ex: migrated to Lather
- lib/caretaker/tr069/rpc/fault.ex: migrated to Lather (no regex)
- lib/caretaker/cwmp/soap.ex: regex only for whitespace minification (acceptable; not parsing)

Note
- This list is limited to protocol-library scope. Transport/TLS, persistence, operator UIs, and external admin APIs are intentionally out of scope.
