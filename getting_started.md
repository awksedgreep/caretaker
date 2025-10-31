# Getting Started

Caretaker is an Elixir TR-069/TR-181 toolkit with a minimal ACS server and a small CPE client for local testing.

## Prerequisites
- Elixir ~> 1.17
- Erlang/OTP compatible with your Elixir install

## Using Caretaker as a dependency
Add to your `mix.exs`:

```elixir
def deps do
  [
    {:caretaker, "~> 0.1"}
  ]
end
```

Then:
- `mix deps.get`
- `mix compile`

## Local development (this repo)
1) Install deps and compile
- `mix deps.get`
- `mix compile`

2) Start an IEx session
- `iex -S mix`

3) Start a minimal ACS and (optionally) the example CPE client

```elixir
# Start Bandit with the built-in ACS Plug and (optionally) Finch for the client
children = [
  {Bandit, plug: Caretaker.ACS.Server, port: 4000},
  {Finch, name: Caretaker.Finch}
]
Supervisor.start_link(children, strategy: :one_for_one)

# Option A: Exercise the built-in CPE client against your local ACS
{:ok, result} =
  Caretaker.CPE.Client.run_session("http://localhost:4000/cwmp",
    device_id: %{
      manufacturer: "Acme",
      oui: "A1B2C3",
      product_class: "Router",
      serial_number: "XYZ123"
    }
  )

# Option B: POST CWMP SOAP envelopes to http://localhost:4000/cwmp using your own client
```

The ACS endpoint is `POST /cwmp`. Caretaker will parse CWMP SOAP (SOAP 1.1) and generate appropriate responses. The CPE client performs: Inform → InformResponse → empty POST, and responds minimally to common RPCs like GPV/SPV during examples.

## Telemetry and logging
- Telemetry prefix: `[:caretaker, ...]` (e.g., `[:caretaker, :acs, :request, :start|:stop]`)
- Configure Logger in `config/config.exs` (defaults to `:info`)

## Formatting and tests
- `mix format`
- `mix test` (full suite)

See `testing.md` for details on testing conventions, fixtures, and telemetry in tests.
