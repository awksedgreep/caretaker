# Caretaker

An Elixir TR-069/TR-181 toolkit.

## Features

- TR-069 RPC structs and codecs powered by Lather
- Minimal ACS server built on Plug and Bandit
- Telemetry-first design `[:caretaker, ...]`
- Logger-based logging (no IO.puts or IO.inspect)
- TR-181 model primitives and store mapping
- Minimal CPE client (Finch): Inform → InformResponse → empty POST, basic RPC handling (GPV)

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:caretaker, "~> 0.1"}
  ]
end
```

Caretaker depends on `:lather` (pulled from Hex).

## Quick start

Start a minimal ACS in a supervision tree:

```elixir
children = [
  {Bandit, plug: Caretaker.ACS.Server, port: 4000}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

Then POST CWMP SOAP to `http://localhost:4000/cwmp`.

## Telemetry

Caretaker emits:

- `[:caretaker, :acs, :request, :start]`
- `[:caretaker, :acs, :request, :stop]`

Additional TR-069 encode/decode events will be added.

## Supported RPCs

Implemented encoders/decoders (spec-driven):
- Inform (encode/decode)
- InformResponse (encode/decode)
- GetParameterNames (+Response) (encode/decode)
- GetParameterValues (+Response) (encode/decode)
- SetParameterValues (+Response) (encode/decode)
- AddObject (+Response) (encode/decode)
- DeleteObject (+Response) (encode/decode)
- Fault (cwmp and SOAP) (decode)

## CPE client usage

A minimal client is included to initiate a session and handle basic RPCs.

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

# The client will:
# - Send Inform and await InformResponse
# - POST empty to fetch next RPC
# - Respond minimally to GetParameterValues (using device_id) and SetParameterValues (status 0)
```

## Logging

All logging uses Elixir Logger. Configure level in `config/config.exs`. No IO.puts or IO.inspect are used.

## Roadmap

- Phase 0: Scaffolding, README, License, initial stubs, compile and test (done)
- Phase 1: TR-069 core (Inform/InformResponse with Lather), RPC registry, fixtures & tests (done)
- Phase 2: Minimal ACS (Plug + Bandit), parse Inform and respond; telemetry timing; integration tests (done)
- Phase 3: Expand RPCs (GetParameterNames/GetParameterValues/SetParameterValues/AddObject/DeleteObject); Fault handling (done)
- Phase 4: TR-181 model primitives and mapping helpers (done)
- Phase 5: CPE client session loop, retries/backoff, telemetry (done)
- Phase 6: Docs, examples, Hex release (in progress)

## Contributing

- Read `AGENTS.md` and follow it exactly
- Always stage all files with `git add -A` before committing
- Run `mix format` and `mix test` before submitting

## License

MIT, see `LICENSE`
