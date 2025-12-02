defmodule Caretaker.CPE.ClientLoadTest do
  use ExUnit.Case, async: false

  @moduletag :load_test
  @port 4052
  @url "http://localhost:4052/cwmp"

  setup do
    # Start dependencies
    _ = start_supervised(Caretaker.PubSub)
    _ = start_supervised(Caretaker.ACS.Session)
    _ = start_supervised({Finch, name: Caretaker.Finch})
    _ = start_supervised({Bandit, plug: Caretaker.ACS.Server, port: @port})
    :ok
  end

  @tag timeout: 120_000
  test "spawn 100 concurrent clients and measure memory" do
    mem_before = :erlang.memory(:total)
    proc_before = length(Process.list())

    # Spawn 100 concurrent client sessions
    tasks =
      for i <- 1..100 do
        Task.async(fn ->
          {:ok, _result} =
            Caretaker.CPE.Client.run_session(@url,
              device_id: %{
                manufacturer: "LoadTest",
                oui: "LOAD01",
                product_class: "TestDevice",
                serial_number: "SN-#{String.pad_leading("#{i}", 5, "0")}"
              },
              timeout: 10_000,
              max_retries: 1
            )
        end)
      end

    # Wait for all to complete
    results = Task.await_many(tasks, 60_000)

    mem_after = :erlang.memory(:total)
    proc_after = length(Process.list())

    # Calculate overhead
    mem_delta_mb = (mem_after - mem_before) / (1024 * 1024)
    proc_delta = proc_after - proc_before
    mem_per_session_kb = (mem_after - mem_before) / length(results) / 1024

    IO.puts("\n=== Load Test Results ===")
    IO.puts("Clients: #{length(results)}")
    IO.puts("Successful: #{Enum.count(results, fn {:ok, _} -> true; _ -> false end)}")
    IO.puts("Memory before: #{Float.round(mem_before / (1024 * 1024), 2)} MB")
    IO.puts("Memory after: #{Float.round(mem_after / (1024 * 1024), 2)} MB")
    IO.puts("Memory delta: #{Float.round(mem_delta_mb, 2)} MB")
    IO.puts("Memory per session: ~#{Float.round(mem_per_session_kb, 2)} KB")
    IO.puts("Processes before: #{proc_before}")
    IO.puts("Processes after: #{proc_after}")
    IO.puts("Process delta: #{proc_delta}")

    # All should succeed
    assert Enum.all?(results, fn
             {:ok, %{inform_ack: true}} -> true
             _ -> false
           end)

    # Memory should be reasonable (< 50 MB delta for 100 clients)
    # Note: ~388 KB/session is acceptable for test clients with full XML parsing
    assert mem_delta_mb < 50.0,
           "Memory usage too high: #{Float.round(mem_delta_mb, 2)} MB for 100 clients"
  end

  @tag timeout: 300_000
  @tag :skip
  test "spawn 1000 concurrent clients (stress test)" do
    mem_before = :erlang.memory(:total)

    # Spawn in batches to avoid overwhelming scheduler
    batch_size = 100
    total = 1000

    results =
      for batch_start <- 0..(total - 1)//batch_size do
        batch_end = min(batch_start + batch_size - 1, total - 1)

        tasks =
          for i <- batch_start..batch_end do
            Task.async(fn ->
              Caretaker.CPE.Client.run_session(@url,
                device_id: %{
                  manufacturer: "StressTest",
                  oui: "STRESS",
                  product_class: "TestDevice",
                  serial_number: "SN-#{String.pad_leading("#{i}", 5, "0")}"
                },
                timeout: 15_000,
                max_retries: 2
              )
            end)
          end

        Task.await_many(tasks, 120_000)
      end
      |> List.flatten()

    mem_after = :erlang.memory(:total)
    mem_delta_mb = (mem_after - mem_before) / (1024 * 1024)
    success_count = Enum.count(results, fn {:ok, _} -> true; _ -> false end)

    IO.puts("\n=== Stress Test Results ===")
    IO.puts("Total clients: #{length(results)}")
    IO.puts("Successful: #{success_count}")
    IO.puts("Failed: #{length(results) - success_count}")
    IO.puts("Memory delta: #{Float.round(mem_delta_mb, 2)} MB")
    IO.puts("Memory per session: ~#{Float.round(mem_delta_mb / length(results) * 1024, 2)} KB")

    # At least 95% should succeed
    assert success_count / length(results) >= 0.95,
           "Too many failures: #{length(results) - success_count}/#{length(results)}"
  end
end
