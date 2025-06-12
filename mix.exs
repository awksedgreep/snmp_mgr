defmodule SnmpMgr.MixProject do
  use Mix.Project

  def project do
    [
      app: :snmp_mgr,
      version: "1.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Documentation
      name: "SnmpMgr",
      description: "Enterprise-grade SNMP client library for Elixir",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :snmp],
      mod: {SnmpMgr.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:snmp_lib, git: "https://github.com/awksedgreep/snmp_lib", tag: "v1.0.5", override: true},
      {:snmp_sim, git: "https://github.com/awksedgreep/snmp_sim.git", tag: "v1.0.15", override: true},

      # Static analysis
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description: "Enterprise-grade SNMP client library for Elixir with streaming engine and bulk operations",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/awksedgreep/snmp_mgr",
        "Documentation" => "https://hexdocs.pm/snmp_mgr"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: nil,
      source_ref: "v1.0.4",
      source_url: "https://github.com/awksedgreep/snmp_mgr",

      extras: [
        "README.md",
        "docs/getting_started.md",
        "docs/snmp_mgr_guide.md",
        "docs/config_guide.md",
        "docs/types_guide.md",
        "docs/mib_guide.md",
        "docs/multi_guide.md",
        "docs/table_guide.md"
      ],

      groups_for_extras: [
        "Getting Started": ["docs/getting_started.md"],
        "Core Modules": [
          "docs/snmp_mgr_guide.md",
          "docs/config_guide.md",
          "docs/types_guide.md"
        ],
        "Utility Modules": [
          "docs/mib_guide.md",
          "docs/multi_guide.md",
          "docs/table_guide.md"
        ]
      ],

      groups_for_modules: [
        "Core": [SnmpMgr, SnmpMgr.Core, SnmpMgr.Config, SnmpMgr.Types],
        "MIB Support": [SnmpMgr.MIB],
        "Operations": [SnmpMgr.Walk, SnmpMgr.Bulk, SnmpMgr.Multi, SnmpMgr.Table],
        "Advanced": [SnmpMgr.AdaptiveWalk, SnmpMgr.Stream],
        "Infrastructure": [
          SnmpMgr.Engine, SnmpMgr.Router, SnmpMgr.CircuitBreaker,
          SnmpMgr.Metrics, SnmpMgr.Supervisor
        ],
        "Utilities": [SnmpMgr.Target, SnmpMgr.Errors, SnmpMgr.Application]
      ]
    ]
  end
end
