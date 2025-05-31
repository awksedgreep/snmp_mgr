defmodule SNMPMgr.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Configuration management
      {SNMPMgr.Config, []},
      # MIB registry and management
      {SNMPMgr.MIB, []},
      # Circuit breaker for fault tolerance
      {SNMPMgr.CircuitBreaker, []}
    ]

    opts = [strategy: :one_for_one, name: SNMPMgr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
