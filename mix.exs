defmodule Caretaker.MixProject do
  use Mix.Project

  def project do
    [
      app: :caretaker,
      version: "0.1.1",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Caretaker — an Elixir TR-069/TR-181 toolkit.",
      package: package(),
      source_url: "https://github.com/markcotner/caretaker",
      homepage_url: "https://github.com/markcotner/caretaker",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "getting_started.md",
          "testing.md",
          "docs/phase-5-cpe-client.md",
          "docs/telemetry.md",
          "docs/release_checklist.md"
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
      {:lather, ">= 0.0.0"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:telemetry, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:tortoise311, "~> 0.12"},
      {:finch, "~> 0.20"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Mark Cotner"],
      links: %{"GitHub" => "https://github.com/markcotner/caretaker"}
    ]
  end
end
