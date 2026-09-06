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
