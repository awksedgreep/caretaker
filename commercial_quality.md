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

1) Complete migration from SweetXml/regex parsing to Lather
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

2) Envelope handling and header compliance
- Ensure encode/decode mirrors CWMP namespace from request; default to urn:dslforum-org:cwmp-1-0 when unknown.
- Always echo cwmp:ID with mustUnderstand="1" when an ID is present.
- Expose optional header fields in encode_envelope/2 (HoldRequests, NoMoreRequests, SessionTimeout) while keeping conservative defaults.
- Acceptance:
  - Unit/integration tests assert namespace mirroring and ID echo
  - New tests cover optional header flags round-trip

3) RPC coverage expansion (codecs only)
- Add encoders/decoders + fixtures + round-trip tests for: Download, Upload, TransferComplete, AutonomousTransferComplete, Reboot, FactoryReset, GetRPCMethods, GetParameterAttributes, SetParameterAttributes, ScheduleInform, Diagnostics (Ping, TraceRoute, NSLookup).
- Acceptance:
  - Each RPC has: struct, encode/1, decode/1, fixtures, tests (positive + fault)

4) Fault handling via Lather
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

7) Example harness alignment (kept minimal)
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

Appendix: Known parsing hotspots to address
- lib/caretaker/acs/server.ex: regex-based detection of GetParameterValuesResponse and other fast-paths.
- lib/caretaker/cpe/client.ex: regex extraction for xmlns:cwmp, RPC local-name, and cwmp:ID.
- lib/caretaker/tr069/rpc/inform.ex: decode uses SweetXml.
- lib/caretaker/tr069/rpc/get_parameter_names.ex: decode uses SweetXml.
- lib/caretaker/tr069/rpc/fault.ex: decode uses SweetXml and regex fallback.
- lib/caretaker/cwmp/soap.ex: uses regex only for whitespace minification (acceptable; not parsing).

Note
- This list is limited to protocol-library scope. Transport/TLS, persistence, operator UIs, and external admin APIs are intentionally out of scope.
