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
  - `firmware_simulator` - Optional FirmwareSimulator agent pid
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    params = Keyword.get(opts, :params, %{})
    name = Keyword.get(opts, :name)
    firmware_simulator = Keyword.get(opts, :firmware_simulator)

    dynamic_behavior = Keyword.get(opts, :dynamic_behavior)

    initial_state = %{
      device_id: device_id,
      params: params,
      attributes: %{},
      instance_numbers: %{},
      options: %{firmware_simulator: firmware_simulator, dynamic_behavior: dynamic_behavior},
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
  If a dynamic_behavior is configured, it will be notified of the change.
  """
  @spec set(Agent.agent(), path(), value()) :: :ok
  def set(agent, path, value) when is_binary(path) do
    Agent.get_and_update(agent, fn state ->
      old_value = get_by_path(state.params, path)
      updated_params = put_by_path(state.params, path, value)
      new_state = %{state | params: updated_params}

      # Notify dynamic behavior of change if configured
      case state.options[:dynamic_behavior] do
        nil ->
          :ok

        pid when is_pid(pid) ->
          if Process.alive?(pid) and old_value != value do
            Caretaker.CPE.DynamicBehavior.record_change(pid, path, old_value, value)
          end

        _ ->
          :ok
      end

      {:ok, new_state}
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
  Notifies dynamic_behavior of changes if configured.
  """
  @spec update_parameters(Agent.agent(), [map()]) :: :ok
  def update_parameters(agent, params) when is_list(params) do
    Agent.get_and_update(agent, fn state ->
      # Collect old values for change tracking
      changes =
        Enum.map(params, fn param ->
          old_value = get_by_path(state.params, param.name)
          {param.name, old_value, param.value}
        end)

      updated_params =
        Enum.reduce(params, state.params, fn param, acc ->
          put_by_path(acc, param.name, param.value)
        end)

      new_state = %{state | params: updated_params}

      # Notify dynamic behavior of changes
      case state.options[:dynamic_behavior] do
        nil ->
          :ok

        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            Enum.each(changes, fn {path, old_val, new_val} ->
              if old_val != new_val do
                Caretaker.CPE.DynamicBehavior.record_change(pid, path, old_val, new_val)
              end
            end)
          end

        _ ->
          :ok
      end

      {:ok, new_state}
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

  @doc """
  Get an option value from state.
  """
  @spec get_option(Agent.agent(), atom()) :: {:ok, term()} | :error
  def get_option(agent, key) when is_atom(key) do
    Agent.get(agent, fn state ->
      case Map.fetch(state.options, key) do
        {:ok, nil} -> :error
        {:ok, value} -> {:ok, value}
        :error -> :error
      end
    end)
  end

  @doc """
  Set an option value in state.
  """
  @spec set_option(Agent.agent(), atom(), term()) :: :ok
  def set_option(agent, key, value) when is_atom(key) do
    Agent.update(agent, fn state ->
      %{state | options: Map.put(state.options, key, value)}
    end)
  end

  @doc """
  Get parameter names under a given path.

  If next_level is true, returns only immediate children (partial paths).
  If next_level is false, returns all descendant parameter names (full paths).

  Returns list of %{name: String.t(), writable: boolean()} maps.
  """
  @spec get_parameter_names(Agent.agent(), String.t(), boolean()) :: [
          %{name: String.t(), writable: boolean()}
        ]
  def get_parameter_names(agent, path, next_level \\ false) do
    Agent.get(agent, fn state ->
      tree = get_tree_by_path(state.params, path)
      collect_parameter_names(tree, path, next_level)
    end)
  end

  @doc """
  Get parameter attributes for a list of paths.

  Returns list of %{name: String.t(), notification: integer(), access_list: [String.t()]} maps.
  Default notification is 0 (off), default access_list is ["Subscriber"].
  """
  @spec get_parameter_attributes(Agent.agent(), [String.t()]) :: [
          %{name: String.t(), notification: integer(), access_list: [String.t()]}
        ]
  def get_parameter_attributes(agent, paths) when is_list(paths) do
    Agent.get(agent, fn state ->
      Enum.flat_map(paths, fn path ->
        # Expand path to include all parameters under it if path ends with "."
        param_paths =
          if String.ends_with?(path, ".") do
            tree = get_tree_by_path(state.params, path)

            flatten_names(tree, String.trim_trailing(path, "."))
            |> Enum.map(& &1.name)
          else
            [path]
          end

        Enum.map(param_paths, fn p ->
          attrs = Map.get(state.attributes, p, %{notification: 0, access_list: ["Subscriber"]})
          %{name: p, notification: attrs.notification, access_list: attrs.access_list}
        end)
      end)
    end)
  end

  @doc """
  Set parameter attributes for a list of attribute changes.

  Each item should have: name, notification_change, notification, access_list_change, access_list.
  Only updates the attributes where the corresponding *_change flag is true.
  """
  @spec set_parameter_attributes(Agent.agent(), [map()]) :: :ok
  def set_parameter_attributes(agent, attrs) when is_list(attrs) do
    Agent.update(agent, fn state ->
      updated_attrs =
        Enum.reduce(attrs, state.attributes, fn attr, acc ->
          current = Map.get(acc, attr.name, %{notification: 0, access_list: ["Subscriber"]})

          new_attrs = %{
            notification:
              if(attr.notification_change, do: attr.notification, else: current.notification),
            access_list:
              if(attr.access_list_change, do: attr.access_list, else: current.access_list)
          }

          Map.put(acc, attr.name, new_attrs)
        end)

      %{state | attributes: updated_attrs}
    end)
  end

  @doc """
  Add a new object instance under the given path.

  The path should be a multi-instance object path ending with a dot (e.g., "Device.IP.Interface.").
  Returns {:ok, instance_number} with the newly created instance number.
  """
  @spec add_object_instance(Agent.agent(), String.t()) :: {:ok, integer()}
  def add_object_instance(agent, object_path) do
    Agent.get_and_update(agent, fn state ->
      clean_path = String.trim_trailing(object_path, ".")

      # Get current instance number for this path, default to 0
      current = Map.get(state.instance_numbers, clean_path, 0)
      new_instance = current + 1

      # Create the instance path (e.g., "Device.IP.Interface.1")
      instance_path = "#{clean_path}.#{new_instance}"

      # Create empty instance node in params
      updated_params = put_by_path(state.params, instance_path, %{})

      # Update instance counter
      updated_instances = Map.put(state.instance_numbers, clean_path, new_instance)

      new_state = %{state | params: updated_params, instance_numbers: updated_instances}
      {{:ok, new_instance}, new_state}
    end)
  end

  @doc """
  Delete an object instance at the given path.

  The path should be a specific instance path (e.g., "Device.IP.Interface.1.").
  Returns :ok on success, {:error, :not_found} if the instance doesn't exist.
  """
  @spec delete_object_instance(Agent.agent(), String.t()) :: :ok | {:error, :not_found}
  def delete_object_instance(agent, object_path) do
    Agent.get_and_update(agent, fn state ->
      clean_path = String.trim_trailing(object_path, ".")
      keys = String.split(clean_path, ".", trim: true)

      # Check if the path exists
      current_value = get_by_path(state.params, clean_path)

      if current_value != nil do
        # Remove the instance by deleting the key from the parent
        {parent_keys, [instance_key]} = Enum.split(keys, -1)
        parent_path = Enum.join(parent_keys, ".")

        updated_params =
          if parent_path == "" do
            Map.delete(state.params, instance_key)
          else
            parent = get_by_path(state.params, parent_path) || %{}
            updated_parent = Map.delete(parent, instance_key)
            put_by_path(state.params, parent_path, updated_parent)
          end

        # Also clean up any attributes for parameters under this instance
        prefix = "#{clean_path}."

        updated_attrs =
          state.attributes
          |> Enum.reject(fn {k, _v} -> String.starts_with?(k, prefix) || k == clean_path end)
          |> Map.new()

        new_state = %{state | params: updated_params, attributes: updated_attrs}
        {:ok, new_state}
      else
        {{:error, :not_found}, state}
      end
    end)
  end

  @doc """
  Get the next available instance number for a multi-instance object path.

  Returns the next instance number that would be assigned (current max + 1).
  """
  @spec get_next_instance_number(Agent.agent(), String.t()) :: integer()
  def get_next_instance_number(agent, object_path) do
    Agent.get(agent, fn state ->
      clean_path = String.trim_trailing(object_path, ".")
      Map.get(state.instance_numbers, clean_path, 0) + 1
    end)
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

  # Collect parameter names with NextLevel support
  defp collect_parameter_names(params, prefix, next_level) when is_map(params) do
    clean_prefix = String.trim_trailing(prefix, ".")

    if next_level do
      # NextLevel=true: return only immediate children (partial paths)
      params
      |> Map.keys()
      |> Enum.map(fn key ->
        full_name = if clean_prefix == "", do: "#{key}.", else: "#{clean_prefix}.#{key}."
        %{name: full_name, writable: true}
      end)
    else
      # NextLevel=false: return all leaf parameters (full paths)
      flatten_names(params, clean_prefix)
    end
  end

  defp collect_parameter_names(_params, _prefix, _next_level), do: []

  defp flatten_names(params, prefix) when is_map(params) do
    Enum.flat_map(params, fn {key, value} ->
      full_key = if prefix == "", do: key, else: "#{prefix}.#{key}"

      case value do
        %{} = nested when map_size(nested) > 0 ->
          flatten_names(nested, full_key)

        _scalar ->
          [%{name: full_key, writable: true}]
      end
    end)
  end

  defp flatten_names(_params, _prefix), do: []
end
