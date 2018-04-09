defmodule Pinocchio.MixProject do
  use Mix.Project

  def project do
    [
      app: :pinocchio,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Pinocchio.Application, []}
    ]
  end

  def deps do
    [
      {:nostrum, git: "https://github.com/Kraigie/nostrum.git"}
    ]
  end
end
