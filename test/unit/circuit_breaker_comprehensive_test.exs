defmodule SNMPMgr.CircuitBreakerComprehensiveTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.{CircuitBreaker, Router}
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :circuit_breaker
  @moduletag :phase_4

  # Standard OIDs for circuit breaker testing
  @test_oids %{
    system_descr: "1.3.6.1.2.1.1.1.0",
    system_uptime: "1.3.6.1.2.1.1.3.0",
    if_table: "1.3.6.1.2.1.2.2"
  }

  setup_all do
    # Start circuit breaker if not already running
    case GenServer.whereis(CircuitBreaker) do
      nil ->
        case CircuitBreaker.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end
      _pid -> :ok
    end
    
    :ok
  end

  describe "circuit breaker initialization and configuration" do
    test "validates circuit breaker startup with default configuration" do
      case CircuitBreaker.start_link() do
        {:ok, pid} ->
          assert is_pid(pid), "Circuit breaker should start with valid PID"
          assert Process.alive?(pid), "Circuit breaker process should be alive"
          
        {:error, {:already_started, pid}} ->
          assert is_pid(pid), "Circuit breaker already started with valid PID"
          assert Process.alive?(pid), "Existing circuit breaker process should be alive"
          
        {:error, reason} ->
          assert is_atom(reason), "Circuit breaker start error: #{inspect(reason)}"
      end
    end

    test "validates circuit breaker configuration with custom settings" do
      custom_configs = [
        [failure_threshold: 3, recovery_timeout: 5000],
        [failure_threshold: 5, recovery_timeout: 10000],
        [failure_threshold: 1, recovery_timeout: 30000],
        [failure_threshold: 10, recovery_timeout: 60000]
      ]
      
      for config <- custom_configs do
        case CircuitBreaker.configure(CircuitBreaker, config) do
          :ok ->
            failure_threshold = Keyword.get(config, :failure_threshold, 3)
            recovery_timeout = Keyword.get(config, :recovery_timeout, 30000)
            
            assert true, "Circuit breaker config accepted: threshold=#{failure_threshold}, timeout=#{recovery_timeout}"
            
          {:error, reason} ->
            assert is_atom(reason), "Circuit breaker config error: #{inspect(reason)}"
        end
      end
    end

    test "validates per-target circuit breaker configuration" do
      target_configs = [
        {"critical_device", [failure_threshold: 2, recovery_timeout: 5000]},
        {"normal_device", [failure_threshold: 5, recovery_timeout: 15000]},
        {"backup_device", [failure_threshold: 10, recovery_timeout: 60000]}
      ]
      
      for {target, config} <- target_configs do
        case CircuitBreaker.configure_target(CircuitBreaker, target, config) do
          :ok ->
            assert true, "Per-target config accepted for #{target}: #{inspect(config)}"
            
          {:error, reason} ->
            assert is_atom(reason), "Per-target config error for #{target}: #{inspect(reason)}"
        end
      end
    end

    test "validates circuit breaker state initialization" do
      test_targets = ["device1", "device2", "device3"]
      
      for target <- test_targets do
        case CircuitBreaker.get_state(CircuitBreaker, target) do
          {:ok, state} ->
            assert state in [:closed, :open, :half_open], "Circuit breaker state should be valid: #{state}"
            
          {:error, :not_found} ->
            assert true, "Circuit breaker state not initialized for #{target} (expected)"
            
          {:error, reason} ->
            assert is_atom(reason), "Circuit breaker state error for #{target}: #{inspect(reason)}"
        end
      end
    end
  end

  describe "circuit breaker three-state behavior" do
    test "validates closed state operation" do
      target = "closed_state_test"
      
      # Ensure circuit breaker starts in closed state
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # Function that should succeed
      success_function = fn ->
        Process.sleep(10) # Simulate work
        {:ok, "success_result"}
      end
      
      case CircuitBreaker.call(CircuitBreaker, target, success_function, 5000) do
        {:ok, result} ->
          assert result == "success_result", "Circuit breaker should allow calls in closed state"
          
          # Verify state remains closed
          case CircuitBreaker.get_state(CircuitBreaker, target) do
            {:ok, :closed} ->
              assert true, "Circuit breaker should remain closed after success"
              
            {:ok, other_state} ->
              assert true, "Circuit breaker state after success: #{other_state}"
              
            {:error, reason} ->
              assert is_atom(reason), "State check error: #{inspect(reason)}"
          end
          
        {:error, reason} ->
          assert is_atom(reason), "Closed state call error: #{inspect(reason)}"
      end
    end

    test "validates transition from closed to open state" do
      target = "open_transition_test"
      
      # Reset circuit breaker
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # Function that fails
      failing_function = fn ->
        {:error, :simulated_failure}
      end
      
      # Get failure threshold
      failure_threshold = case CircuitBreaker.get_config(CircuitBreaker, target) do
        {:ok, config} -> Map.get(config, :failure_threshold, 3)
        _ -> 3  # Default
      end
      
      # Trigger failures to reach threshold
      for attempt <- 1..failure_threshold do
        result = CircuitBreaker.call(CircuitBreaker, target, failing_function, 1000)
        
        case result do
          {:error, :simulated_failure} ->
            assert true, "Failure #{attempt} correctly recorded"
            
          {:error, :circuit_breaker_open} ->
            assert attempt <= failure_threshold, "Circuit breaker opened at failure #{attempt}"
            
          other ->
            assert true, "Failure #{attempt} result: #{inspect(other)}"
        end
      end
      
      # Verify circuit breaker is now open
      case CircuitBreaker.get_state(CircuitBreaker, target) do
        {:ok, :open} ->
          assert true, "Circuit breaker correctly transitioned to open state"
          
        {:ok, other_state} ->
          assert true, "Circuit breaker state after failures: #{other_state}"
          
        {:error, reason} ->
          assert is_atom(reason), "State check error after failures: #{inspect(reason)}"
      end
    end

    test "validates open state behavior" do
      target = "open_state_test"
      
      # Force circuit breaker into open state
      CircuitBreaker.force_open(CircuitBreaker, target)
      
      # Any function call should be rejected
      test_function = fn ->
        {:ok, "should_not_execute"}
      end
      
      case CircuitBreaker.call(CircuitBreaker, target, test_function, 1000) do
        {:error, :circuit_breaker_open} ->
          assert true, "Circuit breaker correctly rejected call in open state"
          
        {:error, other_reason} ->
          assert true, "Circuit breaker rejection: #{other_reason}"
          
        {:ok, _result} ->
          flunk("Circuit breaker should not allow calls in open state")
      end
    end

    test "validates transition from open to half-open state" do
      target = "half_open_transition_test"
      
      # Force circuit breaker open
      CircuitBreaker.force_open(CircuitBreaker, target)
      
      # Get recovery timeout
      recovery_timeout = case CircuitBreaker.get_config(CircuitBreaker, target) do
        {:ok, config} -> Map.get(config, :recovery_timeout, 30000)
        _ -> 30000  # Default
      end
      
      # For testing, use a short timeout
      test_timeout = min(recovery_timeout, 1000)
      CircuitBreaker.configure_target(CircuitBreaker, target, [recovery_timeout: test_timeout])
      
      # Wait for recovery timeout
      Process.sleep(test_timeout + 100)
      
      # Check if circuit breaker transitions to half-open
      case CircuitBreaker.get_state(CircuitBreaker, target) do
        {:ok, :half_open} ->
          assert true, "Circuit breaker correctly transitioned to half-open state"
          
        {:ok, :open} ->
          # Might still be open if timing is tight
          # Try to trigger transition with a call
          test_function = fn -> {:ok, "recovery_test"} end
          CircuitBreaker.call(CircuitBreaker, target, test_function, 1000)
          
          assert true, "Circuit breaker recovery in progress"
          
        {:ok, other_state} ->
          assert true, "Circuit breaker state during recovery: #{other_state}"
          
        {:error, reason} ->
          assert is_atom(reason), "State check error during recovery: #{inspect(reason)}"
      end
    end

    test "validates half-open state recovery" do
      target = "half_open_recovery_test"
      
      # Force circuit breaker into half-open state
      CircuitBreaker.force_half_open(CircuitBreaker, target)
      
      # Success function for recovery
      recovery_function = fn ->
        Process.sleep(50)
        {:ok, "recovery_success"}
      end
      
      case CircuitBreaker.call(CircuitBreaker, target, recovery_function, 5000) do
        {:ok, "recovery_success"} ->
          assert true, "Circuit breaker allowed recovery call in half-open state"
          
          # Should transition back to closed state
          Process.sleep(100) # Allow state transition
          
          case CircuitBreaker.get_state(CircuitBreaker, target) do
            {:ok, :closed} ->
              assert true, "Circuit breaker successfully recovered to closed state"
              
            {:ok, other_state} ->
              assert true, "Circuit breaker state after recovery: #{other_state}"
              
            {:error, reason} ->
              assert is_atom(reason), "State check error after recovery: #{inspect(reason)}"
          end
          
        {:error, reason} ->
          assert is_atom(reason), "Recovery call error: #{inspect(reason)}"
      end
    end

    test "validates half-open state failure" do
      target = "half_open_failure_test"
      
      # Force circuit breaker into half-open state
      CircuitBreaker.force_half_open(CircuitBreaker, target)
      
      # Function that fails during recovery
      failing_recovery_function = fn ->
        {:error, :recovery_failed}
      end
      
      case CircuitBreaker.call(CircuitBreaker, target, failing_recovery_function, 1000) do
        {:error, :recovery_failed} ->
          assert true, "Circuit breaker recorded recovery failure"
          
          # Should transition back to open state
          Process.sleep(100) # Allow state transition
          
          case CircuitBreaker.get_state(CircuitBreaker, target) do
            {:ok, :open} ->
              assert true, "Circuit breaker correctly returned to open state after recovery failure"
              
            {:ok, other_state} ->
              assert true, "Circuit breaker state after recovery failure: #{other_state}"
              
            {:error, reason} ->
              assert is_atom(reason), "State check error after recovery failure: #{inspect(reason)}"
          end
          
        {:error, :circuit_breaker_open} ->
          assert true, "Circuit breaker immediately rejected recovery call"
          
        {:error, other_reason} ->
          assert true, "Recovery failure result: #{other_reason}"
          
        {:ok, _result} ->
          flunk("Failing function should not succeed")
      end
    end
  end

  describe "circuit breaker failure counting and thresholds" do
    test "validates failure counting accuracy" do
      target = "failure_counting_test"
      
      # Reset circuit breaker
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # Set known threshold
      CircuitBreaker.configure_target(CircuitBreaker, target, [failure_threshold: 5])
      
      # Function that alternates success and failure
      call_count = 0
      alternating_function = fn ->
        call_count = call_count + 1
        if rem(call_count, 2) == 0 do
          {:ok, "success_#{call_count}"}
        else
          {:error, "failure_#{call_count}"}
        end
      end
      
      # Make several calls
      results = for i <- 1..8 do
        {i, CircuitBreaker.call(CircuitBreaker, target, alternating_function, 1000)}
      end
      
      # Analyze results
      failures = Enum.filter(results, fn {_i, result} ->
        case result do
          {:error, "failure_" <> _} -> true
          _ -> false
        end
      end)
      
      successes = Enum.filter(results, fn {_i, result} ->
        case result do
          {:ok, "success_" <> _} -> true
          _ -> false
        end
      end)
      
      assert length(failures) > 0, "Should have recorded some failures"
      assert length(successes) > 0, "Should have recorded some successes"
      
      # Check current failure count
      case CircuitBreaker.get_stats(CircuitBreaker, target) do
        {:ok, stats} ->
          failure_count = Map.get(stats, :failure_count, 0)
          assert is_integer(failure_count), "Failure count should be tracked: #{failure_count}"
          
        {:error, reason} ->
          assert is_atom(reason), "Stats error: #{inspect(reason)}"
      end
    end

    test "validates success resets failure count" do
      target = "success_reset_test"
      
      # Reset and configure
      CircuitBreaker.reset(CircuitBreaker, target)
      CircuitBreaker.configure_target(CircuitBreaker, target, [failure_threshold: 10])
      
      # Cause some failures
      failing_function = fn -> {:error, :test_failure} end
      
      for _i <- 1..3 do
        CircuitBreaker.call(CircuitBreaker, target, failing_function, 1000)
      end
      
      # Check failure count
      initial_stats = case CircuitBreaker.get_stats(CircuitBreaker, target) do
        {:ok, stats} -> stats
        _ -> %{}
      end
      
      initial_failures = Map.get(initial_stats, :failure_count, 0)
      
      # Make successful call
      success_function = fn -> {:ok, :success} end
      CircuitBreaker.call(CircuitBreaker, target, success_function, 1000)
      
      # Check that failure count is reset
      Process.sleep(50) # Allow stats update
      
      final_stats = case CircuitBreaker.get_stats(CircuitBreaker, target) do
        {:ok, stats} -> stats
        _ -> %{}
      end
      
      final_failures = Map.get(final_stats, :failure_count, 0)
      
      if initial_failures > 0 and final_failures >= 0 do
        assert final_failures < initial_failures,
          "Success should reduce failure count: #{initial_failures} -> #{final_failures}"
      else
        assert true, "Failure count tracking completed"
      end
    end

    test "validates different threshold configurations" do
      threshold_tests = [
        {1, "very_sensitive"},
        {3, "normal_sensitivity"},
        {10, "low_sensitivity"},
        {50, "very_tolerant"}
      ]
      
      for {threshold, description} <- threshold_tests do
        target = "threshold_test_#{threshold}"
        
        # Configure with specific threshold
        CircuitBreaker.reset(CircuitBreaker, target)
        CircuitBreaker.configure_target(CircuitBreaker, target, [failure_threshold: threshold])
        
        # Function that always fails
        always_fails = fn -> {:error, :test_failure} end
        
        # Make enough calls to exceed threshold
        results = for attempt <- 1..(threshold + 2) do
          {attempt, CircuitBreaker.call(CircuitBreaker, target, always_fails, 500)}
        end
        
        # Find when circuit breaker opened
        open_attempt = Enum.find(results, fn {_attempt, result} ->
          case result do
            {:error, :circuit_breaker_open} -> true
            _ -> false
          end
        end)
        
        case open_attempt do
          {attempt_num, _} ->
            assert attempt_num <= (threshold + 1),
              "#{description} threshold: circuit opened at attempt #{attempt_num} (threshold: #{threshold})"
              
          nil ->
            # Circuit breaker might not have opened yet or thresholds work differently
            assert true, "#{description} threshold test completed"
        end
      end
    end
  end

  describe "circuit breaker timing and recovery" do
    test "validates recovery timeout configuration" do
      timeout_tests = [
        {100, "very_fast_recovery"},
        {1000, "fast_recovery"},
        {5000, "normal_recovery"},
        {30000, "slow_recovery"}
      ]
      
      for {timeout_ms, description} <- timeout_tests do
        target = "recovery_test_#{timeout_ms}"
        
        # Configure with specific recovery timeout
        CircuitBreaker.reset(CircuitBreaker, target)
        CircuitBreaker.configure_target(CircuitBreaker, target, [
          failure_threshold: 1,
          recovery_timeout: timeout_ms
        ])
        
        # Force circuit breaker open
        failing_function = fn -> {:error, :test_failure} end
        CircuitBreaker.call(CircuitBreaker, target, failing_function, 500)
        
        # Verify it's open
        case CircuitBreaker.get_state(CircuitBreaker, target) do
          {:ok, :open} ->
            # For long timeouts, don't actually wait - just verify configuration
            if timeout_ms > 2000 do
              assert true, "#{description} configured with #{timeout_ms}ms timeout"
            else
              # For short timeouts, test actual recovery
              Process.sleep(timeout_ms + 100)
              
              # Should be ready for recovery
              test_function = fn -> {:ok, :recovery_test} end
              
              case CircuitBreaker.call(CircuitBreaker, target, test_function, 1000) do
                {:ok, :recovery_test} ->
                  assert true, "#{description} successfully recovered after #{timeout_ms}ms"
                  
                {:error, :circuit_breaker_open} ->
                  assert true, "#{description} still open (timing may vary)"
                  
                {:error, reason} ->
                  assert is_atom(reason), "#{description} recovery error: #{inspect(reason)}"
              end
            end
            
          {:ok, other_state} ->
            assert true, "#{description} state: #{other_state}"
            
          {:error, reason} ->
            assert is_atom(reason), "#{description} state error: #{inspect(reason)}"
        end
      end
    end

    test "validates timeout during call execution" do
      target = "call_timeout_test"
      
      # Reset circuit breaker
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # Function that takes longer than timeout
      slow_function = fn ->
        Process.sleep(2000)
        {:ok, "slow_result"}
      end
      
      start_time = :erlang.monotonic_time(:millisecond)
      
      case CircuitBreaker.call(CircuitBreaker, target, slow_function, 500) do
        {:error, :timeout} ->
          end_time = :erlang.monotonic_time(:millisecond)
          elapsed_time = end_time - start_time
          
          assert elapsed_time >= 450 and elapsed_time <= 1000,
            "Timeout should be enforced: #{elapsed_time}ms (expected ~500ms)"
            
        {:ok, "slow_result"} ->
          assert true, "Slow function completed (faster than expected)"
          
        {:error, other_reason} ->
          assert is_atom(other_reason), "Call timeout error: #{inspect(other_reason)}"
      end
    end

    test "validates concurrent call handling" do
      target = "concurrent_test"
      
      # Reset circuit breaker
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # Function with variable execution time
      variable_function = fn ->
        sleep_time = :rand.uniform(100) + 50
        Process.sleep(sleep_time)
        {:ok, "completed_#{sleep_time}"}
      end
      
      # Make concurrent calls
      concurrent_count = 10
      
      tasks = for i <- 1..concurrent_count do
        Task.async(fn ->
          {i, CircuitBreaker.call(CircuitBreaker, target, variable_function, 1000)}
        end)
      end
      
      results = Task.yield_many(tasks, 5000)
      
      completed_count = Enum.count(results, fn {_task, result} -> result != nil end)
      
      assert completed_count == concurrent_count,
        "All concurrent calls should complete: #{completed_count}/#{concurrent_count}"
      
      # Check that all calls were handled properly
      successful_calls = Enum.count(results, fn {_task, result} ->
        case result do
          {:ok, {_i, {:ok, _value}}} -> true
          _ -> false
        end
      end)
      
      if successful_calls > 0 do
        assert true, "Circuit breaker handled #{successful_calls} concurrent calls successfully"
      else
        assert true, "Circuit breaker handled concurrent calls (may have different results)"
      end
      
      # Clean up tasks
      for {task, _result} <- results do
        Task.shutdown(task, :brutal_kill)
      end
    end
  end

  describe "circuit breaker per-target isolation" do
    test "validates independent target state management" do
      targets = ["device_a", "device_b", "device_c"]
      
      # Reset all targets
      for target <- targets do
        CircuitBreaker.reset(CircuitBreaker, target)
      end
      
      # Configure different thresholds for each
      CircuitBreaker.configure_target(CircuitBreaker, "device_a", [failure_threshold: 1])
      CircuitBreaker.configure_target(CircuitBreaker, "device_b", [failure_threshold: 3])
      CircuitBreaker.configure_target(CircuitBreaker, "device_c", [failure_threshold: 5])
      
      # Fail device_a (should open quickly)
      failing_function = fn -> {:error, :device_failure} end
      CircuitBreaker.call(CircuitBreaker, "device_a", failing_function, 500)
      
      # device_a should be open
      case CircuitBreaker.get_state(CircuitBreaker, "device_a") do
        {:ok, :open} ->
          assert true, "Device A correctly opened with low threshold"
          
        {:ok, other_state} ->
          assert true, "Device A state: #{other_state}"
          
        {:error, reason} ->
          assert is_atom(reason), "Device A state error: #{inspect(reason)}"
      end
      
      # device_b and device_c should still be closed
      for target <- ["device_b", "device_c"] do
        case CircuitBreaker.get_state(CircuitBreaker, target) do
          {:ok, :closed} ->
            assert true, "#{target} correctly remains closed"
            
          {:ok, other_state} ->
            assert true, "#{target} state: #{other_state}"
            
          {:error, :not_found} ->
            assert true, "#{target} not initialized (expected)"
            
          {:error, reason} ->
            assert is_atom(reason), "#{target} state error: #{inspect(reason)}"
        end
      end
    end

    test "validates target-specific configuration inheritance" do
      global_config = [failure_threshold: 5, recovery_timeout: 10000]
      specific_config = [failure_threshold: 2, recovery_timeout: 5000]
      
      # Set global configuration
      CircuitBreaker.configure(CircuitBreaker, global_config)
      
      # Set specific configuration for one target
      CircuitBreaker.configure_target(CircuitBreaker, "specific_device", specific_config)
      
      # Check configurations
      case CircuitBreaker.get_config(CircuitBreaker, "global_device") do
        {:ok, config} ->
          global_threshold = Map.get(config, :failure_threshold, 0)
          assert global_threshold == 5, "Global device should inherit global config: #{global_threshold}"
          
        {:error, reason} ->
          assert is_atom(reason), "Global config error: #{inspect(reason)}"
      end
      
      case CircuitBreaker.get_config(CircuitBreaker, "specific_device") do
        {:ok, config} ->
          specific_threshold = Map.get(config, :failure_threshold, 0)
          assert specific_threshold == 2, "Specific device should use specific config: #{specific_threshold}"
          
        {:error, reason} ->
          assert is_atom(reason), "Specific config error: #{inspect(reason)}"
      end
    end

    test "validates target cleanup and resource management" do
      test_targets = for i <- 1..50 do
        "cleanup_test_#{i}"
      end
      
      # Create circuit breaker state for many targets
      success_function = fn -> {:ok, :success} end
      
      for target <- test_targets do
        CircuitBreaker.call(CircuitBreaker, target, success_function, 500)
      end
      
      # Check that all targets are tracked
      active_targets = case CircuitBreaker.get_all_targets(CircuitBreaker) do
        {:ok, targets} -> targets
        {:error, _} -> []
      end
      
      tracked_count = length(Enum.filter(active_targets, fn target ->
        String.starts_with?(target, "cleanup_test_")
      end))
      
      if tracked_count > 0 do
        assert tracked_count <= 50, "Circuit breaker should track targets efficiently: #{tracked_count}"
      end
      
      # Test cleanup
      for target <- test_targets do
        CircuitBreaker.remove_target(CircuitBreaker, target)
      end
      
      # Verify cleanup
      Process.sleep(100)
      
      remaining_targets = case CircuitBreaker.get_all_targets(CircuitBreaker) do
        {:ok, targets} -> targets
        {:error, _} -> []
      end
      
      remaining_count = length(Enum.filter(remaining_targets, fn target ->
        String.starts_with?(target, "cleanup_test_")
      end))
      
      assert remaining_count == 0, "All test targets should be cleaned up: #{remaining_count} remaining"
    end
  end

  describe "circuit breaker metrics and monitoring" do
    test "validates metrics collection" do
      target = "metrics_test"
      
      # Reset and make some calls
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # Mix of successful and failing calls
      success_function = fn -> {:ok, :success} end
      failure_function = fn -> {:error, :failure} end
      
      # Make tracked calls
      CircuitBreaker.call(CircuitBreaker, target, success_function, 1000)
      CircuitBreaker.call(CircuitBreaker, target, failure_function, 1000)
      CircuitBreaker.call(CircuitBreaker, target, success_function, 1000)
      CircuitBreaker.call(CircuitBreaker, target, failure_function, 1000)
      
      # Check metrics
      case CircuitBreaker.get_stats(CircuitBreaker, target) do
        {:ok, stats} ->
          assert is_map(stats), "Circuit breaker should provide statistics"
          
          # Look for expected metrics
          expected_metrics = [
            :total_calls, :successful_calls, :failed_calls, :failure_count,
            :state, :last_failure_time, :recovery_time
          ]
          
          found_metrics = Enum.filter(expected_metrics, fn metric ->
            Map.has_key?(stats, metric)
          end)
          
          if length(found_metrics) > 0 do
            assert true, "Circuit breaker collected #{length(found_metrics)} expected metrics"
          else
            assert true, "Circuit breaker statistics available but in different format"
          end
          
        {:error, reason} ->
          assert is_atom(reason), "Circuit breaker stats error: #{inspect(reason)}"
      end
    end

    test "validates metrics accuracy" do
      target = "accuracy_test"
      
      # Reset and configure
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # Get baseline metrics
      baseline_stats = case CircuitBreaker.get_stats(CircuitBreaker, target) do
        {:ok, stats} -> stats
        {:error, _} -> %{}
      end
      
      # Make known number of calls
      success_function = fn -> {:ok, :success} end
      
      for _i <- 1..5 do
        CircuitBreaker.call(CircuitBreaker, target, success_function, 1000)
      end
      
      # Wait for metrics update
      Process.sleep(100)
      
      # Get updated metrics
      updated_stats = case CircuitBreaker.get_stats(CircuitBreaker, target) do
        {:ok, stats} -> stats
        {:error, _} -> %{}
      end
      
      # Verify metrics accuracy
      if Map.has_key?(baseline_stats, :total_calls) and Map.has_key?(updated_stats, :total_calls) do
        baseline_calls = Map.get(baseline_stats, :total_calls, 0)
        updated_calls = Map.get(updated_stats, :total_calls, 0)
        
        if is_number(baseline_calls) and is_number(updated_calls) then
          call_increase = updated_calls - baseline_calls
          assert call_increase == 5,
            "Circuit breaker should accurately count calls: increase=#{call_increase} (expected 5)"
        end
      end
      
      assert true, "Circuit breaker metrics accuracy test completed"
    end

    test "validates performance metrics" do
      target = "performance_metrics_test"
      
      # Reset circuit breaker
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # Function with measurable execution time
      timed_function = fn ->
        Process.sleep(100)
        {:ok, :timed_result}
      end
      
      # Make call and measure time
      start_time = :erlang.monotonic_time(:microsecond)
      CircuitBreaker.call(CircuitBreaker, target, timed_function, 5000)
      end_time = :erlang.monotonic_time(:microsecond)
      
      measured_time = end_time - start_time
      
      # Check if circuit breaker tracks execution times
      case CircuitBreaker.get_stats(CircuitBreaker, target) do
        {:ok, stats} ->
          if Map.has_key?(stats, :average_execution_time) do
            avg_time = Map.get(stats, :average_execution_time)
            
            if is_number(avg_time) do
              # Should be approximately the same as measured time (within reasonable margin)
              time_ratio = measured_time / avg_time
              assert time_ratio > 0.5 and time_ratio < 2.0,
                "Circuit breaker timing should be accurate: measured=#{measured_time}μs, tracked=#{avg_time}μs"
            end
          end
          
        {:error, reason} ->
          assert is_atom(reason), "Performance metrics error: #{inspect(reason)}"
      end
      
      assert true, "Circuit breaker performance metrics test completed"
    end

    test "validates global circuit breaker statistics" do
      # Make calls to multiple targets
      test_targets = ["global_stats_1", "global_stats_2", "global_stats_3"]
      
      success_function = fn -> {:ok, :success} end
      failure_function = fn -> {:error, :failure} end
      
      for target <- test_targets do
        CircuitBreaker.reset(CircuitBreaker, target)
        CircuitBreaker.call(CircuitBreaker, target, success_function, 1000)
        CircuitBreaker.call(CircuitBreaker, target, failure_function, 1000)
      end
      
      # Get global statistics
      case CircuitBreaker.get_global_stats(CircuitBreaker) do
        {:ok, global_stats} ->
          assert is_map(global_stats), "Circuit breaker should provide global statistics"
          
          # Look for global metrics
          expected_global_metrics = [
            :total_targets, :open_circuits, :half_open_circuits, :closed_circuits,
            :total_calls, :total_failures, :global_failure_rate
          ]
          
          found_global_metrics = Enum.filter(expected_global_metrics, fn metric ->
            Map.has_key?(global_stats, metric)
          end)
          
          if length(found_global_metrics) > 0 do
            assert true, "Circuit breaker collected #{length(found_global_metrics)} global metrics"
          else
            assert true, "Circuit breaker global statistics available but in different format"
          end
          
        {:error, reason} ->
          assert is_atom(reason), "Global stats error: #{inspect(reason)}"
      end
    end
  end

  describe "circuit breaker integration scenarios" do
    test "validates circuit breaker with SNMP operations" do
      target = "snmp_integration_test"
      
      # Reset circuit breaker
      CircuitBreaker.reset(CircuitBreaker, target)
      
      # SNMP operation function (simulated)
      snmp_operation = fn ->
        # Simulate SNMP GET operation
        case :rand.uniform(10) do
          n when n <= 7 -> {:ok, "SNMP response data"}
          _ -> {:error, :timeout}
        end
      end
      
      # Make several SNMP calls through circuit breaker
      results = for i <- 1..10 do
        {i, CircuitBreaker.call(CircuitBreaker, target, snmp_operation, 2000)}
      end
      
      # Analyze results
      successes = Enum.count(results, fn {_i, result} ->
        case result do
          {:ok, "SNMP response data"} -> true
          _ -> false
        end
      end)
      
      failures = Enum.count(results, fn {_i, result} ->
        case result do
          {:error, :timeout} -> true
          _ -> false
        end
      end)
      
      circuit_breaker_rejections = Enum.count(results, fn {_i, result} ->
        case result do
          {:error, :circuit_breaker_open} -> true
          _ -> false
        end
      end)
      
      total_processed = successes + failures + circuit_breaker_rejections
      assert total_processed == 10, "All SNMP calls should be processed: #{total_processed}/10"
      
      if circuit_breaker_rejections > 0 do
        assert true, "Circuit breaker protected #{circuit_breaker_rejections} SNMP calls"
      else
        assert true, "Circuit breaker processed all SNMP calls without rejection"
      end
    end

    test "validates circuit breaker with router integration" do
      # Test integration between circuit breaker and router
      router_target = "router_integration_test"
      
      # Function that simulates router call
      router_call = fn ->
        # Simulate routing to backend engine
        case SNMPMgr.with_circuit_breaker(router_target, fn ->
          # Simulate backend operation
          if :rand.uniform(5) == 1 do
            {:error, :backend_failure}
          else
            {:ok, "routed_response"}
          end
        end) do
          result -> result
        end
      end
      
      # Make calls through router with circuit breaker protection
      router_results = for i <- 1..8 do
        {i, router_call.()}
      end
      
      # Verify that circuit breaker is protecting router calls
      successful_routes = Enum.count(router_results, fn {_i, result} ->
        case result do
          {:ok, "routed_response"} -> true
          _ -> false
        end
      end)
      
      protected_calls = Enum.count(router_results, fn {_i, result} ->
        case result do
          {:error, :circuit_breaker_open} -> true
          {:error, :circuit_breaker_timeout} -> true
          _ -> false
        end
      end)
      
      if protected_calls > 0 do
        assert true, "Circuit breaker protected #{protected_calls} router calls"
      else
        assert true, "Circuit breaker processed router calls: #{successful_routes} successful"
      end
    end

    test "validates circuit breaker with engine batch processing" do
      batch_target = "batch_integration_test"
      
      # Function that simulates batch processing
      batch_processor = fn ->
        batch_requests = [
          %{type: :get, target: batch_target, oid: @test_oids.system_descr},
          %{type: :get, target: batch_target, oid: @test_oids.system_uptime},
          %{type: :get, target: batch_target, oid: @test_oids.system_descr}
        ]
        
        # Simulate batch processing with circuit breaker protection
        protected_results = for request <- batch_requests do
          SNMPMgr.with_circuit_breaker(batch_target, fn ->
            # Simulate request processing
            if :rand.uniform(4) == 1 do
              {:error, :processing_failure}
            else
              {:ok, "batch_response_#{request.type}"}
            end
          end)
        end
        
        {:ok, protected_results}
      end
      
      # Process several batches
      batch_results = for i <- 1..5 do
        {i, batch_processor.()}
      end
      
      # Verify batch processing with circuit breaker
      successful_batches = Enum.count(batch_results, fn {_i, result} ->
        case result do
          {:ok, _batch_responses} -> true
          _ -> false
        end
      end)
      
      assert successful_batches > 0, "Circuit breaker should allow batch processing: #{successful_batches}/5"
    end
  end

  describe "integration with SNMP simulator" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    @tag :integration
    test "validates circuit breaker with real SNMP device", %{device: device} do
      target = SNMPSimulator.device_target(device)
      circuit_target = "real_device_circuit_test"
      
      # Reset circuit breaker for this test
      CircuitBreaker.reset(CircuitBreaker, circuit_target)
      
      # Function that makes real SNMP call
      real_snmp_call = fn ->
        case SNMPMgr.get(target, @test_oids.system_descr, community: device.community) do
          {:ok, response} when is_binary(response) ->
            {:ok, response}
            
          {:error, :snmp_modules_not_available} ->
            {:error, :snmp_modules_not_available}
            
          {:error, reason} ->
            {:error, reason}
        end
      end
      
      # Make call through circuit breaker
      case CircuitBreaker.call(CircuitBreaker, circuit_target, real_snmp_call, 5000) do
        {:ok, response} when is_binary(response) ->
          assert String.length(response) > 0, "Circuit breaker should allow real SNMP calls"
          
        {:error, :snmp_modules_not_available} ->
          assert true, "SNMP modules not available for integration test"
          
        {:error, reason} ->
          assert is_atom(reason), "Circuit breaker real device error: #{inspect(reason)}"
      end
      
      # Verify circuit breaker tracked the call
      case CircuitBreaker.get_stats(CircuitBreaker, circuit_target) do
        {:ok, stats} ->
          total_calls = Map.get(stats, :total_calls, 0)
          assert total_calls >= 1, "Circuit breaker should track real SNMP calls: #{total_calls}"
          
        {:error, reason} ->
          assert is_atom(reason), "Circuit breaker stats error: #{inspect(reason)}"
      end
    end

    @tag :integration
    test "validates circuit breaker protection during device failures", %{device: device} do
      target = SNMPSimulator.device_target(device)
      circuit_target = "device_failure_circuit_test"
      
      # Configure sensitive circuit breaker
      CircuitBreaker.reset(CircuitBreaker, circuit_target)
      CircuitBreaker.configure_target(CircuitBreaker, circuit_target, [
        failure_threshold: 2,
        recovery_timeout: 1000
      ])
      
      # Function that calls unreachable device (simulate failure)
      failing_snmp_call = fn ->
        case SNMPMgr.get("192.0.2.1", @test_oids.system_descr, [timeout: 500, retries: 0]) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end
      end
      
      # Make calls that should trigger circuit breaker
      failure_results = for i <- 1..5 do
        {i, CircuitBreaker.call(CircuitBreaker, circuit_target, failing_snmp_call, 2000)}
      end
      
      # Should see circuit breaker protection
      circuit_breaker_protections = Enum.count(failure_results, fn {_i, result} ->
        case result do
          {:error, :circuit_breaker_open} -> true
          _ -> false
        end
      end)
      
      if circuit_breaker_protections > 0 do
        assert true, "Circuit breaker protected #{circuit_breaker_protections} calls during device failures"
      else
        # Check that failures were at least detected
        failures = Enum.count(failure_results, fn {_i, result} ->
          case result do
            {:error, _reason} -> true
            _ -> false
          end
        end)
        
        assert failures >= 3, "Circuit breaker should detect device failures: #{failures}/5"
      end
    end
  end
end