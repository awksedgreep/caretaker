# Northbound task API

Caretaker's ACS can expose a JSON HTTP API for an external change agent (for
example an AP manager) to drive TR-069 changes through the same command queue
the CWMP session already uses. A *task* is one queued change or read for a
device, tracked to a terminal state so the caller can learn its outcome and
cancel or expire it safely.

This implements the requests in issue #34 (CR-1 through CR-10).

## Wiring it up

The API is a Plug router and does not start a web server on its own. Run it
behind Bandit alongside the ACS and its supporting processes:

```elixir
children = [
  Caretaker.PubSub,
  Caretaker.ACS.Session,
  Caretaker.TR181.Store,
  {Caretaker.ACS.Tasks, webhook_url: "https://apmgr.example/hooks", webhook_secret: "s3cr3t"},
  {Bandit, plug: Caretaker.ACS.Server, port: 7547},
  {Bandit, plug: Caretaker.ACS.API, port: 8090}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

`Caretaker.ACS.Tasks` is the registry; `Caretaker.ACS.API` is the HTTP surface;
`Caretaker.ACS.Server` (the `/cwmp` endpoint) reports delivery and completion
back to the registry. `Caretaker.TR181.Store` is needed for connection requests
and to receive read results; `Caretaker.PubSub` powers presence.

`Caretaker.ACS.Tasks` options: `:webhook_url`, `:webhook_secret`,
`:default_ttl_ms` (default 6h), `:retention_ms` (default 90 days),
`:rate_limit` (submissions per second, default 50).

## Device ids

A device is addressed as `OUI-ProductClass-SerialNumber` (the serial may itself
contain dashes). This is the same identity the ACS derives from a device's
Inform.

## Task lifecycle

```
queued ──delivered──> delivered ──> applied
   │                                   ▲
   │                                   └── (Get) carries the returned values
   ├── ttl reached ──> expired
   ├── cancelled ────> cancelled
   └── CPE fault ────> faulted
```

Every task reaches exactly one terminal state: `applied`, `faulted`, `expired`
or `cancelled`. Tasks are correlated to the CWMP session by the `cwmp:ID` the
ACS places on the request the device eventually answers.

## Endpoints (under `/api/v1`)

### CR-1 Submit a parameter set

```
POST /api/v1/devices/AABBCC-Router-SN123/tasks/set-parameters
{
  "parameters": [
    {"path": "Device.WiFi.Radio.2.Channel", "value": "44", "type": "unsignedInt"},
    {"path": "Device.WiFi.Radio.2.TransmitPower", "value": "75", "type": "int"}
  ],
  "ttl_seconds": 21600,
  "tag": "apmgr:pass-8842",
  "idempotency_key": "apmgr:pass-8842:dev-11719:r2"
}
→ 202 {"task_id": "tsk_...", "state": "queued"}
```

A value with no `type` is sent as `xsd:string`; supply `type` for numeric or
boolean parameters (`"unsignedInt"` is normalized to `xsd:unsignedInt`).

### CR-2 Read parameters

```
POST /api/v1/devices/AABBCC-Router-SN123/tasks/get-parameters
{"paths": ["Device.WiFi.Radio.2.Channel", "Device.WiFi.Radio.2.TransmitPower"]}
→ 202 {"task_id": "tsk_...", "state": "queued"}
```

The returned values appear in the task's `result.parameters` once applied.

### CR-3 Task status

```
GET /api/v1/tasks/tsk_...
→ {"task_id": "...", "device_id": "...", "type": "get",
   "state": "applied", "submitted_at": "...", "delivered_at": "...",
   "completed_at": "...", "fault": null, "result": {"parameters": {...}}}
```

On a CPE fault the raw code is exposed: `"fault": {"code": "9006", "message": "..."}`.

### CR-4 TTL and cancellation

`ttl_seconds` on submit bounds how long a task may sit undelivered; the default
is applied when omitted, so a change can never land days later outside a
maintenance window. Cancel one task, or the whole batch by tag:

```
DELETE /api/v1/tasks/tsk_...            → 200 {"state": "cancelled"}
                                        → 409 {"error": "already_delivered"}
POST   /api/v1/tasks/cancel {"tag": "apmgr:pass-8842"}
                                        → 200 {"cancelled": 412}
```

### CR-5 Terminal-state webhook

When `:webhook_url` is configured, a terminal transition POSTs a JSON event
(`task.completed`, with `task_id`, `device_id`, `state`, `fault`,
`completed_at`), retried with backoff. With `:webhook_secret` set, the body is
signed with `x-caretaker-signature: sha256=<hmac>`. `GET /tasks/:id` remains the
reconciliation fallback.

### CR-6 Connection request

```
POST /api/v1/devices/AABBCC-Router-SN123/connection-request
→ 200 {"requested": true, "session_established": true}
→ 200 {"requested": true, "session_established": false, "reason": "auth_required"}
```

Uses the device's `Device.ManagementServer.ConnectionRequestURL` from the
TR-181 store.

### CR-7 Idempotent submission

Provide `idempotency_key`. The same key with the same payload returns the
existing task; the same key with a different payload is `409 idempotency_conflict`.

### CR-8 Device presence

```
GET  /api/v1/devices/AABBCC-Router-SN123/presence
POST /api/v1/devices/presence {"device_ids": ["...", "..."]}
→ {"last_inform": "...", "inform_interval_seconds": 86400, "reachable": true}
```

### CR-9 Throughput limits

`GET /api/v1/limits` reports `tasks_per_second`, `default_ttl_seconds` and
`retention_seconds`. Submissions past the rate limit get `429` with a
`Retry-After` header.

### CR-10 Batch submission

```
POST /api/v1/tasks/batch
{"tag": "apmgr:pass-8842",
 "tasks": [{"device_id": "...", "parameters": [...]}, {"device_id": "...", "paths": [...]}]}
→ 202 {"accepted": 412, "rejected": 3,
       "tasks": [{"device_id": "...", "task_id": "..."}, ...]}
```

One bad device does not reject the batch; the shared `tag` is what CR-4's bulk
cancel operates on.

## Telemetry

`[:caretaker, :acs, :task, :submitted]` on submit, and
`[:caretaker, :acs, :task, <state>]` on each transition
(`delivered`, `applied`, `faulted`, `expired`, `cancelled`).

## Non-parameter RPCs (Reboot / Download / FactoryReset)

The same task machinery queues CPE-directed RPCs beyond get/set:

```
POST /api/v1/devices/:device_id/tasks/reboot
POST /api/v1/devices/:device_id/tasks/factory-reset
POST /api/v1/devices/:device_id/tasks/download
{ "url": "http://f/img.bin", "file_type": "1 Firmware Upgrade Image",
  "file_size": 1048576, "delay_seconds": 0 }
→ 202 { "task_id": "tsk_...", "state": "queued" }
```

Also available in-process: `Tasks.submit_reboot/2`, `Tasks.submit_download/3`,
`Tasks.submit_factory_reset/2`. They share TTL, tag and idempotency options and
reach a terminal state via the same status/webhook path.

## Latest-known parameter cache

```
GET /api/v1/devices/:device_id/parameters
→ { "device_id": "...", "parameters": {
      "Device.DeviceInfo.SoftwareVersion": { "value": "9.9.9", "updated_at": "..." } } }
```

Values come from Informs and completed Get tasks, each with a timestamp. Reading
this warm cache avoids a CPE round-trip; fall back to `submit_get` when a value
is stale or absent. In-process: `Tasks.parameters/1`.

## Presence now includes source IP and ConnectionRequestURL

`GET /devices/:id/presence` (and `presence_bulk/1`) additionally return:

- `source_ip` — the CPE's TCP source address from its last Inform
- `connection_request_url` — as reported in the Inform
- `wan_ip` — the reported WAN IPv4, when present

This lets a consumer correlate an informing device to an external record (e.g. a
DHCP lease) by source/WAN IP.

## Connection request with authentication

Real CPEs protect their ConnectionRequestURL with Basic/Digest auth. Supply
credentials per call, or configure an ACS-wide default on `Tasks` start_link
(`connection_request_auth: %{scheme: :digest, username:, password:}`):

```
POST /api/v1/devices/:device_id/connection-request
{ "scheme": "digest", "username": "acs", "password": "..." }
→ 200 { "requested": true, "session_established": true }
```

## Inbound ACS authentication

`Caretaker.ACS.Server` can require Basic or Digest auth on inbound Informs,
configured at mount:

```elixir
{Bandit, plug: {Caretaker.ACS.Server,
  auth: %{scheme: :digest, realm: "acs", username: "u", password: "p"}}}
# or, for per-device credentials:
auth: %{scheme: :digest, realm: "acs", lookup: fn username -> {:ok, password} | :error end}
```

Unauthenticated requests get `401` with a `WWW-Authenticate` challenge. With no
`auth` configured the ACS accepts unauthenticated Informs (the default).

## Inform subscription (self-discovery)

Every Inform is broadcast; subscribe to self-populate inventory:

```elixir
{:ok, _} = Caretaker.ACS.on_inform(fn inform ->
  MyApp.Inventory.observe(inform.device_id, inform.source_ip, inform.parameter_list)
end)
```

Each Inform carries `device_id`, `events`, `parameter_list` and `source_ip`.
See `Caretaker.ACS` for the mailbox-style `subscribe_informs/0`.

## State durability

`Caretaker.ACS.Session` and `Caretaker.ACS.Tasks` are in-memory. On restart,
queued tasks, presence and learned ConnectionRequestURLs are lost until each CPE
re-informs. To survive deploys, persist `Tasks.snapshot/0` periodically and pass
it back as the `:restore` option to `Tasks` start_link; queued tasks are
re-enqueued to the Session with a fresh TTL on restore. Telemetry for all task
and queue transitions is documented in `docs/telemetry.md` as a stable contract.
