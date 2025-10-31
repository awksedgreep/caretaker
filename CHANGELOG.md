# Changelog

All notable changes to this project will be documented in this file.

## v0.1.0

- TR-069 core: Inform/InformResponse (Lather), RPC registry, fixtures, and tests
- Minimal ACS (Plug + Bandit): Inform handling, queued command flow, content-type guards
- Additional RPCs: GetParameterNames/Values, SetParameterValues, AddObject, DeleteObject; Fault decoding
- TR-181: model helpers, validation, and Store integration; mapping GPV responses
- CWMP/SOAP: spec-driven helpers; namespace robustness (soapenv/xsi/xsd)
- Telemetry: ACS request timing, TR-069 encode/decode spans, TR-181 store updates; CPE client session/http/retry/rpc events
- Minimal CPE client (Finch): Inform → InformResponse → empty POST loop; basic GPV response
- Docs: CPE client guide, telemetry reference, release checklist; README updates
