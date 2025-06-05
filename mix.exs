defmodule SnmpMgr.MixProject do
  use Mix.Project

  def project do
    [
      app: :snmp_mgr,
      version: "0.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      
      # Documentation
      name: "SNMPMgr",
      description: "Enterprise-grade SNMP client library for Elixir",
      package: package(),
      docs: docs()
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
      {:snmp_lib, git: "https://github.com/awksedgreep/snmp_lib", tag: "v0.4.0", override: true},
      {:snmp_sim_ex, git: "https://github.com/awksedgreep/snmp_sim_ex", tag: "v0.2.0", override: true},
      
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
      source_ref: "v0.2.0",
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
        "Core": [SNMPMgr, SNMPMgr.Core, SNMPMgr.Config, SNMPMgr.Types],
        "MIB Support": [SNMPMgr.MIB],
        "Operations": [SNMPMgr.Walk, SNMPMgr.Bulk, SNMPMgr.Multi, SNMPMgr.Table],
        "Advanced": [SNMPMgr.AdaptiveWalk, SNMPMgr.Stream],
        "Infrastructure": [
          SNMPMgr.Engine, SNMPMgr.Router, SNMPMgr.CircuitBreaker, 
          SNMPMgr.Metrics, SNMPMgr.Supervisor
        ],
        "Utilities": [SNMPMgr.Target, SNMPMgr.Errors, SNMPMgr.Application]
      ]
    ]
  end
end
