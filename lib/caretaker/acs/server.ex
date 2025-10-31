defmodule Caretaker.ACS.Server do
  @moduledoc """
  Minimal ACS Plug router.

  Note: Library code does not start Bandit by default. Use child_spec in your app.
  """

  use Plug.Router
  require Logger

  plug(:match)
  plug(:dispatch)

  post "/cwmp" do
    start = System.monotonic_time()

    :telemetry.execute([:caretaker, :acs, :request, :start], %{}, %{path: "/cwmp", method: "POST"})

    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Logger.debug("Received ACS request with bytes=#{byte_size(body)}")

    # TODO: Parse SOAP via Lather and route to the correct RPC decoder.
    # Placeholder response to avoid returning invalid SOAP for now.
    conn =
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.send_resp(204, "")

    duration = System.monotonic_time() - start

    :telemetry.execute([:caretaker, :acs, :request, :stop], %{duration: duration}, %{
      status: conn.status
    })

    conn
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "Not Found")
  end

  @doc "Child spec to start Bandit with this router"
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    bandit_opts = [
      plug: __MODULE__,
      port: Keyword.get(opts, :port, 4000),
      scheme: Keyword.get(opts, :scheme, :http)
    ]

    {Bandit, bandit_opts}
  end
end
