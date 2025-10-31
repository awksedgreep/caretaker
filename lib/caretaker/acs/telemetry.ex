defmodule Caretaker.ACS.Telemetry do
  @moduledoc """
  Telemetry event helpers and optional Logger-backed handlers.
  """

  require Logger

  @spec attach_default_handlers() :: :ok | {:error, :already_exists}
  def attach_default_handlers do
    handler_id = {__MODULE__, :acs_request}

    :telemetry.attach_many(
      handler_id,
      [
        [:caretaker, :acs, :request, :start],
        [:caretaker, :acs, :request, :stop]
      ],
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  @doc false
  def handle_event([:caretaker, :acs, :request, :start], _measure, meta, _config) do
    Logger.metadata(caretaker: true)
    Logger.info("ACS request start method=#{meta[:method]} path=#{meta[:path]}")
  end

  def handle_event([:caretaker, :acs, :request, :stop], measure, meta, _config) do
    dur = measure[:duration] || 0
    Logger.info("ACS request stop status=#{meta[:status]} duration=#{dur}")
  end
end
