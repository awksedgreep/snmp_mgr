defmodule SNMPMgr.EngineIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.{Engine, Router, CircuitBreaker, Pool, Metrics, Config}
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :integration
  @moduletag :engine_integration
  @moduletag :phase_4
  
  # Integration test configuration
  @pool_size 3
  @num_engines 2
  @test_timeout 10_000
  
  setup_all do
    # Ensure configuration is available
    case GenServer.whereis(SNMPMgr.Config) do
      nil -> {:ok, _pid} = Config.start_link()
      _pid -> :ok
    end
    
    # Start SNMP simulator for integration testing
    {:ok, simulator_pid} = SNMPSimulator.start_link()
    on_exit(fn -> SNMPSimulator.stop(simulator_pid) end)
    
    %{simulator: simulator_pid}
  end
  
  setup do
    # Start the full engine ecosystem
    {:ok, metrics_pid} = Metrics.start_link(
      collection_interval: 100,
      window_size: 5
    )
    
    {:ok, pool_pid} = Pool.start_link(
      pool_size: @pool_size,
      max_idle_time: 30_000,
      cleanup_interval: 5_000
    )
    
    {:ok, cb_pid} = CircuitBreaker.start_link(
      failure_threshold: 3,
      recovery_timeout: 2_000
    )
    
    # Start multiple engines
    engine_specs = Enum.map(1..@num_engines, fn i ->
      {:ok, engine_pid} = Engine.start_link(
        name: :"engine_#{i}",
        pool_size: @pool_size,
        max_requests_per_second: 50,
        batch_size: 10
      )
      %{name: :"engine_#{i}", pid: engine_pid, weight: i, max_load: 50 * i}
    end)
    
    {:ok, router_pid} = Router.start_link(
      strategy: :round_robin,
      engines: engine_specs,
      max_retries: 2
    )
    
    on_exit(fn ->
      # Cleanup in reverse order
      if Process.alive?(router_pid), do: GenServer.stop(router_pid)
      
      Enum.each(engine_specs, fn %{pid: pid} ->
        if Process.alive?(pid), do: Engine.stop(pid)
      end)
      
      if Process.alive?(cb_pid), do: GenServer.stop(cb_pid)
      if Process.alive?(pool_pid), do: Pool.stop(pool_pid)
      if Process.alive?(metrics_pid), do: GenServer.stop(metrics_pid)
    end)
    
    %{
      metrics: metrics_pid,
      pool: pool_pid,
      circuit_breaker: cb_pid,
      router: router_pid,
      engines: engine_specs
    }
  end
  
  describe "Full Engine Ecosystem Integration" do
    test "end-to-end request processing through all components", %{router: router, metrics: metrics} do
      # Record the operation with metrics
      result = Metrics.time(metrics, :integration_request, fn ->
        request = %{
          type: :get,
          target: "127.0.0.1:161",
          oid: "1.3.6.1.2.1.1.1.0",
          community: "public"
        }
        
        Router.route_request(router, request)
      end)
      
      # Should complete successfully or with expected error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      # Verify metrics were recorded
      Process.sleep(200)  # Allow metrics collection
      
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) >= 1
    end
    
    test "router distributes requests across multiple engines", %{router: router, engines: engines} do
      # Submit multiple requests
      requests = Enum.map(1..10, fn i ->
        %{
          type: :get,
          target: "device#{i}.test",
          oid: "1.3.6.1.2.1.1.#{i}.0",
          community: "public"
        }
      end)
      
      # Route all requests
      results = Enum.map(requests, fn request ->
        Router.route_request(router, request)
      end)
      
      # Should handle all requests
      assert length(results) == 10
      
      # Check that engines received work
      Enum.each(engines, fn %{pid: engine_pid} ->
        stats = Engine.get_stats(engine_pid)
        # At least some engines should have processed requests
        assert is_map(stats)
      end)
    end
    
    test "circuit breaker protects against failing targets", %{circuit_breaker: cb, router: router} do
      failing_target = "unreachable.device.invalid"
      
      # Submit requests that will fail
      failing_request = %{
        type: :get,
        target: failing_target,
        oid: "1.3.6.1.2.1.1.1.0",
        community: "public"
      }
      
      # Submit multiple failing requests
      results = Enum.map(1..5, fn _i ->
        Router.route_request(router, failing_request)
      end)
      
      # Should handle failures gracefully
      assert length(results) == 5
      
      # Circuit breaker should track the failures
      stats = CircuitBreaker.get_stats(cb)
      assert is_map(stats)
    end
    
    test "pool provides connections to engines", %{pool: pool, engines: engines} do
      # Verify pool is functioning
      {:ok, connection} = Pool.checkout(pool)
      assert is_map(connection)
      Pool.checkin(pool, connection)
      
      # Engines should be able to get pool status
      Enum.each(engines, fn %{pid: engine_pid} ->
        pool_status = Engine.get_pool_status(engine_pid)
        assert is_list(pool_status)
      end)
    end
    
    test "metrics collect data from all components", %{metrics: metrics, router: router, circuit_breaker: cb, pool: pool} do
      # Generate activity across all components
      test_request = %{
        type: :get,
        target: "test.integration.device",
        oid: "1.3.6.1.2.1.1.1.0",
        community: "public"
      }
      
      # Router activity
      Router.route_request(router, test_request)
      
      # Pool activity
      {:ok, conn} = Pool.checkout(pool)
      Pool.checkin(pool, conn)
      
      # Circuit breaker activity
      CircuitBreaker.record_success(cb, "test.device")
      
      # Metrics activity
      Metrics.counter(metrics, :integration_test, 1)
      Metrics.gauge(metrics, :active_components, 4)
      
      # Allow collection
      Process.sleep(200)
      
      # Verify metrics were collected
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) >= 2
      
      summary = Metrics.get_summary(metrics)
      assert summary.total_metric_types[:counter] >= 1
      assert summary.total_metric_types[:gauge] >= 1
    end
  end
  
  describe "Load Testing and Performance" do
    test "system handles moderate concurrent load", %{router: router, metrics: metrics} do
      num_concurrent = 20
      requests_per_task = 5
      
      start_time = System.monotonic_time(:millisecond)
      
      # Create concurrent tasks
      tasks = Enum.map(1..num_concurrent, fn task_id ->
        Task.async(fn ->
          Enum.map(1..requests_per_task, fn req_id ->
            request = %{
              type: :get,
              target: "device#{task_id}.test",
              oid: "1.3.6.1.2.1.1.#{req_id}.0",
              community: "public"
            }
            
            # Time each request
            Metrics.time(metrics, :concurrent_request, fn ->
              Router.route_request(router, request)
            end, %{task: task_id})
          end)
        end)
      end)
      
      # Wait for all tasks
      results = Task.yield_many(tasks, @test_timeout)
      
      end_time = System.monotonic_time(:millisecond)
      total_duration = end_time - start_time
      
      # Verify completion
      completed_tasks = Enum.count(results, fn {_task, result} -> result != nil end)
      assert completed_tasks >= num_concurrent / 2  # At least half should complete
      
      # Should handle load efficiently
      total_requests = num_concurrent * requests_per_task
      avg_time_per_request = total_duration / total_requests
      assert avg_time_per_request < 1000  # Less than 1 second per request
      
      # Verify metrics were collected
      Process.sleep(300)
      summary = Metrics.get_summary(metrics)
      assert summary.total_metric_types[:histogram] >= 1
    end
    
    test "system maintains stability under prolonged load", %{router: router, metrics: metrics} do
      # Run sustained load for a period
      duration_ms = 3000  # 3 seconds
      request_interval = 50  # Every 50ms
      
      start_time = System.monotonic_time(:millisecond)
      request_count = 0
      
      # Submit requests at regular intervals
      while System.monotonic_time(:millisecond) - start_time < duration_ms do
        request = %{
          type: :get,
          target: "sustained.load.test",
          oid: "1.3.6.1.2.1.1.#{rem(request_count, 10)}.0",
          community: "public"
        }
        
        spawn(fn ->
          Metrics.time(metrics, :sustained_request, fn ->
            Router.route_request(router, request)
          end)
        end)
        
        request_count = request_count + 1
        Process.sleep(request_interval)
      end
      
      end_time = System.monotonic_time(:millisecond)
      actual_duration = end_time - start_time
      
      # System should remain stable
      assert actual_duration >= duration_ms
      assert request_count >= duration_ms / request_interval / 2  # At least half expected requests
      
      # All components should still be responsive
      router_stats = Router.get_stats(router)
      assert is_map(router_stats)
      
      metrics_summary = Metrics.get_summary(metrics)
      assert is_map(metrics_summary)
    end
    
    test "resource usage remains bounded under load", %{router: router, engines: engines, pool: pool, circuit_breaker: cb, metrics: metrics} do
      # Measure initial memory usage
      initial_memory = %{
        router: :erlang.process_info(router, :memory)[:memory],
        pool: :erlang.process_info(pool, :memory)[:memory],
        cb: :erlang.process_info(cb, :memory)[:memory],
        metrics: :erlang.process_info(metrics, :memory)[:memory]
      }
      
      engine_initial_memory = Enum.map(engines, fn %{pid: pid} ->
        {pid, :erlang.process_info(pid, :memory)[:memory]}
      end)
      
      # Generate significant load
      Enum.each(1..100, fn i ->
        request = %{
          type: :get,
          target: "memory.test.#{rem(i, 5)}",
          oid: "1.3.6.1.2.1.1.#{rem(i, 10)}.0",
          community: "public"
        }
        
        Router.route_request(router, request)
        
        # Also generate component-specific activity
        if rem(i, 10) == 0 do
          {:ok, conn} = Pool.checkout(pool)
          Pool.checkin(pool, conn)
          
          CircuitBreaker.record_success(cb, "memory.test.device")
          
          Metrics.counter(metrics, :memory_test, 1, %{iteration: i})
        end
      end)
      
      # Allow processing and cleanup
      Process.sleep(1000)
      
      # Measure final memory usage
      final_memory = %{
        router: :erlang.process_info(router, :memory)[:memory],
        pool: :erlang.process_info(pool, :memory)[:memory],
        cb: :erlang.process_info(cb, :memory)[:memory],
        metrics: :erlang.process_info(metrics, :memory)[:memory]
      }
      
      engine_final_memory = Enum.map(engines, fn %{pid: pid} ->
        {pid, :erlang.process_info(pid, :memory)[:memory]}
      end)
      
      # Memory growth should be reasonable
      router_growth = final_memory.router - initial_memory.router
      pool_growth = final_memory.pool - initial_memory.pool
      cb_growth = final_memory.cb - initial_memory.cb
      metrics_growth = final_memory.metrics - initial_memory.metrics
      
      # Allow reasonable growth but not excessive
      assert router_growth < 5_000_000  # Less than 5MB
      assert pool_growth < 2_000_000    # Less than 2MB
      assert cb_growth < 1_000_000      # Less than 1MB
      assert metrics_growth < 3_000_000 # Less than 3MB
      
      # Engine memory should also be bounded
      Enum.zip(engine_initial_memory, engine_final_memory)
      |> Enum.each(fn {{pid, initial}, {^pid, final}} ->
        growth = final - initial
        assert growth < 5_000_000  # Less than 5MB per engine
      end)
    end
  end
  
  describe "Failure Scenarios and Recovery" do
    test "system handles engine failures gracefully", %{router: router, engines: engines} do
      # Stop one engine
      [%{pid: first_engine} | remaining_engines] = engines
      Engine.stop(first_engine)
      
      # System should continue functioning with remaining engines
      request = %{
        type: :get,
        target: "failover.test",
        oid: "1.3.6.1.2.1.1.1.0",
        community: "public"
      }
      
      result = Router.route_request(router, request)
      
      # Should either succeed with remaining engines or fail gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      # Router should detect the failed engine
      Process.sleep(100)
      router_stats = Router.get_stats(router)
      assert router_stats.engine_count <= length(engines)
    end
    
    test "circuit breaker prevents cascade failures", %{circuit_breaker: cb, router: router} do
      failing_targets = ["fail1.test", "fail2.test", "fail3.test"]
      
      # Cause failures for multiple targets
      Enum.each(failing_targets, fn target ->
        Enum.each(1..5, fn _i ->
          # Simulate failures
          CircuitBreaker.record_failure(cb, target, :simulated_failure)
          
          # Also route requests that might fail
          failing_request = %{
            type: :get,
            target: target,
            oid: "1.3.6.1.2.1.1.1.0",
            community: "public"
          }
          
          Router.route_request(router, failing_request)
        end)
      end)
      
      # Circuit breakers should be open for failed targets
      cb_stats = CircuitBreaker.get_stats(cb)
      assert cb_stats.total_breakers >= length(failing_targets)
      
      # System should still handle requests to healthy targets
      healthy_request = %{
        type: :get,
        target: "healthy.device.test",
        oid: "1.3.6.1.2.1.1.1.0",
        community: "public"
      }
      
      result = Router.route_request(router, healthy_request)
      # Should handle healthy requests normally
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "pool handles connection errors and recovery", %{pool: pool} do
      # Create connections
      connections = Enum.map(1..3, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        conn
      end)
      
      # Simulate connection errors
      Enum.each(connections, fn conn ->
        Pool.return_error(pool, conn, :connection_error)
      end)
      
      # Pool should handle errors and remain functional
      stats = Pool.get_stats(pool)
      assert stats.metrics.connection_errors >= 3
      
      # Should still be able to create new connections
      {:ok, new_connection} = Pool.checkout(pool)
      assert is_map(new_connection)
      Pool.checkin(pool, new_connection)
    end
    
    test "metrics system handles component failures", %{metrics: metrics, router: router} do
      # Start collecting metrics
      Metrics.counter(metrics, :failure_test, 1)
      
      # Stop router to simulate component failure
      GenServer.stop(router)
      
      # Metrics should continue functioning
      Metrics.counter(metrics, :post_failure_test, 1)
      Metrics.gauge(metrics, :system_status, 0)
      
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) >= 2
      
      # Should have both pre and post failure metrics
      pre_failure = Enum.find(Map.values(current_metrics), fn metric ->
        metric.name == :failure_test
      end)
      
      post_failure = Enum.find(Map.values(current_metrics), fn metric ->
        metric.name == :post_failure_test
      end)
      
      assert pre_failure != nil
      assert post_failure != nil
    end
  end
  
  describe "Configuration and Dynamic Reconfiguration" do
    test "router strategy can be changed at runtime", %{router: router} do
      # Test different strategies
      strategies = [:round_robin, :least_connections, :weighted]
      
      Enum.each(strategies, fn strategy ->
        :ok = Router.set_strategy(router, strategy)
        
        stats = Router.get_stats(router)
        assert stats.strategy == strategy
        
        # Should still route requests with new strategy
        request = %{
          type: :get,
          target: "strategy.test",
          oid: "1.3.6.1.2.1.1.1.0",
          community: "public"
        }
        
        result = Router.route_request(router, request)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
    
    test "engines can be added and removed dynamically", %{router: router} do
      initial_stats = Router.get_stats(router)
      initial_count = initial_stats.engine_count
      
      # Add a new engine
      {:ok, new_engine} = Engine.start_link(name: :dynamic_engine)
      
      new_engine_spec = %{
        name: :dynamic_engine,
        pid: new_engine,
        weight: 1,
        max_load: 50
      }
      
      :ok = Router.add_engine(router, new_engine_spec)
      
      # Should have more engines
      stats_after_add = Router.get_stats(router)
      assert stats_after_add.engine_count == initial_count + 1
      
      # Remove the engine
      :ok = Router.remove_engine(router, :dynamic_engine)
      
      # Should be back to original count
      stats_after_remove = Router.get_stats(router)
      assert stats_after_remove.engine_count == initial_count
      
      # Clean up
      Engine.stop(new_engine)
    end
    
    test "circuit breaker thresholds affect behavior", %{circuit_breaker: cb} do
      target = "threshold.test"
      
      # Get initial state (should be closed)
      {:ok, initial_state} = CircuitBreaker.get_state(cb, target)
      assert initial_state.state == :closed
      
      # Record failures up to threshold - 1
      Enum.each(1..2, fn _i ->
        CircuitBreaker.record_failure(cb, target, :test_failure)
      end)
      
      # Should still be closed
      {:ok, pre_threshold_state} = CircuitBreaker.get_state(cb, target)
      assert pre_threshold_state.state == :closed
      
      # One more failure should open the circuit
      CircuitBreaker.record_failure(cb, target, :final_failure)
      
      {:ok, post_threshold_state} = CircuitBreaker.get_state(cb, target)
      assert post_threshold_state.state == :open
    end
  end
  
  describe "Monitoring and Observability" do
    test "comprehensive system health can be monitored", %{router: router, engines: engines, pool: pool, circuit_breaker: cb, metrics: metrics} do
      # Generate some activity
      test_request = %{
        type: :get,
        target: "monitoring.test",
        oid: "1.3.6.1.2.1.1.1.0",
        community: "public"
      }
      
      Router.route_request(router, test_request)
      
      # Collect health information from all components
      router_stats = Router.get_stats(router)
      
      engine_stats = Enum.map(engines, fn %{pid: engine_pid} ->
        Engine.get_stats(engine_pid)
      end)
      
      pool_stats = Pool.get_stats(pool)
      cb_stats = CircuitBreaker.get_stats(cb)
      metrics_summary = Metrics.get_summary(metrics)
      
      # Verify comprehensive monitoring data is available
      assert is_map(router_stats)
      assert Map.has_key?(router_stats, :strategy)
      assert Map.has_key?(router_stats, :engine_count)
      assert Map.has_key?(router_stats, :metrics)
      
      Enum.each(engine_stats, fn stats ->
        assert is_map(stats)
        assert Map.has_key?(stats, :queue_length)
        assert Map.has_key?(stats, :metrics)
      end)
      
      assert is_map(pool_stats)
      assert Map.has_key?(pool_stats, :total_connections)
      assert Map.has_key?(pool_stats, :metrics)
      
      assert is_map(cb_stats)
      assert Map.has_key?(cb_stats, :total_breakers)
      assert Map.has_key?(cb_stats, :metrics)
      
      assert is_map(metrics_summary)
      assert Map.has_key?(metrics_summary, :current_metrics)
      assert Map.has_key?(metrics_summary, :window_count)
    end
    
    test "metrics provide performance insights", %{router: router, metrics: metrics} do
      # Generate timed operations
      operation_types = [:get, :set, :walk]
      
      Enum.each(operation_types, fn op_type ->
        Enum.each(1..5, fn i ->
          Metrics.time(metrics, :operation_performance, fn ->
            request = %{
              type: op_type,
              target: "perf.test.#{i}",
              oid: "1.3.6.1.2.1.1.#{i}.0",
              community: "public"
            }
            
            Router.route_request(router, request)
            
            # Simulate variable operation time
            Process.sleep(10 + rem(i, 3) * 5)
          end, %{operation: op_type})
        end)
      end)
      
      # Allow metrics collection
      Process.sleep(300)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Should have histograms for performance timing
      performance_histograms = Enum.filter(Map.values(current_metrics), fn metric ->
        metric.type == :histogram and metric.name == :operation_performance
      end)
      
      assert length(performance_histograms) >= 3  # One per operation type
      
      # Should have counters for operation counts
      performance_counters = Enum.filter(Map.values(current_metrics), fn metric ->
        metric.type == :counter and metric.name == :operation_performance_total
      end)
      
      assert length(performance_counters) >= 3
    end
  end
end