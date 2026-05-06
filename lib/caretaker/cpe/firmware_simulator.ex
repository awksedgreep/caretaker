defmodule Caretaker.CPE.FirmwareSimulator do
  @moduledoc """
  Simulates firmware upgrade lifecycle for a CPE device.

  State machine:
    idle → downloading → downloaded → applying → rebooting → upgraded

  Supports two download modes:
    - `:mock` - Simulates download with configurable delay (default)
    - `:fetch` - Actually fetches the URL to validate it exists

  ## Usage

      {:ok, sim} = FirmwareSimulator.start_link(
        current_version: "1.0.0",
        download_behavior: :mock,
        download_duration: 10_000,
        reboot_delay: 5_000
      )

      # When Download RPC received:
      {:ok, :downloading} = FirmwareSimulator.start_download(sim, %{
        url: "http://firmware.example.com/v2.0.bin",
        command_key: "upgrade-123",
        file_type: "1 Firmware Upgrade Image",
        target_version: "2.0.0"
      })

      # Check status:
      {:downloading, progress} = FirmwareSimulator.status(sim)

      # When download completes (async), state transitions to :downloaded
      # Client can then send TransferComplete

      # When Reboot RPC received:
      :ok = FirmwareSimulator.start_reboot(sim)

      # After reboot delay, state is :upgraded and version is updated
  """

  use Agent

  @type state ::
          :idle
          | :downloading
          | :downloaded
          | :applying
          | :rebooting
          | :upgraded

  @type download_behavior :: :mock | :fetch

  @type t :: %{
          state: state(),
          current_version: String.t(),
          target_version: String.t() | nil,
          download_behavior: download_behavior(),
          download_duration: non_neg_integer(),
          reboot_delay: non_neg_integer(),
          download_started_at: DateTime.t() | nil,
          download_completed_at: DateTime.t() | nil,
          command_key: String.t() | nil,
          file_type: String.t() | nil,
          url: String.t() | nil,
          fault_code: integer(),
          fault_string: String.t()
        }

  @default_download_duration 10_000
  @default_reboot_delay 5_000

  @doc """
  Start a firmware simulator agent.

  Options:
    - `current_version` - Current firmware version (default: "1.0.0")
    - `download_behavior` - `:mock` or `:fetch` (default: :mock)
    - `download_duration` - Simulated download time in ms (default: 10_000)
    - `reboot_delay` - Simulated reboot time in ms (default: 5_000)
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    initial_state = %{
      state: :idle,
      current_version: Keyword.get(opts, :current_version, "1.0.0"),
      target_version: nil,
      download_behavior: Keyword.get(opts, :download_behavior, :mock),
      download_duration: Keyword.get(opts, :download_duration, @default_download_duration),
      reboot_delay: Keyword.get(opts, :reboot_delay, @default_reboot_delay),
      download_started_at: nil,
      download_completed_at: nil,
      command_key: nil,
      file_type: nil,
      url: nil,
      fault_code: 0,
      fault_string: ""
    }

    Agent.start_link(fn -> initial_state end)
  end

  @doc """
  Get the current state and version.
  """
  @spec status(pid()) :: {state(), map()}
  def status(agent) do
    Agent.get(agent, fn s ->
      {s.state,
       %{
         current_version: s.current_version,
         target_version: s.target_version,
         command_key: s.command_key,
         download_started_at: s.download_started_at,
         download_completed_at: s.download_completed_at
       }}
    end)
  end

  @doc """
  Get the current firmware version.
  """
  @spec current_version(pid()) :: String.t()
  def current_version(agent) do
    Agent.get(agent, & &1.current_version)
  end

  @doc """
  Get the command key for the current/last transfer.
  """
  @spec command_key(pid()) :: String.t() | nil
  def command_key(agent) do
    Agent.get(agent, & &1.command_key)
  end

  @doc """
  Get fault information for TransferComplete.
  """
  @spec fault_info(pid()) :: {integer(), String.t()}
  def fault_info(agent) do
    Agent.get(agent, fn s -> {s.fault_code, s.fault_string} end)
  end

  @doc """
  Get download timestamps for TransferComplete.
  """
  @spec transfer_times(pid()) :: {String.t(), String.t()}
  def transfer_times(agent) do
    Agent.get(agent, fn s ->
      start_time =
        case s.download_started_at do
          nil -> "0001-01-01T00:00:00Z"
          dt -> DateTime.to_iso8601(dt)
        end

      complete_time =
        case s.download_completed_at do
          nil -> "0001-01-01T00:00:00Z"
          dt -> DateTime.to_iso8601(dt)
        end

      {start_time, complete_time}
    end)
  end

  @doc """
  Start a firmware download. Called when Download RPC is received.

  Params:
    - `url` - Download URL from ACS
    - `command_key` - Command key for correlation
    - `file_type` - TR-069 file type (e.g., "1 Firmware Upgrade Image")
    - `target_version` - Target version to set after upgrade (optional)

  Returns:
    - `{:ok, :downloading}` - Download started
    - `{:error, :already_downloading}` - Already in download state
    - `{:error, :invalid_state}` - Not in idle state
  """
  @spec start_download(pid(), map()) :: {:ok, :downloading} | {:error, term()}
  def start_download(agent, params) do
    Agent.get_and_update(agent, fn s ->
      case s.state do
        :idle ->
          new_state = %{
            s
            | state: :downloading,
              url: params[:url],
              command_key: params[:command_key],
              file_type: params[:file_type],
              target_version: params[:target_version] || extract_version_from_url(params[:url]),
              download_started_at: DateTime.utc_now(),
              download_completed_at: nil,
              fault_code: 0,
              fault_string: ""
          }

          :telemetry.execute(
            [:caretaker, :firmware, :download, :start],
            %{},
            %{
              url: params[:url],
              command_key: params[:command_key],
              current_version: s.current_version,
              target_version: new_state.target_version
            }
          )

          # Start async download simulation
          simulator = agent

          spawn(fn ->
            simulate_download(simulator, s.download_behavior, s.download_duration, params[:url])
          end)

          {{:ok, :downloading}, new_state}

        :downloading ->
          {{:error, :already_downloading}, s}

        _ ->
          {{:error, :invalid_state}, s}
      end
    end)
  end

  @doc """
  Check if download is complete and ready for TransferComplete.
  """
  @spec download_complete?(pid()) :: boolean()
  def download_complete?(agent) do
    Agent.get(agent, fn s -> s.state == :downloaded end)
  end

  @doc """
  Mark the transfer as acknowledged (ACS received TransferComplete).
  Transitions from :downloaded to :applying.
  """
  @spec transfer_acknowledged(pid()) :: :ok | {:error, term()}
  def transfer_acknowledged(agent) do
    Agent.get_and_update(agent, fn s ->
      case s.state do
        :downloaded ->
          new_state = %{s | state: :applying}

          :telemetry.execute(
            [:caretaker, :firmware, :transfer, :acknowledged],
            %{},
            %{command_key: s.command_key}
          )

          {:ok, new_state}

        _ ->
          {{:error, :invalid_state}, s}
      end
    end)
  end

  @doc """
  Start reboot sequence. Called when Reboot RPC is received.
  Transitions from :applying to :rebooting.

  Returns:
    - `{:ok, reboot_delay}` - Reboot started, returns delay in ms
    - `{:error, reason}` - Cannot reboot in current state
  """
  @spec start_reboot(pid()) :: {:ok, non_neg_integer()} | {:error, term()}
  def start_reboot(agent) do
    Agent.get_and_update(agent, fn s ->
      case s.state do
        state when state in [:applying, :downloaded, :idle] ->
          new_state = %{s | state: :rebooting}

          :telemetry.execute(
            [:caretaker, :firmware, :reboot, :start],
            %{},
            %{
              command_key: s.command_key,
              current_version: s.current_version,
              target_version: s.target_version
            }
          )

          # Start async reboot simulation
          simulator = agent
          reboot_delay = s.reboot_delay

          spawn(fn ->
            Process.sleep(reboot_delay)
            complete_reboot(simulator)
          end)

          {{:ok, reboot_delay}, new_state}

        _ ->
          {{:error, :invalid_state}, s}
      end
    end)
  end

  @doc """
  Check if device has rebooted and is ready to reconnect.
  """
  @spec reboot_complete?(pid()) :: boolean()
  def reboot_complete?(agent) do
    Agent.get(agent, fn s -> s.state == :upgraded end)
  end

  @doc """
  Reset simulator to idle state (for testing or re-use).
  """
  @spec reset(pid()) :: :ok
  def reset(agent) do
    Agent.update(agent, fn s ->
      %{
        s
        | state: :idle,
          target_version: nil,
          download_started_at: nil,
          download_completed_at: nil,
          command_key: nil,
          file_type: nil,
          url: nil,
          fault_code: 0,
          fault_string: ""
      }
    end)
  end

  # -- Private functions --

  defp simulate_download(agent, behavior, duration, url) do
    result =
      case behavior do
        :mock ->
          # Just wait for the simulated duration
          Process.sleep(duration)
          :ok

        :fetch ->
          # Actually fetch the URL (HEAD request to validate)
          fetch_url(url, duration)
      end

    case result do
      :ok ->
        complete_download(agent)

      {:error, reason} ->
        fail_download(agent, reason)
    end
  end

  defp fetch_url(url, timeout) do
    # Ensure Finch is started
    case Process.whereis(Caretaker.Finch) do
      nil ->
        case Supervisor.start_link([{Finch, name: Caretaker.Finch}], strategy: :one_for_one) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        :ok
    end

    # Make HEAD request to validate URL
    req = Finch.build(:head, url)

    case Finch.request(req, Caretaker.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Finch.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp complete_download(agent) do
    Agent.update(agent, fn s ->
      if s.state == :downloading do
        new_state = %{s | state: :downloaded, download_completed_at: DateTime.utc_now()}

        :telemetry.execute(
          [:caretaker, :firmware, :download, :complete],
          %{duration_ms: download_duration_ms(s)},
          %{
            url: s.url,
            command_key: s.command_key,
            target_version: s.target_version
          }
        )

        new_state
      else
        s
      end
    end)
  end

  defp fail_download(agent, reason) do
    Agent.update(agent, fn s ->
      if s.state == :downloading do
        {fault_code, fault_string} = reason_to_fault(reason)

        new_state = %{
          s
          | state: :downloaded,
            download_completed_at: DateTime.utc_now(),
            fault_code: fault_code,
            fault_string: fault_string
        }

        :telemetry.execute(
          [:caretaker, :firmware, :download, :failed],
          %{},
          %{
            url: s.url,
            command_key: s.command_key,
            fault_code: fault_code,
            fault_string: fault_string
          }
        )

        new_state
      else
        s
      end
    end)
  end

  defp complete_reboot(agent) do
    Agent.update(agent, fn s ->
      if s.state == :rebooting do
        new_version = s.target_version || s.current_version

        new_state = %{
          s
          | state: :upgraded,
            current_version: new_version,
            target_version: nil
        }

        :telemetry.execute(
          [:caretaker, :firmware, :reboot, :complete],
          %{},
          %{
            command_key: s.command_key,
            new_version: new_version
          }
        )

        new_state
      else
        s
      end
    end)
  end

  defp download_duration_ms(%{download_started_at: nil}), do: 0

  defp download_duration_ms(%{download_started_at: start, download_completed_at: nil}) do
    DateTime.diff(DateTime.utc_now(), start, :millisecond)
  end

  defp download_duration_ms(%{download_started_at: start, download_completed_at: complete}) do
    DateTime.diff(complete, start, :millisecond)
  end

  defp reason_to_fault({:http_error, status}) do
    {9010, "Download failed: HTTP #{status}"}
  end

  defp reason_to_fault(%{reason: :timeout}) do
    {9010, "Download failed: connection timeout"}
  end

  defp reason_to_fault(reason) do
    {9010, "Download failed: #{inspect(reason)}"}
  end

  defp extract_version_from_url(nil), do: nil

  defp extract_version_from_url(url) do
    # Try to extract version from URL like "firmware_v2.0.0.bin"
    case Regex.run(~r/[vV]?(\d+\.\d+\.\d+)/, url) do
      [_, version] -> version
      _ -> nil
    end
  end
end
