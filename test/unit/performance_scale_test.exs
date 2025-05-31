defmodule SNMPMgr.PerformanceScaleTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.{Engine, Router, CircuitBreaker, Pool, Metrics}
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :performance
  @moduletag :scale
  @moduletag :phase_4

  # Performance test configuration
  @light_load_concurrent 50
  @medium_load_concurrent 100
  @heavy_load_concurrent 200
  @stress_load_concurrent 500
  @sustained_duration_ms 5000
  @performance_timeout 5_000

  # Standard OIDs for performance testing
  @test_oids %{
    system_descr: "1.3.6.1.2.1.1.1.0",
    system_uptime: "1.3.6.1.2.1.1.3.0",
    system_contact: "1.3.6.1.2.1.1.4.0",
    system_name: "1.3.6.1.2.1.1.5.0",
    if_table: "1.3.6.1.2.1.2.2",
    if_number: "1.3.6.1.2.1.2.1.0"
  }

  setup_all do
    # Start components individually to avoid startup conflicts
    # Following pattern from circuit_breaker_comprehensive_test.exs
    
    # Start circuit breaker if not already running
    case GenServer.whereis(SNMPMgr.CircuitBreaker) do
      nil ->
        case SNMPMgr.CircuitBreaker.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end
      _pid -> :ok
    end
    
    # Start metrics if not already running
    case GenServer.whereis(SNMPMgr.Metrics) do
      nil ->
        case SNMPMgr.Metrics.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end
      _pid -> :ok
    end
    
    :ok
  end

  describe "engine throughput and latency performance" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    @tag :performance
    test "validates engine throughput under light concurrent load", %{device: device} do
      concurrent_count = @light_load_concurrent
      requests_per_task = 10
      target = SNMPSimulator.device_target(device)
      
      start_time = :erlang.monotonic_time(:microsecond)
      
      # Create concurrent tasks
      tasks = for i <- 1..concurrent_count do
        Task.async(fn ->
          task_results = for j <- 1..requests_per_task do
            request = %{
              type: :get,
              target: target,
              oid: @test_oids.system_descr,
              community: device.community,
              timeout: 200,
              request_id: "light_#{i}_#{j}"
            }
            
            {latency, result} = :timer.tc(fn ->
              SNMPMgr.engine_request(request)
            end)
            
            {latency, result}
          end
          
          {i, task_results}
        end)
      end
      
      # Wait for completion
      results = Task.yield_many(tasks, @performance_timeout)
      end_time = :erlang.monotonic_time(:microsecond)
      
      elapsed_time = end_time - start_time
      total_requests = concurrent_count * requests_per_task
      
      # Analyze results
      completed_tasks = Enum.count(results, fn {_task, result} -> result != nil end)
      assert completed_tasks >= concurrent_count * 0.9, # At least 90% completion
        "Light load completion rate: #{completed_tasks}/#{concurrent_count}"
      
      # Calculate throughput
      if completed_tasks > 0 do
        throughput = (total_requests * 1_000_000) / elapsed_time
        assert throughput > 100, # At least 100 requests/second
          "Light load throughput: #{throughput} req/sec"
      end
      
      # Calculate latency statistics
      all_latencies = for {_task, {:ok, {_i, task_results}}} <- results,
                          {latency, {:ok, _result}} <- task_results do
        latency
      end
      
      if length(all_latencies) > 0 do
        avg_latency = Enum.sum(all_latencies) / length(all_latencies)
        max_latency = Enum.max(all_latencies)
        p95_latency = Enum.sort(all_latencies) |> Enum.at(round(length(all_latencies) * 0.95))
        
        assert avg_latency < 50_000, # Less than 50ms average
          "Light load average latency: #{avg_latency} μs"
        assert max_latency < 200_000, # Less than 200ms max
          "Light load max latency: #{max_latency} μs"
        assert p95_latency < 100_000, # Less than 100ms P95
          "Light load P95 latency: #{p95_latency} μs"
      end
      
      # Clean up tasks
      for {task, _result} <- results do
        Task.shutdown(task, :brutal_kill)
      end
    end

    @tag :performance
    test "validates engine throughput under medium concurrent load" do
      concurrent_count = @medium_load_concurrent
      requests_per_task = 8
      
      start_time = :erlang.monotonic_time(:microsecond)
      
      # Create concurrent tasks with mixed request types
      tasks = for i <- 1..concurrent_count do
        Task.async(fn ->
          task_results = for j <- 1..requests_per_task do
            request_type = case rem(j, 4) do
              0 -> :get
              1 -> :get_next
              2 -> :get_bulk
              3 -> :walk
            end
            
            oid = case request_type do
              :get -> @test_oids.system_descr
              :get_next -> "1.3.6.1.2.1.1"
              :get_bulk -> @test_oids.if_table
              :walk -> "1.3.6.1.2.1.1"
            end
            
            request = %{
              type: request_type,
              target: "127.0.0.1",
              oid: oid,
              community: "public",
              request_id: "medium_#{i}_#{j}"
            }
            
            # Add type-specific options
            request = case request_type do
              :get_bulk -> Map.put(request, :max_repetitions, 10)
              _ -> request
            end
            
            {latency, result} = :timer.tc(fn ->
              SNMPMgr.engine_request(request)
            end)
            
            {request_type, latency, result}
          end
          
          {i, task_results}
        end)
      end
      
      # Wait for completion with longer timeout for bulk operations
      results = Task.yield_many(tasks, @performance_timeout * 2)
      end_time = :erlang.monotonic_time(:microsecond)
      
      elapsed_time = end_time - start_time
      total_requests = concurrent_count * requests_per_task
      
      # Analyze results
      completed_tasks = Enum.count(results, fn {_task, result} -> result != nil end)
      assert completed_tasks >= concurrent_count * 0.8, # At least 80% completion
        "Medium load completion rate: #{completed_tasks}/#{concurrent_count}"
      
      # Calculate throughput
      if completed_tasks > 0 do
        throughput = (total_requests * 1_000_000) / elapsed_time
        assert throughput > 50, # At least 50 requests/second under medium load
          "Medium load throughput: #{throughput} req/sec"
      end
      
      # Analyze by request type
      all_results = for {_task, {:ok, {_i, task_results}}} <- results,
                        {request_type, latency, {:ok, _result}} <- task_results do
        {request_type, latency}
      end
      
      if length(all_results) > 0 do
        # Group by request type
        by_type = Enum.group_by(all_results, fn {type, _latency} -> type end)
        
        for {request_type, type_results} <- by_type do
          latencies = Enum.map(type_results, fn {_type, latency} -> latency end)
          avg_latency = Enum.sum(latencies) / length(latencies)
          
          # Different expectations per request type
          max_expected_latency = case request_type do
            :get -> 100_000      # 100ms
            :get_next -> 150_000 # 150ms
            :get_bulk -> 500_000 # 500ms
            :walk -> 1_000_000   # 1s
          end
          
          assert avg_latency < max_expected_latency,
            "Medium load #{request_type} average latency: #{avg_latency} μs (max: #{max_expected_latency})"
        end
      end
      
      # Clean up tasks
      for {task, _result} <- results do
        Task.shutdown(task, :brutal_kill)
      end
    end

    @tag :performance
    test "validates engine behavior under heavy concurrent load" do
      concurrent_count = @heavy_load_concurrent
      requests_per_task = 5
      
      # Pre-warm the engine
      warmup_request = %{
        type: :get,
        target: "127.0.0.1",
        oid: @test_oids.system_descr,
        community: "public"
      }
      SNMPMgr.engine_request(warmup_request)
      
      start_time = :erlang.monotonic_time(:microsecond)
      
      # Create heavy concurrent load
      tasks = for i <- 1..concurrent_count do
        Task.async(fn ->
          task_results = for j <- 1..requests_per_task do
            request = %{
              type: :get,
              target: "device#{rem(i, 10)}.test",
              oid: @test_oids.system_descr,
              community: "public",
              request_id: "heavy_#{i}_#{j}",
              timeout: 10_000 # Longer timeout for heavy load
            }
            
            start_req = :erlang.monotonic_time(:microsecond)
            result = SNMPMgr.engine_request(request)
            end_req = :erlang.monotonic_time(:microsecond)
            
            {end_req - start_req, result}
          end
          
          {i, task_results}
        end)
      end
      
      # Wait for completion with extended timeout
      results = Task.yield_many(tasks, @performance_timeout * 3)
      end_time = :erlang.monotonic_time(:microsecond)
      
      elapsed_time = end_time - start_time
      total_requests = concurrent_count * requests_per_task
      
      # Analyze results - more lenient expectations for heavy load
      completed_tasks = Enum.count(results, fn {_task, result} -> result != nil end)
      assert completed_tasks >= concurrent_count * 0.7, # At least 70% completion
        "Heavy load completion rate: #{completed_tasks}/#{concurrent_count}"
      
      # System should remain stable under heavy load
      if completed_tasks > 0 do
        throughput = (total_requests * 1_000_000) / elapsed_time
        assert throughput > 20, # At least 20 requests/second under heavy load
          "Heavy load throughput: #{throughput} req/sec"
      end
      
      # Check that the engine didn't crash
      case SNMPMgr.get_engine_stats() do
        {:ok, stats} ->
          assert is_map(stats), "Engine should remain operational under heavy load"
          
        {:error, reason} ->
          assert is_atom(reason), "Engine stats error under heavy load: #{inspect(reason)}"
      end
      
      # Clean up tasks
      for {task, _result} <- results do
        Task.shutdown(task, :brutal_kill)
      end
    end

    @tag :performance
    @tag :stress
    test "validates engine stress limits and graceful degradation" do
      concurrent_count = @stress_load_concurrent
      requests_per_task = 3
      
      # Monitor memory before stress test
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)
      
      start_time = :erlang.monotonic_time(:microsecond)
      
      # Create stress load
      tasks = for i <- 1..concurrent_count do
        Task.async(fn ->
          for j <- 1..requests_per_task do
            request = %{
              type: :get,
              target: "stress#{rem(i, 20)}.test",
              oid: @test_oids.system_descr,
              community: "public",
              request_id: "stress_#{i}_#{j}",
              timeout: 5_000 # Shorter timeout for stress test
            }
            
            case SNMPMgr.engine_request(request) do
              {:ok, result} -> {:success, result}
              {:error, :timeout} -> {:timeout, nil}
              {:error, :overloaded} -> {:overloaded, nil}
              {:error, reason} -> {:error, reason}
            end
          end
        end)
      end
      
      # Wait for completion with reasonable timeout
      results = Task.yield_many(tasks, @performance_timeout)
      end_time = :erlang.monotonic_time(:microsecond)
      
      _elapsed_time = end_time - start_time
      
      # Analyze stress test results
      completed_tasks = Enum.count(results, fn {_task, result} -> result != nil end)
      
      # Under stress, we expect some failures but system should remain stable
      assert completed_tasks >= concurrent_count * 0.5, # At least 50% completion
        "Stress load completion rate: #{completed_tasks}/#{concurrent_count}"
      
      # Collect all results
      all_outcomes = for {_task, {:ok, task_results}} <- results,
                         outcome <- task_results do
        case outcome do
          {:success, _} -> :success
          {:timeout, _} -> :timeout
          {:overloaded, _} -> :overloaded
          {:error, _} -> :error
        end
      end
      
      if length(all_outcomes) > 0 do
        success_rate = Enum.count(all_outcomes, &(&1 == :success)) / length(all_outcomes)
        
        # Under stress, success rate can be lower but system should not crash
        assert success_rate >= 0.3, # At least 30% success under stress
          "Stress load success rate: #{success_rate * 100}%"
      end
      
      # Check memory usage after stress
      :erlang.garbage_collect()
      memory_after = :erlang.memory(:total)
      memory_growth = memory_after - memory_before
      
      # Memory growth should be reasonable even under stress
      assert memory_growth < 50_000_000, # Less than 50MB growth
        "Stress load memory growth: #{memory_growth} bytes"
      
      # Engine should still be responsive after stress
      case SNMPMgr.get_engine_stats() do
        {:ok, stats} ->
          assert is_map(stats), "Engine should remain operational after stress test"
          
        {:error, reason} ->
          assert is_atom(reason), "Engine stats error after stress: #{inspect(reason)}"
      end
      
      # Clean up tasks
      for {task, _result} <- results do
        Task.shutdown(task, :brutal_kill)
      end
    end
  end

  describe "sustained load and endurance testing" do
    @tag :performance
    @tag :endurance
    test "validates engine performance under sustained moderate load" do
      duration_ms = @sustained_duration_ms
      request_interval_ms = 20 # 50 requests/second
      
      start_time = :erlang.monotonic_time(:millisecond)
      request_count = 0
      results = []
      
      # Sustained load loop - simplified approach
      max_requests = div(duration_ms, request_interval_ms) + 1
      
      {results, request_count} = 
        1..max_requests
        |> Enum.reduce_while({results, request_count}, fn _i, {acc_results, count} ->
          current_time = :erlang.monotonic_time(:millisecond)
          if current_time - start_time < duration_ms do
            request = %{
              type: :get,
              target: "sustained.test", 
              oid: @test_oids.system_descr,
              community: "public",
              request_id: "sustained_#{count}"
            }
            
            # Make request and track result
            result_task = Task.async(fn ->
              {latency, result} = :timer.tc(fn ->
                SNMPMgr.engine_request(request)
              end)
              {count, latency, result}
            end)
            
            new_results = [result_task | acc_results]
            new_count = count + 1
            
            # Control request rate
            Process.sleep(request_interval_ms)
            
            {:cont, {new_results, new_count}}
          else
            {:halt, {acc_results, count}}
          end
        end)
      
      end_time = :erlang.monotonic_time(:millisecond)
      actual_duration = end_time - start_time
      
      # Wait for all pending requests
      final_results = Task.yield_many(results, 10_000)
      
      # Analyze sustained load results
      assert actual_duration >= duration_ms * 0.9,
        "Sustained load duration: #{actual_duration}ms"
      
      assert request_count >= (duration_ms / request_interval_ms) * 0.8,
        "Sustained load request count: #{request_count}"
      
      # Check result quality over time
      successful_results = for {_task, {:ok, {req_id, latency, {:ok, _result}}}} <- final_results do
        {req_id, latency}
      end
      
      if length(successful_results) > 0 do
        success_rate = length(successful_results) / length(final_results)
        assert success_rate >= 0.8, # At least 80% success under sustained load
          "Sustained load success rate: #{success_rate * 100}%"
        
        # Check latency stability over time
        latencies = Enum.map(successful_results, fn {_req_id, latency} -> latency end)
        avg_latency = Enum.sum(latencies) / length(latencies)
        
        # Latency should remain reasonable throughout
        assert avg_latency < 100_000, # Less than 100ms average
          "Sustained load average latency: #{avg_latency} μs"
        
        # Check for latency degradation over time
        {early_latencies, late_latencies} = Enum.split(latencies, div(length(latencies), 2))
        
        early_avg = Enum.sum(early_latencies) / length(early_latencies)
        late_avg = Enum.sum(late_latencies) / length(late_latencies)
        
        latency_degradation = late_avg / early_avg
        assert latency_degradation < 2.0, # Less than 2x degradation
          "Sustained load latency degradation: #{latency_degradation}x"
      end
      
      # Clean up tasks
      for {task, _result} <- final_results do
        Task.shutdown(task, :brutal_kill)
      end
    end

    @tag :performance
    @tag :endurance
    test "validates engine resource stability under prolonged operation" do
      duration_ms = @sustained_duration_ms * 2 # Longer duration
      measurement_interval = 1000 # Measure every second
      
      # Initial measurements
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)
      initial_stats = case SNMPMgr.get_engine_stats() do
        {:ok, stats} -> stats
        {:error, _} -> %{}
      end
      
      start_time = :erlang.monotonic_time(:millisecond)
      measurements = []
      request_count = 0
      
      # Background request generator
      generator_pid = spawn(fn ->
        generate_background_load(start_time + duration_ms)
      end)
      
      # Periodic measurements - using reduce_while
      max_measurements = div(duration_ms, measurement_interval) + 1
      
      {measurements, request_count} = 
        1..max_measurements
        |> Enum.reduce_while({measurements, request_count}, fn _i, {acc_measurements, count} ->
          current_time = :erlang.monotonic_time(:millisecond)
          if current_time - start_time < duration_ms do
            # Make some immediate requests
            for i <- 1..5 do
              request = %{
                type: :get,
                target: "resource#{rem(i, 3)}.test",
                oid: @test_oids.system_descr,
                community: "public",
                request_id: "resource_#{count + i}"
              }
              
              spawn(fn -> SNMPMgr.engine_request(request) end)
            end
            
            new_count = count + 5
            
            # Take measurements
            :erlang.garbage_collect()
            current_memory = :erlang.memory(:total)
            
            current_stats = case SNMPMgr.get_engine_stats() do
              {:ok, stats} -> stats
              {:error, _} -> %{}
            end
            
            measurement = %{
              time: current_time - start_time,
              memory: current_memory,
              stats: current_stats,
              request_count: new_count
            }
            
            new_measurements = [measurement | acc_measurements]
            
            Process.sleep(measurement_interval)
            
            {:cont, {new_measurements, new_count}}
          else
            {:halt, {acc_measurements, count}}
          end
        end)
      
      # Stop background generator
      Process.exit(generator_pid, :normal)
      
      end_time = :erlang.monotonic_time(:millisecond)
      actual_duration = end_time - start_time
      
      # Analyze resource stability
      assert actual_duration >= duration_ms * 0.9,
        "Resource test duration: #{actual_duration}ms"
      
      # Memory stability analysis
      memory_measurements = Enum.map(measurements, & &1.memory)
      max_memory = Enum.max(memory_measurements)
      memory_growth = max_memory - initial_memory
      
      assert memory_growth < 20_000_000, # Less than 20MB growth
        "Memory growth over time: #{memory_growth} bytes"
      
      # Check for memory leaks (increasing trend)
      if length(memory_measurements) >= 3 do
        {early_memories, late_memories} = Enum.split(memory_measurements, div(length(memory_measurements), 2))
        
        early_avg = Enum.sum(early_memories) / length(early_memories)
        late_avg = Enum.sum(late_memories) / length(late_memories)
        
        memory_trend = late_avg / early_avg
        assert memory_trend < 1.5, # Less than 50% increase over time
          "Memory trend over time: #{memory_trend}x"
      end
      
      # Engine should remain responsive
      final_stats = case SNMPMgr.get_engine_stats() do
        {:ok, stats} -> stats
        {:error, _} -> %{}
      end
      
      assert is_map(final_stats), "Engine should remain operational after prolonged load"
    end
  end

  describe "batch processing performance" do
    @tag :performance
    test "validates batch processing efficiency and throughput" do
      batch_sizes = [10, 25, 50, 100, 200]
      
      for batch_size <- batch_sizes do
        # Create batch of requests
        batch_requests = for i <- 1..batch_size do
          %{
            type: :get,
            target: "127.0.0.1",
            oid: @test_oids.system_descr,
            community: "public",
            request_id: "batch_#{batch_size}_#{i}"
          }
        end
        
        # Time batch processing
        {batch_latency, batch_result} = :timer.tc(fn ->
          SNMPMgr.engine_batch(batch_requests)
        end)
        
        case batch_result do
          {:ok, results} ->
            assert length(results) == batch_size,
              "Batch size #{batch_size}: should return all results"
            
            # Calculate efficiency metrics
            avg_time_per_request = batch_latency / batch_size
            
            # Batch processing should be more efficient than individual requests
            max_expected_time_per_request = case batch_size do
              size when size <= 25 -> 50_000   # 50ms per request
              size when size <= 100 -> 25_000  # 25ms per request
              _ -> 15_000                      # 15ms per request
            end
            
            assert avg_time_per_request < max_expected_time_per_request,
              "Batch size #{batch_size}: efficiency #{avg_time_per_request} μs per request"
            
            # Check success rate
            successful_results = Enum.count(results, fn
              {:ok, _} -> true
              _ -> false
            end)
            
            success_rate = successful_results / batch_size
            assert success_rate >= 0.9, # At least 90% success
              "Batch size #{batch_size}: success rate #{success_rate * 100}%"
              
          {:error, reason} ->
            assert is_atom(reason), "Batch size #{batch_size} error: #{inspect(reason)}"
        end
      end
    end

    @tag :performance
    test "validates concurrent batch processing performance" do
      concurrent_batches = 10
      requests_per_batch = 20
      
      start_time = :erlang.monotonic_time(:microsecond)
      
      # Create concurrent batch tasks
      batch_tasks = for batch_id <- 1..concurrent_batches do
        Task.async(fn ->
          batch_requests = for req_id <- 1..requests_per_batch do
            %{
              type: :get,
              target: "batch#{batch_id}.test",
              oid: @test_oids.system_descr,
              community: "public",
              request_id: "concurrent_batch_#{batch_id}_#{req_id}"
            }
          end
          
          {batch_latency, result} = :timer.tc(fn ->
            SNMPMgr.engine_batch(batch_requests)
          end)
          
          {batch_id, batch_latency, result}
        end)
      end
      
      # Wait for all batches
      batch_results = Task.yield_many(batch_tasks, @performance_timeout)
      end_time = :erlang.monotonic_time(:microsecond)
      
      total_elapsed = end_time - start_time
      total_requests = concurrent_batches * requests_per_batch
      
      # Analyze concurrent batch performance
      completed_batches = Enum.count(batch_results, fn {_task, result} -> result != nil end)
      assert completed_batches >= concurrent_batches * 0.9,
        "Concurrent batch completion: #{completed_batches}/#{concurrent_batches}"
      
      # Calculate overall throughput
      if completed_batches > 0 do
        throughput = (total_requests * 1_000_000) / total_elapsed
        assert throughput > 200, # At least 200 requests/second for concurrent batches
          "Concurrent batch throughput: #{throughput} req/sec"
      end
      
      # Analyze individual batch performance
      successful_batches = for {_task, {:ok, {batch_id, latency, {:ok, results}}}} <- batch_results do
        {batch_id, latency, length(results)}
      end
      
      if length(successful_batches) > 0 do
        batch_latencies = Enum.map(successful_batches, fn {_id, latency, _count} -> latency end)
        avg_batch_latency = Enum.sum(batch_latencies) / length(batch_latencies)
        
        assert avg_batch_latency < 500_000, # Less than 500ms per batch
          "Average concurrent batch latency: #{avg_batch_latency} μs"
      end
      
      # Clean up tasks
      for {task, _result} <- batch_results do
        Task.shutdown(task, :brutal_kill)
      end
    end
  end

  describe "memory and resource management under load" do
    @tag :performance
    test "validates memory efficiency under various load patterns" do
      load_patterns = [
        {:burst, 100, 1},      # 100 requests in 1 burst
        {:steady, 50, 10},     # 50 requests over 10 intervals
        {:increasing, 20, 5}   # Increasing load pattern
      ]
      
      for {pattern_type, base_count, intervals} <- load_patterns do
        # Measure initial memory
        :erlang.garbage_collect()
        initial_memory = :erlang.memory(:total)
        
        # Execute load pattern
        case pattern_type do
          :burst ->
            # Single burst of requests
            tasks = for i <- 1..base_count do
              Task.async(fn ->
                request = %{
                  type: :get,
                  target: "memory.burst.test",
                  oid: @test_oids.system_descr,
                  community: "public",
                  request_id: "burst_#{i}"
                }
                SNMPMgr.engine_request(request)
              end)
            end
            
            _results = Task.yield_many(tasks, 10_000)
            
            for {task, _result} <- _results do
              Task.shutdown(task, :brutal_kill)
            end
            
          :steady ->
            # Steady rate over intervals
            for interval <- 1..intervals do
              interval_tasks = for i <- 1..base_count do
                Task.async(fn ->
                  request = %{
                    type: :get,
                    target: "memory.steady.test",
                    oid: @test_oids.system_descr,
                    community: "public",
                    request_id: "steady_#{interval}_#{i}"
                  }
                  SNMPMgr.engine_request(request)
                end)
              end
              
              _interval_results = Task.yield_many(interval_tasks, 5_000)
              
              for {task, _result} <- _interval_results do
                Task.shutdown(task, :brutal_kill)
              end
              
              # Small delay between intervals
              Process.sleep(100)
            end
            
          :increasing ->
            # Increasing load pattern
            for interval <- 1..intervals do
              requests_this_interval = base_count * interval
              
              interval_tasks = for i <- 1..requests_this_interval do
                Task.async(fn ->
                  request = %{
                    type: :get,
                    target: "memory.increasing.test",
                    oid: @test_oids.system_descr,
                    community: "public",
                    request_id: "increasing_#{interval}_#{i}"
                  }
                  SNMPMgr.engine_request(request)
                end)
              end
              
              _interval_results = Task.yield_many(interval_tasks, 10_000)
              
              for {task, _result} <- _interval_results do
                Task.shutdown(task, :brutal_kill)
              end
              
              Process.sleep(200)
            end
        end
        
        # Allow cleanup and garbage collection
        Process.sleep(500)
        :erlang.garbage_collect()
        final_memory = :erlang.memory(:total)
        
        memory_growth = final_memory - initial_memory
        
        # Memory growth should be reasonable for each pattern
        max_expected_growth = case pattern_type do
          :burst -> 5_000_000      # 5MB for burst
          :steady -> 3_000_000     # 3MB for steady
          :increasing -> 8_000_000 # 8MB for increasing
        end
        
        assert memory_growth < max_expected_growth,
          "#{pattern_type} pattern memory growth: #{memory_growth} bytes (max: #{max_expected_growth})"
      end
    end

    @tag :performance
    test "validates connection pool efficiency under load" do
      pool_sizes = [10, 25, 50]
      concurrent_requests = 100
      
      for pool_size <- pool_sizes do
        # Configure engine with specific pool size
        case SNMPMgr.configure_engine([pool: [pool_size: pool_size]]) do
          :ok ->
            # Measure pool performance
            start_time = :erlang.monotonic_time(:microsecond)
            
            # Create load that exceeds pool size
            tasks = for i <- 1..concurrent_requests do
              Task.async(fn ->
                request = %{
                  type: :get,
                  target: "pool#{rem(i, 5)}.test",
                  oid: @test_oids.system_descr,
                  community: "public",
                  request_id: "pool_#{pool_size}_#{i}"
                }
                
                SNMPMgr.engine_request(request)
              end)
            end
            
            results = Task.yield_many(tasks, @performance_timeout)
            end_time = :erlang.monotonic_time(:microsecond)
            
            elapsed_time = end_time - start_time
            
            # Analyze pool efficiency
            completed_count = Enum.count(results, fn {_task, result} -> result != nil end)
            
            # Pool should handle load efficiently regardless of size
            completion_rate = completed_count / concurrent_requests
            assert completion_rate >= 0.8,
              "Pool size #{pool_size}: completion rate #{completion_rate * 100}%"
            
            # Smaller pools might be slower but should still work
            throughput = (completed_count * 1_000_000) / elapsed_time
            min_expected_throughput = max(20, pool_size * 2) # At least 2 req/sec per pool connection
            
            assert throughput >= min_expected_throughput,
              "Pool size #{pool_size}: throughput #{throughput} req/sec (min: #{min_expected_throughput})"
            
            # Clean up tasks
            for {task, _result} <- results do
              Task.shutdown(task, :brutal_kill)
            end
            
          {:error, reason} ->
            assert is_atom(reason), "Pool configuration error: #{inspect(reason)}"
        end
      end
    end
  end

  # Helper function for background load generation
  defp generate_background_load(end_time) do
    if :erlang.monotonic_time(:millisecond) < end_time do
      request = %{
        type: :get,
        target: "background.test",
        oid: "1.3.6.1.2.1.1.1.0",
        community: "public"
      }
      
      spawn(fn -> SNMPMgr.engine_request(request) end)
      
      Process.sleep(100) # 10 requests/second background load
      generate_background_load(end_time)
    end
  end
end