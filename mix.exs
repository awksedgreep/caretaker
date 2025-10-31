defmodule Caretaker.MixProject do
  use Mix.Project

  def project do
    [
      app: :caretaker,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Caretaker — an Elixir TR-069/TR-181 toolkit.",
      package: package(),
      source_url: "https://github.com/markcotner/caretaker",
      homepage_url: "https://github.com/markcotner/caretaker",
      docs: [
        main: "readme",
        extras: ["README.md"],
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
