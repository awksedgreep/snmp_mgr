defmodule SNMPMgr.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Configuration management
      {SNMPMgr.Config, []},
      # MIB registry and management
      {SNMPMgr.MIB, []}
    ]

    opts = [strategy: :one_for_one, name: SNMPMgr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
