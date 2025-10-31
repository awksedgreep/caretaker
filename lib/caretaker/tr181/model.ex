defmodule Caretaker.TR181.Model do
  @moduledoc """
  Minimal TR-181 model helpers: basic type casting/validation and path mapping.

  - Type mapping from XSD (xsd:string, xsd:int, xsd:boolean, xsd:unsignedInt, xsd:dateTime)
  - Casting values to native Elixir types
  - Building nested maps from dotted TR-181 paths and flattening back
  """

  @typedoc "Supported XSD types"
  @type xsd_type :: String.t()

  @typedoc "Cast result"
  @type casted :: String.t() | integer() | boolean() | DateTime.t()

  @spec type_for_xsd(String.t()) ::
          :string
          | :int
          | :uint
          | :bool
          | :datetime
          | :long
          | :ulong
          | :float
          | :double
          | :decimal
          | :base64
          | :unknown
  def type_for_xsd("xsd:string"), do: :string
  def type_for_xsd("xsd:int"), do: :int
  def type_for_xsd("xsd:unsignedInt"), do: :uint
  def type_for_xsd("xsd:boolean"), do: :bool
  def type_for_xsd("xsd:dateTime"), do: :datetime
  def type_for_xsd("xsd:long"), do: :long
  def type_for_xsd("xsd:unsignedLong"), do: :ulong
  def type_for_xsd("xsd:float"), do: :float
  def type_for_xsd("xsd:double"), do: :double
  def type_for_xsd("xsd:decimal"), do: :decimal
  def type_for_xsd("xsd:base64Binary"), do: :base64
  def type_for_xsd(_), do: :unknown

  @doc "Cast string value to native type based on XSD type"
  @spec cast(String.t(), String.t()) :: {:ok, casted()} | {:error, term()}
  def cast(value, "xsd:string") when is_binary(value), do: {:ok, value}

  def cast(value, "xsd:int") when is_binary(value) do
    case Integer.parse(value) do
      {i, ""} -> {:ok, i}
      _ -> {:error, :invalid_int}
    end
  end

  def cast(value, "xsd:unsignedInt") when is_binary(value) do
    with {:ok, i} <- cast(value, "xsd:int"),
         true <- i >= 0 do
      {:ok, i}
    else
      false -> {:error, :negative}
      {:error, _} = e -> e
    end
  end

  def cast(value, "xsd:boolean") when is_binary(value) do
    case String.downcase(value) do
      "1" -> {:ok, true}
      "0" -> {:ok, false}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, :invalid_boolean}
    end
  end

  def cast(value, "xsd:dateTime") when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, :invalid_datetime}
    end
  end

  def cast(value, "xsd:long") when is_binary(value), do: cast(value, "xsd:int")
  def cast(value, "xsd:unsignedLong") when is_binary(value), do: cast(value, "xsd:unsignedInt")

  def cast(value, "xsd:float") when is_binary(value) do
    case Float.parse(value) do
      {f, ""} -> {:ok, f}
      _ -> {:error, :invalid_float}
    end
  end

  def cast(value, "xsd:double") when is_binary(value), do: cast(value, "xsd:float")
  def cast(value, "xsd:decimal") when is_binary(value), do: cast(value, "xsd:float")

  def cast(value, "xsd:base64Binary") when is_binary(value) do
    case Base.decode64(value) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :invalid_base64}
    end
  end

  def cast(value, _unknown) when is_binary(value), do: {:ok, value}

  @doc "Cast a ParameterValueStruct-like map %{name, value, type}"
  @spec cast_param(%{name: String.t(), value: String.t(), type: String.t()}) ::
          {:ok, %{name: String.t(), value: casted(), type: String.t()}} | {:error, term()}
  def cast_param(%{name: name, value: val, type: type}) do
    case cast(val, type) do
      {:ok, v} -> {:ok, %{name: name, value: v, type: type}}
      {:error, reason} -> {:error, {name, reason}}
    end
  end

  @doc "Put a value into nested map based on dotted path. Trailing dot is ignored."
  @spec put_path(map(), String.t(), any()) :: map()
  def put_path(acc, path, value) do
    segments =
      path
      |> String.trim_trailing(".")
      |> String.split(".", trim: true)

    do_put_path(acc, segments, value)
  end

  defp do_put_path(acc, [last], value), do: Map.put(acc, last, value)

  defp do_put_path(acc, [seg | rest], value) do
    child = Map.get(acc, seg, %{})
    Map.put(acc, seg, do_put_path(child, rest, value))
  end

  @doc "Build nested map from list of %{name, value, type} after casting"
  @spec normalize_params([%{name: String.t(), value: String.t(), type: String.t()}]) ::
          {:ok, map()} | {:error, list()}
  def normalize_params(params) when is_list(params) do
    {errors, casted} =
      params
      |> Enum.map(&cast_param/1)
      |> Enum.split_with(fn
        {:error, _} -> true
        {:ok, _} -> false
      end)

    if errors != [] do
      {:error, Enum.map(errors, fn {:error, e} -> e end)}
    else
      nested =
        casted
        |> Enum.map(fn {:ok, p} -> p end)
        |> Enum.reduce(%{}, fn %{name: n, value: v}, acc -> put_path(acc, n, v) end)

      {:ok, nested}
    end
  end

  @doc "Convenience: from ParameterValueStructs list to nested map"
  @spec from_parameter_values([map()]) :: {:ok, map()} | {:error, list()}
  def from_parameter_values(list), do: normalize_params(list)

  @doc "Flatten nested map back to ParameterValueStruct list with provided XSD type map (path => type)"
  @spec to_parameter_values(map(), map()) :: [map()]
  def to_parameter_values(nested, type_map \\ %{}) when is_map(nested) do
    nested
    |> flatten_kv()
    |> Enum.map(fn {path, value} ->
      xsd = Map.get(type_map, path, infer_xsd(value))
      %{name: path, value: to_string_value(value, xsd), type: xsd}
    end)
  end

  defp flatten_kv(map, prefix \\ "") do
    Enum.flat_map(map, fn {k, v} ->
      path = if prefix == "", do: k, else: prefix <> "." <> k

      case v do
        %{} -> flatten_kv(v, path)
        other -> [{path, other}]
      end
    end)
  end

  defp infer_xsd(value) when is_integer(value), do: "xsd:int"
  defp infer_xsd(value) when is_boolean(value), do: "xsd:boolean"
  defp infer_xsd(value) when is_float(value), do: "xsd:double"
  defp infer_xsd(%DateTime{}), do: "xsd:dateTime"
  defp infer_xsd(value) when is_binary(value), do: "xsd:string"
  defp infer_xsd(_), do: "xsd:string"

  def to_string_value(%DateTime{} = dt, _xsd), do: DateTime.to_iso8601(dt)
  def to_string_value(value, "xsd:base64Binary") when is_binary(value), do: Base.encode64(value)
  def to_string_value(value, _xsd), do: to_string(value)
end

defmodule Caretaker.TR181.Model.Validate do
  @moduledoc false
  alias Caretaker.TR181.Model

  @spec validate(map(), Caretaker.TR181.Schema.t()) :: :ok | {:error, [term()]}
  def validate(nested, schema) when is_map(nested) and is_map(schema) do
    flat = flatten(nested)

    errs =
      Enum.flat_map(schema, fn {path, rules} ->
        val = Map.get(flat, path)
        validate_rules(path, val, rules)
      end)

    case errs do
      [] -> :ok
      list -> {:error, list}
    end
  end

  defp flatten(map, prefix \\ "") do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      path = if prefix == "", do: k, else: prefix <> "." <> k

      cond do
        is_map(v) and Map.get(v, :__struct__) == nil ->
          Map.merge(acc, flatten(v, path))

        true ->
          Map.put(acc, path, v)
      end
    end)
  end

  defp validate_rules(path, val, rules) do
    Enum.flat_map(rules, fn
      :required ->
        if is_nil(val), do: [{path, :required}], else: []

      {:type, xsd} ->
        if is_nil(val) do
          []
        else
          case Model.cast(Model.to_string_value(val, xsd), xsd) do
            {:ok, _} -> []
            {:error, reason} -> [{path, {:type, xsd, reason}}]
          end
        end

      {:min, min} ->
        cond do
          is_nil(val) -> []
          not is_numberish(val) -> []
          value_to_number(val) < min -> [{path, {:min, min}}]
          true -> []
        end

      {:max, max} ->
        cond do
          is_nil(val) -> []
          not is_numberish(val) -> []
          value_to_number(val) > max -> [{path, {:max, max}}]
          true -> []
        end

      {:enum, list} ->
        if is_nil(val) or val in list, do: [], else: [{path, {:enum, list}}]

      _ ->
        []
    end)
  end

  defp is_numberish(v), do: is_integer(v) or is_float(v)
  defp value_to_number(v) when is_integer(v) or is_float(v), do: v

  defp value_to_number(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} ->
        i

      _ ->
        case Float.parse(v) do
          {f, ""} -> f
          _ -> 0
        end
    end
  end

  defp value_to_number(_), do: 0
end
