# AGENTS.md - Critical Rules for AI Agents Working on the Caretaker Project

This document defines how agents must work in the Caretaker repository. Caretaker is a spec-driven TR-069/TR-181 toolkit intended to provision and manage GPON ONTs and potentially Mikrotik RouterOS devices.

## 🚨 ABSOLUTE DIRECTORY RULES - NO EXCEPTIONS

### ✅ CURRENT WORKING DIRECTORY
- ALWAYS STAY IN: `/Users/mcotner/Documents/elixir/caretaker`
- NEVER leave this directory or work in other projects without explicit user permission
- NEVER use `cd` to parent directories or other repositories

### 🛑 FORBIDDEN ACTIONS
- DO NOT assume scope; ask if uncertain
- DO NOT change directory structure without approval
- DO NOT add/remove dependencies without approval
- DO NOT use `IO.puts` or `IO.inspect` in code or tests — use `Logger.xxx`
- DO NOT run tests with limiting flags (e.g., `--max-failures`)
- ALWAYS run `git add -A` (or `git add .`) before committing or tagging

## 📋 PROJECT CONTEXT

### What is Caretaker?
- An Elixir library focused on TR-069/CWMP and TR-181 with a minimal ACS
- Targets GPON ONTs and potentially Mikrotik devices
- Strongly spec-driven (SOAP 1.1 + CWMP) with conservative defaults for compatibility

### Work scope (current phases)
- Phase 1: TR-069 core (Inform/InformResponse) with Lather; CWMP envelope helpers; fixtures and tests
- Phase 2: Minimal ACS request routing and response generation
- Later phases: Additional RPCs, TR-181 helpers, client, docs, telemetry expansion

## 🔍 MANDATORY PRACTICES

1) Spec-driven CWMP/SOAP
- Use SOAP 1.1 envelope (`http://schemas.xmlsoap.org/soap/envelope/`)
- Mirror the CWMP namespace from the CPE request when responding (e.g., `urn:dslforum-org:cwmp-1-0` … `-1-4`)
- If the incoming version is unknown, default to `urn:dslforum-org:cwmp-1-0` for maximum compatibility
- Always include `cwmp:ID` with `mustUnderstand="1"` and echo CPE’s ID when required
- Respond with `Content-Type: text/xml; charset=utf-8`

2) TR-069 session and correlation
- Correlate responses using CWMP ID
- Maintain per-device session context keyed by DeviceId (OUI, ProductClass, SerialNumber) when implementing ACS flows
- Prefer generic/spec-compliant behavior before vendor-specific tweaks

3) Testing protocol
- ALWAYS run the full suite: `mix test` (no `--max-failures`)
- Prefer fixture-driven tests for CWMP envelopes and RPCs
- Attach telemetry handlers in tests to assert events when needed
- Remove any temporary IO in tests before merging

4) Logging
- Use Logger exclusively; no `IO.puts`/`IO.inspect`
- Keep logs structured and at appropriate levels

5) Version control
- Stage all changes with `git add -A` before any commit or tag

## 📁 DIRECTORY LAYOUT CONVENTIONS
- `priv/spec/tr-069/` — vendored SOAP/CWMP XSDs and spec assets
- `test/fixtures/tr069/` — envelope samples (Inform, InformResponse, empty requests, etc.)
- `docs/` — technical notes (e.g., envelope strategy, ACS flow)

## ⚠️ ERROR HANDLING & ANALYSIS
- Read full errors before acting
- Identify whether failures are due to parsing, envelope shape, namespace, or test setup
- Verify fixes address the root cause and remain spec-conformant
- Ask before large refactors or config changes

## 📞 COMMUNICATION PROTOCOL
- Before implementing non-trivial changes, outline the plan and confirm scope
- Report planned changes and expected impact
- After changes, report test results and any follow-up items

## 🚨 EMERGENCY STOP CONDITIONS
- Unsure about CWMP/CPE version handling or envelope structure
- Risk of introducing vendor-specific hacks that violate spec
- Ambiguity about dependency additions or directory changes
- Unexpected widespread test failures

## ✅ SUCCESS CRITERIA
- Tests pass without limiting flags
- Generated envelopes are spec-conformant and conservative by default
- Behavior accommodates GPON and Mikrotik devices without vendor lock-in
- Changes are minimal, targeted, and approved when required
