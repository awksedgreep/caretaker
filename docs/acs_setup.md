# ACS Setup Guide

This guide shows how to run the minimal ACS (Auto Configuration Server) included for examples/tests and how to interact with it.

## Start the ACS

Add Bandit with the Caretaker router to your supervision tree:

```elixir
children = [
  {Bandit, plug: Caretaker.ACS.Server, port: 4000}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

- Endpoint: `POST /cwmp`
- Content-Type: `text/xml; charset=utf-8`
- SOAP 1.1 envelope, CWMP namespace mirrored from peer (defaults to `urn:dslforum-org:cwmp-1-0`).

## Basic flow

1) Device sends Inform
- ACS responds with InformResponse echoing `cwmp:ID` and mirroring the CWMP namespace
- ACS may enqueue a `GetParameterValues` for `Device.DeviceInfo.`

2) Device sends an empty POST
- ACS dequeues the next command (if any) and returns a SOAP envelope (200)
- If the queue is empty, ACS responds 204 (No Content)

3) Device posts RPC responses
- Example: `GetParameterValuesResponse` is mapped into the TR-181 Store and ACS responds 204

## Example

```bash
curl -sS -X POST \
  -H 'Content-Type: text/xml; charset=utf-8' \
  --data-binary @test/fixtures/tr069/inform.xml \
  http://localhost:4000/cwmp
```

Follow with an empty POST to fetch the next RPC:

```bash
curl -sS -X POST http://localhost:4000/cwmp
```

## Telemetry

ACS emits:
- `[:caretaker, :acs, :request, :start|:stop]`
- `[:caretaker, :acs, :inform, :received]`
- `[:caretaker, :acs, :queue, :enqueue|:dequeue]`
- `[:caretaker, :tr181, :store, :updated]` on TR-181 merge

See `docs/telemetry.md` for details.

## Notes

- This ACS is a minimal example harness; production servers should manage sessions, persistence, and multi-tenancy at the application level.
- Logging uses `Logger`; avoid `IO.puts`/`IO.inspect`.
- SOAP/CWMP handling is spec-driven via Lather; use `Caretaker.CWMP.SOAP.encode_envelope/2` and `decode_envelope/1` for all messages.