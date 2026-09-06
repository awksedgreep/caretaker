defmodule Caretaker.HTTP do
  @moduledoc """
  Shared HTTP plumbing for Caretaker's outbound requests.

  Applications should add `{Finch, name: Caretaker.Finch}` to their own
  supervision tree. When that has not been done, `ensure_finch/0` starts a
  detached pool so that the pool's lifetime is not tied to whichever process
  happened to make the first request.
  """

  @finch Caretaker.Finch
  @owner Caretaker.Finch.Owner

  @doc "Name of the shared Finch pool."
  @spec finch() :: atom()
  def finch, do: @finch

  @doc """
  Ensure the shared Finch pool is running.

  The pool is started under a supervisor owned by a dedicated, unlinked
  process, so it survives the caller exiting.
  """
  @spec ensure_finch() :: :ok | {:error, term()}
  def ensure_finch do
    case Process.whereis(@finch) do
      nil -> start_detached()
      _pid -> :ok
    end
  end

  defp start_detached do
    parent = self()
    ref = make_ref()

    _owner =
      spawn(fn ->
        try do
          Process.register(self(), @owner)
        rescue
          ArgumentError ->
            # Another caller is starting the pool concurrently; let it win.
            send(parent, {ref, :ok})
            exit(:normal)
        end

        result = Supervisor.start_link([{Finch, name: @finch}], strategy: :one_for_one)
        send(parent, {ref, normalize(result)})

        case result do
          {:ok, sup} ->
            monitor = Process.monitor(sup)

            receive do
              {:DOWN, ^monitor, :process, ^sup, _} -> :ok
            end

          _ ->
            :ok
        end
      end)

    receive do
      {^ref, res} -> await_registered(res)
    after
      5_000 -> {:error, :finch_start_timeout}
    end
  end

  defp normalize({:ok, _}), do: :ok
  defp normalize({:error, {:already_started, _}}), do: :ok

  defp normalize({:error, {:shutdown, {:failed_to_start_child, _, {:already_started, _}}}}),
    do: :ok

  defp normalize({:error, reason}), do: {:error, reason}

  # A concurrent starter may still be registering the pool name.
  defp await_registered(:ok), do: await_registered(:ok, 50)
  defp await_registered(other), do: other

  defp await_registered(:ok, 0), do: {:error, :finch_not_started}

  defp await_registered(:ok, n) do
    case Process.whereis(@finch) do
      nil ->
        Process.sleep(10)
        await_registered(:ok, n - 1)

      _ ->
        :ok
    end
  end
end
