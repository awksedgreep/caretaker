defmodule Caretaker.Integration.FleetSessionTest do
  @moduledoc """
  Exercises the Fleet session runner (#15) end to end: a fleet of simulated
  devices runs real CWMP sessions against a live ACS and the sessions are
  counted.
  """
  use ExUnit.Case, async: false

  alias Caretaker.CPE.Fleet

  setup do
    port = 4000 + rem(System.unique_integer([:positive]), 1000)
    start_supervised!(Caretaker.PubSub)
    start_supervised!(Caretaker.ACS.Session)
    _ = start_supervised({Finch, name: Caretaker.Finch})
    start_supervised!({Bandit, plug: Caretaker.ACS.Server, port: port})
    %{acs_url: "http://localhost:#{port}/cwmp"}
  end

  test "run_all_sessions drives real CWMP sessions and counts them", %{acs_url: acs_url} do
    {:ok, fleet} =
      Fleet.start_link(acs_url: acs_url, count: 3, oui_prefix: "FLEET0")

    {:ok, 3} = Fleet.spawn_devices(fleet)

    # Sessions have not run yet
    stats = Fleet.stats(fleet)
    assert stats.total_sessions == 0

    {:ok, 3} = Fleet.run_all_sessions(fleet, ["1 BOOT"])

    # Wait for the background sessions to complete
    assert eventually(fn -> Fleet.stats(fleet).total_sessions == 3 end)

    stats = Fleet.stats(fleet)
    assert stats.connected == 3
    assert stats.total_sessions == 3

    Fleet.stop_all(fleet)
  end

  test "run_session runs a single device session", %{acs_url: acs_url} do
    {:ok, fleet} = Fleet.start_link(acs_url: acs_url, count: 2, oui_prefix: "FLEET0")
    {:ok, 2} = Fleet.spawn_devices(fleet)

    assert :ok = Fleet.run_session(fleet, "FLEET0-000001", ["2 PERIODIC"])
    assert eventually(fn -> Fleet.stats(fleet).total_sessions == 1 end)

    assert {:error, :not_found} = Fleet.run_session(fleet, "does-not-exist")

    Fleet.stop_all(fleet)
  end

  defp eventually(fun, retries \\ 50) do
    cond do
      fun.() -> true
      retries == 0 -> false
      true ->
        Process.sleep(20)
        eventually(fun, retries - 1)
    end
  end
end
