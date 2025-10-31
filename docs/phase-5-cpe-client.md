# CPE Client Guide

This guide shows how to use the minimal TR-069 CPE client included in Caretaker to initiate a session with the built-in ACS.

## Overview

Flow:
- Build and send Inform to ACS
- Receive InformResponse
- Send empty POST to fetch next RPC (e.g., GetParameterValues)
- Respond to simple RPCs (currently GetParameterValues) and continue until 204

Defaults are conservative and spec-driven:
- SOAP 1.1 Envelope; `xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"`
- CWMP namespace mirrors peer; default `urn:dslforum-org:cwmp-1-0`
- Header includes `cwmp:ID` with `mustUnderstand="1"`

## Quick start

Start the ACS (Plug + Bandit) and the Finch HTTP pool, then run the client once.

```elixir
children = [
  {Bandit, plug: Caretaker.ACS.Server, port: 4000},
  {Finch, name: Caretaker.Finch}
]
Supervisor.start_link(children, strategy: :one_for_one)

{:ok, result} =
  Caretaker.CPE.Client.run_session("http://localhost:4000/cwmp",
    device_id: %{
      manufacturer: "Acme",
      oui: "A1B2C3",
      product_class: "Router",
      serial_number: "XYZ123"
    }
  )

# result = %{cwmp_id: ..., cwmp_ns: ..., inform_ack: true, rpc: "GetParameterValues" | nil}
```

## Telemetry

Events emitted by the client:
- `[:caretaker, :cpe_client, :session, :start|:stop]` — session lifecycle
- `[:caretaker, :cpe_client, :http, :request, :start|:stop]` — HTTP requests
- `[:caretaker, :cpe_client, :retry]` — retry with backoff
- `[:caretaker, :cpe_client, :rpc, :received]` — RPC received from ACS
- `[:caretaker, :cpe_client, :rpc, :responded]` — RPC responded by client
- `[:caretaker, :cpe_client, :rpc, :unsupported]` — RPC not handled by client
- `[:caretaker, :cpe_client, :error]` — errors

Attach handlers in tests or your app to observe metrics and state.

## Timeouts and retries

Options:
- `timeout` (default: 5_000 ms)
- `max_retries` (default: 3)
- `backoff_base` (default: 200 ms), exponential with full jitter

## Notes

- Use Logger for all logging; never IO.puts or IO.inspect.
- The client currently implements a minimal responder for GetParameterValues using the provided device_id.
- You can extend the responder with additional TR-069 RPCs following the same pattern.
