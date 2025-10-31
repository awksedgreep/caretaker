defmodule Caretaker.TR181.Store do
  @moduledoc """
  In-memory store for TR-181 per-device models (Agent-backed).

  Keyed by {oui, product_class, serial}, value is a nested map of TR-181 params.
  """

  use Agent

  @type device_key :: {String.t(), String.t(), String.t()}
  @type model :: map()

  def start_link(_opts \\ []), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @spec put(device_key(), model()) :: :ok
  def put(key, model) when is_tuple(key) and is_map(model) do
    Agent.update(__MODULE__, &Map.put(&1, key, model))
  end

  @spec get(device_key()) :: model() | nil
  def get(key) when is_tuple(key), do: Agent.get(__MODULE__, &Map.get(&1, key))

  @doc "Merge a list of ParameterValueStructs into the device model after validation"
  @spec merge_params(device_key(), [map()], Caretaker.TR181.Schema.t()) :: :ok | {:error, list()}
  def merge_params(key, params, schema) do
    case Caretaker.TR181.Model.from_parameter_values(params) do
      {:ok, nested} ->
        case Caretaker.TR181.Model.Validate.validate(nested, schema) do
          :ok ->
            Agent.update(__MODULE__, fn state ->
              current = Map.get(state, key, %{})
              merged = deep_merge(current, nested)
              Map.put(state, key, merged)
            end)

            :ok

          {:error, errs} ->
            {:error, errs}
        end

      {:error, errs} ->
        {:error, errs}
    end
  end

  defp deep_merge(a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, fn _k, v1, v2 -> deep_merge(v1, v2) end)
  end

  defp deep_merge(_v1, v2), do: v2
end
