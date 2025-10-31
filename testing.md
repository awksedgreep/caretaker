# Testing

This project uses `mix test` with ExUnit. Run the full suite (no limiting flags) and keep logs under control using Logger.

## Running tests
- Full suite: `mix test`
- Formatting check (optional but recommended): `mix format --check-formatted`
- Focus while developing (ok locally): `mix test test/path/to/file_test.exs` or `mix test --only focus`
  - Before merging, always run the full suite with plain `mix test`

## Structure
- Unit tests: `test/caretaker/**`
- Integration tests: `test/integration/**`
- Fixtures: `test/support/fixtures/` (place sample SOAP Inform/InformResponse envelopes here)

## Telemetry in tests
Attach temporary handlers to assert timings and payloads emitted by Caretaker (prefix `[:caretaker, ...]`).

```elixir
:ok =
  :telemetry.attach_many(
    "test-handler",
    [
      [:caretaker, :acs, :request, :start],
      [:caretaker, :acs, :request, :stop]
    ],
    fn event, measurements, metadata, _config ->
      send(self(), {:telemetry, event, measurements, metadata})
    end,
    nil
  )

# ... run code that triggers ACS handling ...

assert_received {:telemetry, [:caretaker, :acs, :request, :start], %{}, %{path: "/cwmp"}}
```

Detach after the test if you attach statefully:

```elixir
:telemetry.detach("test-handler")
```

## Logger in tests
- Use Logger assertions or capture logs when necessary; do not use `IO.puts`/`IO.inspect`
- Default log level is configured in `config/config.exs`; consider setting `:warn` in tests if noise is high

## Tips
- Prefer fixture-driven tests for CWMP envelopes and RPCs
- For RPC encode/decode, assert shapes and namespaces rather than exact string formatting when possible
- Keep tests deterministic; avoid sleeps when asserting telemetry—use message assertions instead
