# Telemetry Reference

This document lists telemetry events emitted by Caretaker components and their metadata.

All events are prefixed with `:caretaker`.

## ACS (Server)

- [:caretaker, :acs, :request, :start]
  - measurements: %{}
  - metadata: %{path, method}
- [:caretaker, :acs, :request, :stop]
  - measurements: %{duration}
  - metadata: %{status}
- [:caretaker, :acs, :inform, :received]
  - measurements: %{}
  - metadata: %{device_id}
- [:caretaker, :acs, :queue, :enqueue]
  - measurements: %{}
  - metadata: %{rpc}
- [:caretaker, :acs, :queue, :dequeue]
  - measurements: %{}
  - metadata: %{rpc}
- [:caretaker, :tr181, :store, :updated]
  - measurements: %{}
  - metadata: %{device: %{oui, product_class, serial}}

## TR-069 RPC

- [:caretaker, :tr069, :rpc, :encode, :start|:stop]
  - measurements: %{duration?}
  - metadata: %{rpc}
- [:caretaker, :tr069, :rpc, :decode, :start|:stop]
  - measurements: %{duration?}
  - metadata: %{rpc, error?}

## CPE Client

- [:caretaker, :cpe_client, :session, :start|:stop]
  - measurements: %{}
  - metadata: %{acs_url, cwmp_id?, cwmp_ns?, rpc?}
- [:caretaker, :cpe_client, :http, :request, :start|:stop]
  - measurements: %{}
  - metadata: %{method, url, status? | error?}
- [:caretaker, :cpe_client, :retry]
  - measurements: %{}
  - metadata: %{attempt, backoff_ms}
- [:caretaker, :cpe_client, :rpc, :received]
  - measurements: %{}
  - metadata: %{acs_url, cwmp_ns, rpc}
- [:caretaker, :cpe_client, :rpc, :responded]
  - measurements: %{}
  - metadata: %{acs_url, cwmp_ns, rpc}
- [:caretaker, :cpe_client, :rpc, :unsupported]
  - measurements: %{}
  - metadata: %{rpc}
- [:caretaker, :cpe_client, :error]
  - measurements: %{}
  - metadata: %{acs_url, cwmp_id?, reason}
- [:caretaker, :cpe_client, :params, :updated]
  - measurements: %{}
  - metadata: %{count}
- [:caretaker, :cpe_client, :attrs, :updated]
  - measurements: %{}
  - metadata: %{count}

## Firmware Simulator

- [:caretaker, :firmware, :download, :start]
  - measurements: %{}
  - metadata: %{url, command_key, current_version, target_version}
- [:caretaker, :firmware, :download, :complete]
  - measurements: %{duration_ms}
  - metadata: %{url, command_key, target_version}
- [:caretaker, :firmware, :download, :failed]
  - measurements: %{}
  - metadata: %{url, command_key, fault_code, fault_string}
- [:caretaker, :firmware, :reboot, :start]
  - measurements: %{}
  - metadata: %{command_key, current_version, target_version}
- [:caretaker, :firmware, :reboot, :complete]
  - measurements: %{}
  - metadata: %{command_key, new_version}

## Fleet Management

- [:caretaker, :fleet, :init]
  - measurements: %{count}
  - metadata: %{acs_url, profiles}
- [:caretaker, :fleet, :spawned]
  - measurements: %{count}
  - metadata: %{acs_url}
- [:caretaker, :fleet, :stopped]
  - measurements: %{count}
  - metadata: %{}
- [:caretaker, :fleet, :device, :spawned]
  - measurements: %{}
  - metadata: %{serial_number, profile}

## Dynamic Behavior

- [:caretaker, :cpe, :param, :changed]
  - measurements: %{}
  - metadata: %{path, old_value, new_value}
- [:caretaker, :cpe, :periodic_inform, :scheduled]
  - measurements: %{delay_ms}
  - metadata: %{interval, jitter}
- [:caretaker, :cpe, :periodic_inform, :triggered]
  - measurements: %{}
  - metadata: %{pending_events}

## Connection Request Server

- [:caretaker, :connection_request, :server, :started]
  - measurements: %{port}
  - metadata: %{host}
- [:caretaker, :connection_request, :received]
  - measurements: %{}
  - metadata: %{serial}
- [:caretaker, :connection_request, :triggered]
  - measurements: %{}
  - metadata: %{serial}
- [:caretaker, :connection_request, :not_found]
  - measurements: %{}
  - metadata: %{serial}

## Usage

Attach a handler in tests or your application:

```elixir
:telemetry.attach_many(
  {:caretaker, self()},
  [
    [:caretaker, :acs, :request, :start],
    [:caretaker, :cpe_client, :session, :stop]
  ],
  fn event, meas, meta, _cfg -> Logger.debug("telemetry=#{inspect({event, meas, meta})}") end,
  %{}
)
```
