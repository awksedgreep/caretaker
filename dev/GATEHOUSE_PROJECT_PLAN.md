# Gatehouse: ACS Web Interface Project Plan

A Phoenix LiveView application for managing TR-069/TR-369 devices using the Caretaker library.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Gatehouse (Phoenix)                        │
├─────────────────────────────────────────────────────────────────┤
│  LiveView UI          REST API          GraphQL API             │
│       │                   │                  │                  │
│       └───────────────────┴──────────────────┘                  │
│                           │                                     │
│                    Gatehouse.Core                                  │
│            (Business logic, contexts)                           │
│                           │                                     │
├───────────────────────────┼─────────────────────────────────────┤
│                           │                                     │
│  ┌─────────────────┐  ┌───┴───────────────┐  ┌───────────────┐ │
│  │ Postgres/       │  │    Caretaker      │  │   PubSub      │ │
│  │ TimescaleDB     │  │    Library        │  │   (Real-time) │ │
│  └─────────────────┘  └───────────────────┘  └───────────────┘ │
│                                │                                │
└────────────────────────────────┼────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │      CPE Devices        │
                    │   (TR-069 / TR-369)     │
                    └─────────────────────────┘
```

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Phoenix 1.7+ |
| UI | LiveView + Components |
| CSS | Tailwind CSS |
| Database | PostgreSQL 15+ with TimescaleDB |
| Protocol | Caretaker library (TR-069/TR-369) |
| Auth | phx_gen_auth + optional SSO |
| API | REST + GraphQL (Absinthe) |
| Background Jobs | Oban |
| Caching | ETS / Cachex |
| Telemetry | OpenTelemetry + Prometheus |

---

## Phase 1: Project Foundation

### Goal
Set up the Phoenix project with core infrastructure.

### Tasks

- [ ] Create Phoenix project: `mix phx.new gatehouse --live`
- [ ] Add dependencies to mix.exs:
  ```elixir
  {:caretaker, "~> 0.2"},
  {:timescaledb, "~> 0.1"},  # or raw SQL migrations
  {:oban, "~> 2.17"},
  {:cachex, "~> 3.6"},
  {:absinthe, "~> 1.7"},
  {:absinthe_phoenix, "~> 2.0"}
  ```
- [ ] Configure TimescaleDB in repo
- [ ] Set up Tailwind with custom theme
- [ ] Create base layout with navigation shell
- [ ] Set up authentication (phx.gen.auth)
- [ ] Configure Oban for background jobs
- [ ] Set up PubSub topics structure
- [ ] Add Caretaker to supervision tree
- [ ] Create telemetry handlers

### Database Setup

```sql
-- Enable TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Files to Create

```
lib/gatehouse/
├── application.ex          # Supervision tree with Caretaker
├── repo.ex                 # Ecto Repo with TimescaleDB
├── pubsub.ex              # PubSub topic helpers
└── telemetry.ex           # Telemetry event handlers

lib/gatehouse_web/
├── router.ex              # Routes
├── layouts/               # App shell, navigation
└── components/            # Core UI components
```

---

## Phase 2: Database Schema

### Goal
Design and implement the database schema for devices, parameters, events, and logs.

### Tasks

- [ ] Design and implement core migrations
- [ ] Create Ecto schemas
- [ ] Set up TimescaleDB hypertables
- [ ] Configure compression policies
- [ ] Create continuous aggregates
- [ ] Add retention policies
- [ ] Seed development data

### Schema Design

#### Regular Tables

```elixir
# devices - Core device registry
create table(:devices, primary_key: false) do
  add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
  add :serial_number, :string, null: false
  add :oui, :string, null: false
  add :product_class, :string
  add :manufacturer, :string
  add :model_name, :string
  add :software_version, :string
  add :hardware_version, :string

  # Protocol
  add :protocol, :string, null: false  # "cwmp" | "usp"
  add :endpoint_id, :string            # USP endpoint ID

  # Status
  add :status, :string, default: "offline"  # online, offline, upgrading, error
  add :last_contact, :utc_datetime_usec
  add :last_inform, :utc_datetime_usec
  add :ip_address, :string

  # Current state (denormalized for fast queries)
  add :current_params, :map, default: %{}

  # Metadata
  add :tags, {:array, :string}, default: []
  add :notes, :text
  add :group_id, references(:groups, type: :uuid, on_delete: :nilify_all)

  timestamps(type: :utc_datetime_usec)
end

create unique_index(:devices, [:serial_number, :oui])
create index(:devices, [:status])
create index(:devices, [:protocol])
create index(:devices, [:group_id])
create index(:devices, [:tags], using: :gin)

# groups - Device groupings
create table(:groups, primary_key: false) do
  add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
  add :name, :string, null: false
  add :description, :text
  add :parent_id, references(:groups, type: :uuid, on_delete: :nilify_all)
  add :dynamic_query, :map  # For auto-membership based on criteria

  timestamps(type: :utc_datetime_usec)
end

# profiles - Provisioning templates
create table(:profiles, primary_key: false) do
  add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
  add :name, :string, null: false
  add :description, :text
  add :device_matcher, :map  # Criteria for auto-apply
  add :parameters, :map, null: false  # Parameter values to set
  add :priority, :integer, default: 0
  add :enabled, :boolean, default: true

  timestamps(type: :utc_datetime_usec)
end

# jobs - Bulk operations
create table(:jobs, primary_key: false) do
  add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
  add :type, :string, null: false  # firmware_upgrade, parameter_set, reboot, etc
  add :status, :string, default: "pending"  # pending, running, completed, failed, cancelled
  add :target_type, :string  # all, group, device_list, query
  add :target_spec, :map
  add :payload, :map
  add :progress, :map, default: %{total: 0, completed: 0, failed: 0}
  add :started_at, :utc_datetime_usec
  add :completed_at, :utc_datetime_usec
  add :created_by_id, references(:users, type: :id, on_delete: :nilify_all)

  timestamps(type: :utc_datetime_usec)
end

# job_results - Per-device job results
create table(:job_results, primary_key: false) do
  add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
  add :job_id, references(:jobs, type: :uuid, on_delete: :delete_all), null: false
  add :device_id, references(:devices, type: :uuid, on_delete: :delete_all), null: false
  add :status, :string, default: "pending"  # pending, success, failed, skipped
  add :result, :map
  add :error, :text
  add :started_at, :utc_datetime_usec
  add :completed_at, :utc_datetime_usec

  timestamps(type: :utc_datetime_usec)
end

create index(:job_results, [:job_id])
create index(:job_results, [:device_id])
create unique_index(:job_results, [:job_id, :device_id])

# audit_log - Compliance and history
create table(:audit_log, primary_key: false) do
  add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()")
  add :action, :string, null: false  # device.created, param.set, job.started, etc
  add :actor_type, :string, null: false  # user, system, device, job
  add :actor_id, :string
  add :target_type, :string  # device, group, profile, job
  add :target_id, :uuid
  add :changes, :map  # Before/after diff
  add :metadata, :map
  add :ip_address, :string

  add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
end

create index(:audit_log, [:target_type, :target_id])
create index(:audit_log, [:actor_type, :actor_id])
create index(:audit_log, [:inserted_at])
```

#### TimescaleDB Hypertables

```elixir
# param_history - Parameter values over time
create table(:param_history, primary_key: false) do
  add :time, :utc_datetime_usec, null: false
  add :device_id, :uuid, null: false
  add :path, :string, null: false
  add :value, :map, null: false  # JSONB for any type
  add :source, :string  # inform, set, get, job
end

execute """
  SELECT create_hypertable('param_history', 'time',
    chunk_time_interval => INTERVAL '1 day'
  );
"""

execute """
  CREATE INDEX ON param_history (device_id, path, time DESC);
"""

execute """
  ALTER TABLE param_history SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id, path',
    timescaledb.compress_orderby = 'time DESC'
  );
"""

execute """
  SELECT add_compression_policy('param_history', INTERVAL '7 days');
"""

# events - Device events (boot, connect, disconnect, etc)
create table(:events, primary_key: false) do
  add :time, :utc_datetime_usec, null: false
  add :device_id, :uuid, null: false
  add :event_type, :string, null: false
  add :event_code, :string
  add :data, :map
end

execute """
  SELECT create_hypertable('events', 'time',
    chunk_time_interval => INTERVAL '1 day'
  );
"""

create index(:events, [:device_id, :time])
create index(:events, [:event_type, :time])

# logs - System and device logs
create table(:logs, primary_key: false) do
  add :time, :utc_datetime_usec, null: false
  add :level, :string, null: false
  add :source, :string, null: false
  add :device_id, :uuid
  add :job_id, :uuid
  add :user_id, :integer
  add :message, :text, null: false
  add :metadata, :map
end

execute """
  SELECT create_hypertable('logs', 'time',
    chunk_time_interval => INTERVAL '1 day'
  );
"""

create index(:logs, [:device_id, :time])
create index(:logs, [:level, :time])

execute """
  SELECT add_retention_policy('logs', INTERVAL '90 days');
"""
```

#### Continuous Aggregates

```elixir
execute """
  CREATE MATERIALIZED VIEW param_hourly
  WITH (timescaledb.continuous) AS
  SELECT
    time_bucket('1 hour', time) AS bucket,
    device_id,
    path,
    avg((value->>'v')::double precision) FILTER (WHERE jsonb_typeof(value->'v') = 'number') AS avg_val,
    min((value->>'v')::double precision) FILTER (WHERE jsonb_typeof(value->'v') = 'number') AS min_val,
    max((value->>'v')::double precision) FILTER (WHERE jsonb_typeof(value->'v') = 'number') AS max_val,
    last(value, time) AS last_value
  FROM param_history
  GROUP BY bucket, device_id, path
  WITH NO DATA;
"""

execute """
  SELECT add_continuous_aggregate_policy('param_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
  );
"""
```

---

## Phase 3: Caretaker Integration

### Goal
Integrate the Caretaker library and wire up device communication.

### Tasks

- [ ] Configure Caretaker ACS server in supervision tree
- [ ] Create device session manager
- [ ] Implement PubSub bridge for real-time updates
- [ ] Handle Inform processing and device registration
- [ ] Implement parameter sync to database
- [ ] Add USP Controller support
- [ ] Create device connection tracking

### Key Modules

```elixir
defmodule Gatehouse.DeviceManager do
  @moduledoc """
  Bridges Caretaker events to Gatehouse's database and PubSub.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Subscribe to Caretaker telemetry
    :telemetry.attach_many(
      "gatehouse-device-manager",
      [
        [:caretaker, :acs, :inform, :received],
        [:caretaker, :acs, :session, :started],
        [:caretaker, :acs, :session, :ended],
        [:caretaker, :usp, :agent, :registered],
        [:caretaker, :usp, :agent, :message]
      ],
      &handle_telemetry/4,
      nil
    )

    {:ok, %{}}
  end

  defp handle_telemetry([:caretaker, :acs, :inform, :received], _measurements, metadata, _config) do
    # Upsert device, record params, broadcast update
    device = upsert_device_from_inform(metadata.inform)
    record_parameters(device, metadata.inform.parameter_list)
    broadcast_device_update(device)
  end

  # ... more handlers
end
```

```elixir
defmodule Gatehouse.ProtocolHandler do
  @moduledoc """
  Handles outgoing commands to devices via appropriate protocol.
  """

  def get_parameters(device, paths) do
    case device.protocol do
      "cwmp" -> get_via_cwmp(device, paths)
      "usp" -> get_via_usp(device, paths)
    end
  end

  def set_parameters(device, params) do
    case device.protocol do
      "cwmp" -> set_via_cwmp(device, params)
      "usp" -> set_via_usp(device, params)
    end
  end

  # Unified interface, protocol-specific implementation
end
```

---

## Phase 4: Core UI - Device Management

### Goal
Build the primary device management interface with LiveView.

### Tasks

- [ ] Dashboard with fleet overview
- [ ] Device list with filtering/sorting
- [ ] Device detail view with parameter tree
- [ ] Real-time status updates
- [ ] Quick actions (reboot, refresh, etc)
- [ ] Device search (full-text)
- [ ] Device groups management

### LiveView Components

```
lib/gatehouse_web/live/
├── dashboard_live.ex           # Fleet overview
├── device_live/
│   ├── index.ex               # Device list
│   ├── show.ex                # Device detail
│   ├── form_component.ex      # Edit device metadata
│   └── components/
│       ├── device_card.ex     # Card in list view
│       ├── param_tree.ex      # Parameter browser
│       ├── status_badge.ex    # Online/offline badge
│       └── quick_actions.ex   # Action buttons
├── group_live/
│   ├── index.ex
│   └── show.ex
└── components/
    ├── data_table.ex          # Sortable, filterable table
    ├── search_input.ex        # Live search
    ├── time_ago.ex            # "5 minutes ago"
    └── flash_group.ex         # Toast notifications
```

### Dashboard Wireframe

```
┌─────────────────────────────────────────────────────────────────┐
│ Gatehouse                                    [Search...] [Profile] │
├──────────┬──────────────────────────────────────────────────────┤
│          │                                                      │
│ Dashboard│  Fleet Overview                                      │
│ Devices  │  ┌──────────┬──────────┬──────────┬──────────┐      │
│ Groups   │  │ 12,847   │    23    │   156    │  45/sec  │      │
│ Jobs     │  │ Online   │ Offline  │ Upgrading│ Msg Rate │      │
│ Profiles │  └──────────┴──────────┴──────────┴──────────┘      │
│ ──────── │                                                      │
│ Logs     │  Recent Activity                         [View All]  │
│ Settings │  ┌───────────────────────────────────────────────┐  │
│          │  │ Router-4521 came online              2s ago   │  │
│          │  │ Firmware upgrade complete (45)       1m ago   │  │
│          │  │ Alert: High errors on GW-89          5m ago   │  │
│          │  └───────────────────────────────────────────────┘  │
│          │                                                      │
│          │  Active Jobs                                         │
│          │  ┌───────────────────────────────────────────────┐  │
│          │  │ ████████████░░░░ FW 2.1.0 → EU         78%   │  │
│          │  │ ██░░░░░░░░░░░░░░ Config push → All     12%   │  │
│          │  └───────────────────────────────────────────────┘  │
│          │                                                      │
└──────────┴──────────────────────────────────────────────────────┘
```

### Device List Wireframe

```
┌─────────────────────────────────────────────────────────────────┐
│ Devices                                          [+ Add Device] │
├─────────────────────────────────────────────────────────────────┤
│ [Search devices...]  [Status ▾] [Model ▾] [Group ▾] [Protocol ▾]│
├─────────────────────────────────────────────────────────────────┤
│ □  Serial        Model          Status    IP           Last Seen│
├─────────────────────────────────────────────────────────────────┤
│ □  ABC-12345     Router-X100    🟢 Online  192.168.1.1  2m ago  │
│ □  DEF-67890     Gateway-G200   🟢 Online  192.168.1.2  5m ago  │
│ □  GHI-11111     Router-X100    🔴 Offline 192.168.1.3  2h ago  │
│ □  JKL-22222     ONT-F300       🟡 Upgrading 10.0.0.5   1m ago  │
├─────────────────────────────────────────────────────────────────┤
│ [With selected: Reboot | Set Parameters | Add to Group | ...]  │
│                                                                 │
│ Showing 1-25 of 12,847                      [< 1 2 3 ... 514 >] │
└─────────────────────────────────────────────────────────────────┘
```

### Device Detail Wireframe

```
┌─────────────────────────────────────────────────────────────────┐
│ ← Devices    Router-X100 (ABC-12345)                  🟢 Online │
├─────────────────────────────────────────────────────────────────┤
│ [Parameters] [Events] [History] [Diagnostics] [Logs]           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Device Info                                                    │
│  ├─ Manufacturer: ACME Corp                                    │
│  ├─ Model: Router-X100                                         │
│  ├─ Serial: ABC-12345                                          │
│  ├─ Firmware: 2.0.1                               [Upgrade]    │
│  └─ Last Contact: 2 minutes ago                                │
│                                                                 │
│  Parameters                                      [Refresh All]  │
│  ▼ Device                                                       │
│    ▼ DeviceInfo                                                │
│        Manufacturer      ACME Corp               [readonly]    │
│        ModelName         Router-X100             [readonly]    │
│        SoftwareVersion   2.0.1                   [readonly]    │
│    ▶ ManagementServer                                          │
│    ▼ WiFi                                                      │
│      ▼ Radio.1                                                 │
│          Enable          true                    [Edit]        │
│          Channel         6                       [Edit]        │
│      ▶ Radio.2                                                 │
│      ▶ SSID.1                                                  │
│    ▶ Ethernet                                                  │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ [Reboot] [Factory Reset] [Run Diagnostic] [Delete]             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 5: Parameter History & Visualization

### Goal
Implement parameter history viewing and charting.

### Tasks

- [ ] Record all parameter changes to TimescaleDB
- [ ] Parameter history timeline view
- [ ] Diff view between two points in time
- [ ] Charts for numeric parameters
- [ ] Export to CSV/JSON
- [ ] Retention policy UI

### Components

```elixir
defmodule GatehouseWeb.Live.Device.HistoryComponent do
  use GatehouseWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="param-history">
      <.time_range_picker selected={@range} />

      <.chart
        :if={numeric?(@path)}
        data={@chart_data}
        type="line"
      />

      <.change_log changes={@changes}>
        <:row :let={change}>
          <.time_ago time={change.time} />
          <span><%= change.old_value %> → <%= change.new_value %></span>
          <span class="text-gray-500"><%= change.source %></span>
        </:row>
      </.change_log>
    </div>
    """
  end
end
```

---

## Phase 6: Bulk Operations & Jobs

### Goal
Implement fleet-wide operations with progress tracking.

### Tasks

- [ ] Job creation wizard
- [ ] Target selection (all, group, query, manual)
- [ ] Job queue with Oban
- [ ] Real-time progress updates
- [ ] Staged rollouts (10% → 50% → 100%)
- [ ] Rollback capability
- [ ] Job history and results

### Job Types

| Type | Description |
|------|-------------|
| `firmware_upgrade` | Push firmware to devices |
| `parameter_set` | Set parameters on multiple devices |
| `parameter_get` | Bulk parameter read |
| `reboot` | Reboot devices |
| `factory_reset` | Factory reset devices |
| `diagnostic` | Run diagnostics |
| `profile_apply` | Apply provisioning profile |

### Job Worker

```elixir
defmodule Gatehouse.Workers.DeviceJobWorker do
  use Oban.Worker, queue: :device_ops, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id, "device_id" => device_id}}) do
    job = Jobs.get_job!(job_id)
    device = Devices.get_device!(device_id)

    Jobs.update_result(job, device, %{status: "running"})
    broadcast_progress(job)

    result = execute_job_action(job, device)

    Jobs.update_result(job, device, result)
    broadcast_progress(job)

    :ok
  end

  defp execute_job_action(%{type: "reboot"}, device) do
    case Gatehouse.ProtocolHandler.reboot(device) do
      :ok -> %{status: "success"}
      {:error, reason} -> %{status: "failed", error: reason}
    end
  end

  # ... other job types
end
```

---

## Phase 7: Automation & Workflows

### Goal
Event-driven automation and provisioning workflows.

### Tasks

- [ ] Workflow builder (visual or YAML)
- [ ] Event triggers (on_boot, on_connect, on_value_change)
- [ ] Conditional logic
- [ ] Action library (set params, notify, run job)
- [ ] Workflow execution engine
- [ ] Workflow history/debugging

### Workflow Schema

```elixir
create table(:workflows, primary_key: false) do
  add :id, :uuid, primary_key: true
  add :name, :string, null: false
  add :description, :text
  add :enabled, :boolean, default: true
  add :trigger, :map, null: false  # {type: "event", event: "boot"}
  add :conditions, {:array, :map}, default: []
  add :actions, {:array, :map}, null: false
  add :priority, :integer, default: 0

  timestamps(type: :utc_datetime_usec)
end
```

### Example Workflow

```yaml
name: "New Device Provisioning"
trigger:
  type: event
  event: first_inform
conditions:
  - field: device.model
    operator: matches
    value: "Router-X*"
actions:
  - type: apply_profile
    profile: "baseline_router"
  - type: set_parameters
    params:
      Device.ManagementServer.PeriodicInformInterval: 3600
  - type: notify
    channel: slack
    message: "New device provisioned: {{device.serial}}"
```

---

## Phase 8: API Layer

### Goal
REST and GraphQL APIs for external integrations.

### Tasks

- [ ] REST API with OpenAPI spec
- [ ] GraphQL schema with Absinthe
- [ ] API authentication (API keys, JWT)
- [ ] Rate limiting
- [ ] Webhooks for events
- [ ] API documentation

### REST Endpoints

```
GET     /api/v1/devices
POST    /api/v1/devices
GET     /api/v1/devices/:id
PATCH   /api/v1/devices/:id
DELETE  /api/v1/devices/:id

GET     /api/v1/devices/:id/parameters
POST    /api/v1/devices/:id/parameters
GET     /api/v1/devices/:id/parameters/history

POST    /api/v1/devices/:id/actions/reboot
POST    /api/v1/devices/:id/actions/refresh
POST    /api/v1/devices/:id/actions/factory_reset
POST    /api/v1/devices/:id/diagnostics/:type

GET     /api/v1/jobs
POST    /api/v1/jobs
GET     /api/v1/jobs/:id
DELETE  /api/v1/jobs/:id

GET     /api/v1/groups
POST    /api/v1/groups
...

POST    /api/v1/webhooks
...
```

### GraphQL Schema

```graphql
type Device {
  id: ID!
  serialNumber: String!
  oui: String!
  manufacturer: String
  model: String
  status: DeviceStatus!
  lastContact: DateTime
  parameters: [Parameter!]!
  events(first: Int, after: String): EventConnection!
  group: Group
}

type Query {
  devices(
    filter: DeviceFilter
    first: Int
    after: String
  ): DeviceConnection!

  device(id: ID!): Device
}

type Mutation {
  setParameters(deviceId: ID!, params: [ParameterInput!]!): SetParameterResult!
  rebootDevice(id: ID!): Device!
  createJob(input: JobInput!): Job!
}

type Subscription {
  deviceUpdated(id: ID): Device!
  jobProgress(id: ID!): Job!
}
```

---

## Phase 9: Observability & Monitoring

### Goal
System monitoring, metrics, and alerting.

### Tasks

- [ ] Prometheus metrics endpoint
- [ ] Grafana dashboard templates
- [ ] Health check endpoints
- [ ] Alerting rules
- [ ] System status page
- [ ] Performance monitoring

### Metrics

```elixir
defmodule Gatehouse.Metrics do
  use Prometheus.Metric

  # Counters
  counter :gatehouse_devices_total, "Total devices registered"
  counter :gatehouse_informs_total, "Total Informs received"
  counter :gatehouse_jobs_total, "Total jobs created", [:type, :status]

  # Gauges
  gauge :gatehouse_devices_online, "Currently online devices"
  gauge :gatehouse_active_sessions, "Active device sessions"
  gauge :gatehouse_job_queue_size, "Jobs waiting in queue"

  # Histograms
  histogram :gatehouse_inform_duration_seconds, "Inform processing time"
  histogram :gatehouse_job_duration_seconds, "Job execution time", [:type]
end
```

---

## Phase 10: Multi-tenancy (Optional)

### Goal
Support multiple organizations/tenants.

### Tasks

- [ ] Organization model
- [ ] Row-level security in Postgres
- [ ] Tenant scoping in queries
- [ ] Subdomain or path-based routing
- [ ] Per-tenant configuration
- [ ] Billing integration hooks

---

## Phase 11: Polish & Production

### Goal
Production readiness.

### Tasks

- [ ] Error handling and user feedback
- [ ] Loading states and skeletons
- [ ] Keyboard shortcuts
- [ ] Dark mode
- [ ] Mobile responsiveness
- [ ] Accessibility audit
- [ ] Performance optimization
- [ ] Security audit
- [ ] Documentation
- [ ] Docker deployment
- [ ] Kubernetes manifests
- [ ] CI/CD pipeline

---

## Development Milestones

| Milestone | Phases | Description |
|-----------|--------|-------------|
| **MVP** | 1-4 | Basic device management with real-time UI |
| **Beta** | 5-7 | History, bulk ops, automation |
| **v1.0** | 8-9 | API, monitoring |
| **Enterprise** | 10-11 | Multi-tenancy, polish |

---

## Getting Started

```bash
# Create project
mix phx.new gatehouse --live

# Add dependencies (edit mix.exs)

# Setup database
mix ecto.create
mix ecto.migrate

# Start server
mix phx.server
```

---

## Open Questions

1. **Authentication**: Built-in only, or SSO/OIDC support?
2. **Multi-tenancy**: Required for v1, or later phase?
3. **Deployment target**: Docker, Kubernetes, bare metal?
4. **License**: Open source or proprietary?
5. **Name confirmation**: Gatehouse, or something else?

---

## Notes

- Each phase should be independently deployable
- Write tests as you go (aim for 80%+ coverage)
- Use LiveView streams for large lists
- Consider Phoenix.Presence for online device tracking
- Caretaker handles protocol complexity; Gatehouse focuses on UX
