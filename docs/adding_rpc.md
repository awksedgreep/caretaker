# Adding a TR-069 RPC

This guide outlines how to add a new TR-069 RPC codec (encode/decode) to Caretaker.

## Pattern

1) Define a struct and typespecs
- Keep names spec-driven; use strings for XML element names and attributes when building maps

2) Implement encode/1 via Lather
- Build a nested map matching the desired XML, e.g. `%{"cwmp:Foo" => %{...}}`
- Call `Lather.Xml.Builder.build_fragment(map)` to produce the body fragment (without the SOAP envelope)

3) Implement decode/1 via Lather
- Wrap the incoming fragment to stabilize prefixes, then parse:

```elixir
wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
  node = parsed["root"]["cwmp:Foo"] || parsed["root"]["Foo"] || %{}
  # Extract fields from node
end
```

- Tolerate prefix and attribute order differences; prefer fetching by keys and lists

4) Add tests
- Round-trip tests for encode/decode using `Caretaker.CWMP.SOAP.encode_envelope/2` and `decode_envelope/1`
- Include negative or variant fixtures when applicable

5) Wire up (optional)
- For ACS examples, dispatch is based on the RPC element local-name via `SOAP.decode_envelope/1`; no central registry is required
- If the CPE client should respond to the new RPC, extend `Caretaker.CPE.Client.respond_to_rpc/6`

## Conventions

- Mirror the CWMP namespace from the peer; default to `urn:dslforum-org:cwmp-1-0`
- Echo `cwmp:ID` with `mustUnderstand="1"` when present in requests
- Use `Logger` only; avoid IO in tests and code
- Keep telemetry spans for encode/decode where appropriate

## Example skeleton

```elixir
defmodule Caretaker.TR069.RPC.Foo do
  @enforce_keys [:bar]
  defstruct [:bar]

  @type t :: %__MODULE__{bar: String.t()}

  @spec encode(t()) :: {:ok, iodata()} | {:error, term()}
  def encode(%__MODULE__{bar: bar}) do
    Lather.Xml.Builder.build_fragment(%{"cwmp:Foo" => %{"Bar" => bar}})
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(xml) do
    wrapped = "<root xmlns:cwmp=\"urn:dslforum-org:cwmp-1-0\">" <> xml <> "</root>"
    with {:ok, parsed} <- Lather.Xml.Parser.parse(wrapped) do
      root = parsed["root"] || %{}
      node = root["cwmp:Foo"] || root["Foo"] || %{}
      {:ok, %__MODULE__{bar: node["Bar"] || ""}}
    end
  end
end
```