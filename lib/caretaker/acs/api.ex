defmodule Caretaker.ACS.API do
  @moduledoc """
  Northbound HTTP API for external TR-069 change agents.

  A JSON REST surface over `Caretaker.ACS.Tasks` for submitting, tracking,
  cancelling and expiring TR-069 changes, plus device presence, connection
  requests, batch submission and documented throughput limits.

  This is a Plug router; it does not start a web server on its own. Mount it
  behind Bandit alongside a running `Caretaker.ACS.Tasks` (and `Session`):

      children = [
        Caretaker.ACS.Session,
        Caretaker.ACS.Tasks,
        {Bandit, plug: Caretaker.ACS.API, port: 8090}
      ]

  ## Endpoints (all under `/api/v1`)

    - `POST /devices/:device_id/tasks/set-parameters` — CR-1
    - `POST /devices/:device_id/tasks/get-parameters` — CR-2
    - `GET  /tasks/:task_id` — CR-3
    - `DELETE /tasks/:task_id` — CR-4 (cancel one)
    - `POST /tasks/cancel` `{tag}` — CR-4 (bulk cancel / kill switch)
    - `POST /tasks/batch` — CR-10
    - `POST /devices/:device_id/connection-request` — CR-6
    - `GET  /devices/:device_id/presence` — CR-8
    - `POST /devices/presence` `{device_ids}` — CR-8 (bulk)
    - `GET  /limits` — CR-9

  `device_id` is `OUI-ProductClass-SerialNumber` (the serial may contain dashes).
  """

  use Plug.Router

  alias Caretaker.ACS.Tasks

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  # -- CR-1: submit SetParameterValues --
  post "/api/v1/devices/:device_id/tasks/set-parameters" do
    with_rate_limit(conn, fn conn ->
      params = conn.body_params["parameters"]
      opts = task_opts(conn.body_params)

      cond do
        not is_list(params) ->
          error(conn, 400, "invalid_request", "\"parameters\" must be a list")

        true ->
          submit_response(conn, Tasks.submit_set(device_id, params, opts))
      end
    end)
  end

  # -- CR-2: submit GetParameterValues --
  post "/api/v1/devices/:device_id/tasks/get-parameters" do
    with_rate_limit(conn, fn conn ->
      paths = conn.body_params["paths"]

      if is_list(paths) do
        submit_response(conn, Tasks.submit_get(device_id, paths, task_opts(conn.body_params)))
      else
        error(conn, 400, "invalid_request", "\"paths\" must be a list")
      end
    end)
  end

  # -- CR-40: submit Reboot / Download / FactoryReset --
  post "/api/v1/devices/:device_id/tasks/reboot" do
    with_rate_limit(conn, fn conn ->
      submit_response(conn, Tasks.submit_reboot(device_id, task_opts(conn.body_params)))
    end)
  end

  post "/api/v1/devices/:device_id/tasks/factory-reset" do
    with_rate_limit(conn, fn conn ->
      submit_response(conn, Tasks.submit_factory_reset(device_id, task_opts(conn.body_params)))
    end)
  end

  post "/api/v1/devices/:device_id/tasks/download" do
    with_rate_limit(conn, fn conn ->
      spec = Map.take(conn.body_params, ~w(url file_type file_size delay_seconds target_file_name username password command_key))
      submit_response(conn, Tasks.submit_download(device_id, spec, task_opts(conn.body_params)))
    end)
  end

  # -- CR-45: latest-known parameter cache --
  get "/api/v1/devices/:device_id/parameters" do
    json(conn, 200, %{"device_id" => device_id, "parameters" => Tasks.parameters(device_id)})
  end

  # -- CR-3: task status --
  get "/api/v1/tasks/:task_id" do
    case Tasks.get(task_id) do
      {:ok, task} -> json(conn, 200, Tasks.to_status(task))
      {:error, :not_found} -> error(conn, 404, "not_found", "no such task")
    end
  end

  # -- CR-4: cancel one task --
  delete "/api/v1/tasks/:task_id" do
    case Tasks.cancel(task_id) do
      {:ok, :cancelled} ->
        json(conn, 200, %{"task_id" => task_id, "state" => "cancelled"})

      {:error, :not_found} ->
        error(conn, 404, "not_found", "no such task")

      {:error, {:already, state}} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(409, Jason.encode!(%{"error" => "already_#{state}", "state" => Atom.to_string(state)}))
    end
  end

  # -- CR-4: bulk cancel by tag (kill switch) --
  post "/api/v1/tasks/cancel" do
    case conn.body_params["tag"] do
      tag when is_binary(tag) and tag != "" ->
        {:ok, count} = Tasks.cancel_by_tag(tag)
        json(conn, 200, %{"tag" => tag, "cancelled" => count})

      _ ->
        error(conn, 400, "invalid_request", "\"tag\" is required")
    end
  end

  # -- CR-10: batch submit --
  post "/api/v1/tasks/batch" do
    with_rate_limit(conn, fn conn ->
      tasks = conn.body_params["tasks"]
      tag = conn.body_params["tag"]

      if is_list(tasks) do
        results = Enum.map(tasks, &batch_one(&1, tag))
        accepted = Enum.count(results, &Map.has_key?(&1, "task_id"))

        json(conn, 202, %{
          "accepted" => accepted,
          "rejected" => length(results) - accepted,
          "tasks" => results
        })
      else
        error(conn, 400, "invalid_request", "\"tasks\" must be a list")
      end
    end)
  end

  # -- CR-6: connection request --
  post "/api/v1/devices/:device_id/connection-request" do
    opts =
      []
      |> put_opt(:username, conn.body_params["username"])
      |> put_opt(:password, conn.body_params["password"])
      |> put_opt(:scheme, cr_scheme(conn.body_params["scheme"]))

    result = Tasks.connection_request(device_id, opts)
    status = if result["requested"], do: 200, else: 502
    json(conn, status, result)
  end

  # -- CR-8: presence (single) --
  get "/api/v1/devices/:device_id/presence" do
    json(conn, 200, Tasks.presence(device_id))
  end

  # -- CR-8: presence (bulk) --
  post "/api/v1/devices/presence" do
    case conn.body_params["device_ids"] do
      ids when is_list(ids) ->
        json(conn, 200, %{"devices" => Tasks.presence_bulk(ids)})

      _ ->
        error(conn, 400, "invalid_request", "\"device_ids\" must be a list")
    end
  end

  # -- CR-9: documented limits --
  get "/api/v1/limits" do
    json(conn, 200, Tasks.limits())
  end

  match _ do
    error(conn, 404, "not_found", "unknown endpoint")
  end

  @doc "Child spec to start Bandit with this router."
  @spec child_spec(keyword()) :: {Bandit, keyword()}
  def child_spec(opts \\ []) do
    {Bandit,
     plug: __MODULE__,
     port: Keyword.get(opts, :port, 8090),
     scheme: Keyword.get(opts, :scheme, :http)}
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp task_opts(body) when is_map(body) do
    []
    |> put_opt(:ttl_ms, ttl_ms(body))
    |> put_opt(:tag, body["tag"])
    |> put_opt(:idempotency_key, body["idempotency_key"])
  end

  defp task_opts(_), do: []

  defp put_opt(opts, _k, nil), do: opts
  defp put_opt(opts, k, v), do: [{k, v} | opts]

  defp ttl_ms(%{"ttl_seconds" => s}) when is_integer(s) and s >= 0, do: s * 1000
  defp ttl_ms(_), do: nil

  defp cr_scheme("basic"), do: :basic
  defp cr_scheme("digest"), do: :digest
  defp cr_scheme(_), do: nil

  defp submit_response(conn, result) do
    case result do
      {:ok, task_id} ->
        json(conn, 202, %{"task_id" => task_id, "state" => "queued"})

      {:error, :idempotency_conflict} ->
        error(conn, 409, "idempotency_conflict", "key reused with a different payload")

      {:error, :session_unavailable} ->
        error(conn, 503, "session_unavailable", "ACS session store is not running")

      {:error, :invalid_device_id} ->
        error(conn, 400, "invalid_device_id", "device_id must be OUI-ProductClass-SerialNumber")

      {:error, reason} ->
        error(conn, 400, "invalid_request", to_string(reason))
    end
  end

  defp batch_one(spec, tag) when is_map(spec) do
    device_id = spec["device_id"]
    opts = task_opts(Map.put(spec, "tag", spec["tag"] || tag))

    result =
      cond do
        is_list(spec["parameters"]) -> Tasks.submit_set(device_id, spec["parameters"], opts)
        is_list(spec["paths"]) -> Tasks.submit_get(device_id, spec["paths"], opts)
        true -> {:error, :invalid_request}
      end

    case result do
      {:ok, task_id} -> %{"device_id" => device_id, "task_id" => task_id}
      {:error, reason} -> %{"device_id" => device_id, "error" => to_string(reason)}
    end
  end

  defp batch_one(_spec, _tag), do: %{"error" => "invalid_request"}

  # Apply the submission rate limit (CR-9): 429 + Retry-After on breach.
  defp with_rate_limit(conn, fun) do
    case Tasks.take_token() do
      :ok ->
        fun.(conn)

      {:error, {:rate_limited, retry_after}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{"error" => "rate_limited", "retry_after" => retry_after}))
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp error(conn, status, code, message) do
    json(conn, status, %{"error" => code, "message" => message})
  end
end
