defmodule Caretaker.TR181.Model do
  @moduledoc """
  TR-181 parameter model primitives (stub).
  """

  @type path :: String.t()
  @type type :: :string | :int | :bool | :datetime | :base64

  @type param :: %{
          path: path(),
          type: type(),
          value: any()
        }
end
