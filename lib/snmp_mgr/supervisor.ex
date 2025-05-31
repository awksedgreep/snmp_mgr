defmodule SNMPMgr.Supervisor do
  @moduledoc """
  Main supervisor for the SNMPMgr streaming PDU engine infrastructure.
  
  This supervisor manages all Phase 5 components including engines, routers,
  connection pools, circuit breakers, and metrics collection.
  """
  
  use Supervisor
  require Logger
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    # Configuration
    engine_config = Keyword.get(opts, :engine, [])
    router_config = Keyword.get(opts, :router, [])
    pool_config = Keyword.get(opts, :pool, [])
    circuit_breaker_config = Keyword.get(opts, :circuit_breaker, [])
    metrics_config = Keyword.get(opts, :metrics, [])
    
    children = [
      # Metrics collection (start first)
      {SNMPMgr.Metrics, metrics_config},
      
      # Circuit breaker
      {SNMPMgr.CircuitBreaker, circuit_breaker_config},
      
      # Connection pool
      {SNMPMgr.Pool, pool_config},
      
      # Main engines (can have multiple)
      {SNMPMgr.Engine, Keyword.put(engine_config, :name, :engine_1)},
      {SNMPMgr.Engine, Keyword.put(engine_config, :name, :engine_2)},
      
      # Router (coordinates engines)
      {SNMPMgr.Router, 
        Keyword.merge(router_config, [
          engines: [
            %{name: :engine_1, weight: 1, max_load: 100},
            %{name: :engine_2, weight: 1, max_load: 100}
          ]
        ])}
    ]
    
    Logger.info("Starting SNMPMgr Phase 5 infrastructure")
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end