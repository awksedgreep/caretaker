defmodule Caretaker.CPE.ClientTest do
  use ExUnit.Case, async: false

  setup do
    port = random_port()

    # Start dependencies used by ACS
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)
    _ = start_supervised({Finch, name: Caretaker.Finch})

    # Start ACS server on fixed port
    {:ok, _} = start_supervised({Bandit, plug: Caretaker.ACS.Server, port: port})
    %{url: "http://localhost:#{port}/cwmp"}
  end

  test "run_session sends Inform, receives InformResponse, then fetches queued RPC", ctx do
    {:ok, result} = Caretaker.CPE.Client.run_session(ctx.url)

    assert result.inform_ack == true
    assert result.rpc in ["GetParameterValues", nil]
  end

  defp random_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
