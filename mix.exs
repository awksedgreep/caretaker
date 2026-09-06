defmodule Caretaker.MixProject do
  use Mix.Project

  def project do
    [
      app: :caretaker,
      version: "0.4.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Caretaker — an Elixir TR-069/TR-181/TR-369 (USP) toolkit.",
      package: package(),
      source_url: "https://github.com/awksedgreep/caretaker",
      homepage_url: "https://github.com/awksedgreep/caretaker",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "getting_started.md",
          "testing.md",
          "docs/phase-5-cpe-client.md",
          "docs/telemetry.md",
          "docs/release_checklist.md",
          "docs/acs_setup.md",
          "docs/adding_rpc.md",
          "docs/adding_tr369.md",
          "docs/task_api.md"
        ],
        source_ref: "main"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:lather, "~> 1.1"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:websock_adapter, "~> 0.5"},
      {:telemetry, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:finch, "~> 0.20"},
      {:protobuf, "~> 0.13"},
      {:mint_web_socket, "~> 1.0"},
      # MQTT 5.0 client + broker (USP-over-MQTT transport; broker used in tests).
      {:mqttx, "~> 0.11"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Mark Cotner"],
      links: %{"GitHub" => "https://github.com/awksedgreep/caretaker"},
      # Ship only the library and its docs; keep internal planning material out.
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md getting_started.md testing.md docs)
    ]
  end
end
