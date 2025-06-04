defmodule SnmpMgr.MixProject do
  use Mix.Project

  def project do
    [
      app: :snmp_mgr,
      version: "0.1.2",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :snmp],
      mod: {SNMPMgr.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:snmp_lib, git: "https://github.com/awksedgreep/snmp_lib", tag: "v0.2.3", override: true},
      {:snmp_sim_ex, git: "https://github.com/awksedgreep/snmp_sim_ex", tag: "v0.1.3", override: true},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
