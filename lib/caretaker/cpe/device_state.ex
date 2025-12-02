defmodule Caretaker.CPE.DeviceState do
  @moduledoc """
  Maintains TR-181 parameter state for a simulated CPE device.

  Each device has its own parameter store, initialized from a profile
  (map or JSON). Supports get/set operations with TR-181 path awareness
  and basic type validation.

  ## Example

      # Create device with initial parameters
      {:ok, state} = DeviceState.start_link(
        device_id: %{oui: "A1B2C3", product_class: "Router", serial_number: "SN001"},
        params: %{
          "Device" => %{
            "DeviceInfo" => %{
              "Manufacturer" => "Acme",
              "SerialNumber" => "SN001",
              "SoftwareVersion" => "1.0.0"
            }
          }
        }
      )

      # Get a parameter
      DeviceState.get(state, "Device.DeviceInfo.Manufacturer")
      # => "Acme"

      # Set a parameter
      DeviceState.set(state, "Device.DeviceInfo.SoftwareVersion", "2.0.0")
      # => :ok

      # Get all parameters under a path
      DeviceState.get_tree(state, "Device.DeviceInfo.")
      # => %{"Manufacturer" => "Acme", "SerialNumber" => "SN001", ...}
  """

  use Agent
  require Logger

  @type device_id :: %{
          required(:oui) => String.t(),
          required(:product_class) => String.t(),
          required(:serial_number) => String.t()
        }

  @type params :: map()
  @type path :: String.t()
  @type value :: term()

  @doc """
  Start a new device state agent.

  Options:
  - `device_id` - Device identification (required)
  - `params` - Initial parameter tree (default: empty map)
  - `name` - Optional agent name (default: no name)
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    params = Keyword.get(opts, :params, %{})
    name = Keyword.get(opts, :name)

    initial_state = %{
      device_id: device_id,
      params: params,
      created_at: DateTime.utc_now()
    }

    case name do
      nil -> Agent.start_link(fn -> initial_state end)
      name -> Agent.start_link(fn -> initial_state end, name: name)
    end
  end

  @doc """
  Get a parameter value by TR-181 path.

  Supports both dotted paths ("Device.DeviceInfo.Manufacturer")
  and returns nil if not found.
  """
  @spec get(Agent.agent(), path()) :: value() | nil
  def get(agent, path) when is_binary(path) do
    Agent.get(agent, fn state ->
      get_by_path(state.params, path)
    end)
  end

  @doc """
  Set a parameter value by TR-181 path.

  Creates intermediate keys if needed.
  """
  @spec set(Agent.agent(), path(), value()) :: :ok
  def set(agent, path, value) when is_binary(path) do
    Agent.update(agent, fn state ->
      updated_params = put_by_path(state.params, path, value)
      %{state | params: updated_params}
    end)
  end

  @doc """
  Get all parameters under a path (supports trailing dot).

  Returns a nested map of all parameters under the given prefix.
  """
  @spec get_tree(Agent.agent(), path()) :: map()
  def get_tree(agent, path) when is_binary(path) do
    Agent.get(agent, fn state ->
      get_tree_by_path(state.params, path)
    end)
  end

  @doc """
  Get all parameters as a flat list of TR-181 ParameterValueStruct format.

  Returns list of %{name: "path", value: val, type: "xsd:type"}.
  """
  @spec to_parameter_list(Agent.agent()) :: [map()]
  def to_parameter_list(agent) do
    Agent.get(agent, fn state ->
      flatten_params(state.params)
    end)
  end

  @doc """
  Get parameters matching a path (supports wildcard queries like "Device.DeviceInfo.").

  Returns list of %{name: "path", value: val, type: "xsd:type"}.
  """
  @spec get_parameters(Agent.agent(), path()) :: [map()]
  def get_parameters(agent, path) when is_binary(path) do
    Agent.get(agent, fn state ->
      tree = get_tree_by_path(state.params, path)
      flatten_params(tree, path)
    end)
  end

  @doc """
  Update multiple parameters from a list of ParameterValueStruct maps.

  Each item should have :name and :value keys.
  """
  @spec update_parameters(Agent.agent(), [map()]) :: :ok
  def update_parameters(agent, params) when is_list(params) do
    Agent.update(agent, fn state ->
      updated_params =
        Enum.reduce(params, state.params, fn param, acc ->
          put_by_path(acc, param.name, param.value)
        end)

      %{state | params: updated_params}
    end)
  end

  @doc """
  Load parameters from a JSON file.
  """
  @spec load_profile(Agent.agent(), String.t()) :: :ok | {:error, term()}
  def load_profile(agent, file_path) do
    case File.read(file_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, params} ->
            Agent.update(agent, fn state ->
              %{state | params: params}
            end)

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read, reason}}
    end
  end

  @doc """
  Get device_id from state.
  """
  @spec device_id(Agent.agent()) :: device_id()
  def device_id(agent) do
    Agent.get(agent, & &1.device_id)
  end

  # Private helpers

  defp get_by_path(params, path) do
    keys = String.split(path, ".", trim: true)
    get_in(params, keys)
  end

  defp put_by_path(params, path, value) do
    keys = String.split(path, ".", trim: true)
    put_in_nested(params, keys, value)
  end

  defp put_in_nested(_params, [], value), do: value

  defp put_in_nested(params, [key | rest], value) do
    current = Map.get(params, key, %{})
    Map.put(params, key, put_in_nested(current, rest, value))
  end

  defp get_tree_by_path(params, path) do
    # Remove trailing dot if present
    clean_path = String.trim_trailing(path, ".")

    case clean_path do
      "" -> params
      _ -> get_by_path(params, clean_path) || %{}
    end
  end

  defp flatten_params(params, prefix \\ "") do
    Enum.flat_map(params, fn {key, value} ->
      full_key = if prefix == "", do: key, else: "#{prefix}#{key}"

      case value do
        %{} = nested when map_size(nested) > 0 ->
          flatten_params(nested, "#{full_key}.")

        scalar ->
          [
            %{
              name: full_key,
              value: to_string(scalar),
              type: infer_type(scalar)
            }
          ]
      end
    end)
  end

  defp infer_type(value) when is_integer(value), do: "xsd:int"
  defp infer_type(value) when is_boolean(value), do: "xsd:boolean"
  defp infer_type(value) when is_float(value), do: "xsd:double"
  defp infer_type(_value), do: "xsd:string"
end
