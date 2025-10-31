defmodule Caretaker.CPE.ClientTest do
  use ExUnit.Case, async: false

  @port 4051
  @url "http://localhost:4051/cwmp"

  setup do
    # Start dependencies used by ACS
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)
    _ = start_supervised({Finch, name: Caretaker.Finch})

    # Start ACS server on fixed port
    {:ok, _} = start_supervised({Bandit, plug: Caretaker.ACS.Server, port: @port})
    :ok
  end

  test "run_session sends Inform, receives InformResponse, then fetches queued RPC" do
    {:ok, result} = Caretaker.CPE.Client.run_session(@url)

    assert result.inform_ack == true
    assert result.rpc in ["GetParameterValues", nil]
  end
end
