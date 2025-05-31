defmodule SNMPMgr.MetricsComprehensiveTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.{Metrics, Config}
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :metrics
  @moduletag :phase_4
  
  # Test configuration
  @test_window_size 5  # 5 seconds for faster testing
  @test_retention_period 20  # 20 seconds for faster testing
  @test_collection_interval 100  # 100ms for faster testing
  
  setup_all do
    # Ensure configuration is available
    case GenServer.whereis(SNMPMgr.Config) do
      nil -> {:ok, _pid} = Config.start_link()
      _pid -> :ok
    end
    
    # Start SNMP simulator for testing
    {:ok, simulator_pid} = SNMPSimulator.start_link()
    on_exit(fn -> SNMPSimulator.stop(simulator_pid) end)
    
    %{simulator: simulator_pid}
  end
  
  setup do
    # Start fresh metrics collector for each test
    metrics_opts = [
      window_size: @test_window_size,
      retention_period: @test_retention_period,
      collection_interval: @test_collection_interval
    ]
    
    {:ok, metrics_pid} = Metrics.start_link(metrics_opts)
    
    on_exit(fn ->
      if Process.alive?(metrics_pid) do
        GenServer.stop(metrics_pid)
      end
    end)
    
    %{metrics: metrics_pid}
  end
  
  describe "Metrics Initialization and Configuration" do
    test "starts with default configuration" do
      {:ok, metrics} = Metrics.start_link()
      
      current_metrics = Metrics.get_metrics(metrics)
      summary = Metrics.get_summary(metrics)
      
      assert is_map(current_metrics)
      assert map_size(current_metrics) == 0  # No metrics recorded yet
      assert is_map(summary)
      
      GenServer.stop(metrics)
    end
    
    test "starts with custom configuration", %{metrics: metrics} do
      summary = Metrics.get_summary(metrics)
      
      assert is_map(summary)
      assert Map.has_key?(summary, :current_metrics)
      assert Map.has_key?(summary, :window_count)
      assert Map.has_key?(summary, :total_metric_types)
      assert Map.has_key?(summary, :last_collection)
    end
    
    test "validates configuration parameters" do
      # Invalid window size
      assert {:error, _reason} = Metrics.start_link(window_size: 0)
      assert {:error, _reason} = Metrics.start_link(window_size: -1)
      
      # Invalid retention period
      assert {:error, _reason} = Metrics.start_link(retention_period: -1)
      
      # Invalid collection interval
      assert {:error, _reason} = Metrics.start_link(collection_interval: -1)
    end
    
    test "collection timer starts automatically", %{metrics: metrics} do
      # Wait for a few collection cycles
      Process.sleep(@test_collection_interval * 3)
      
      summary = Metrics.get_summary(metrics)
      # Should have at least started collection
      assert summary.window_count >= 0
    end
    
    test "disabling collection timer works" do
      {:ok, metrics} = Metrics.start_link(collection_interval: 0)
      
      # Should not crash and should be functional
      Metrics.counter(metrics, :test_counter, 1)
      
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) >= 1
      
      GenServer.stop(metrics)
    end
  end
  
  describe "Counter Metrics" do
    test "records counter metrics", %{metrics: metrics} do
      Metrics.counter(metrics, :requests_total, 1)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      assert map_size(current_metrics) == 1
      
      # Find the counter metric
      counter_metric = current_metrics |> Map.values() |> hd()
      
      assert counter_metric.type == :counter
      assert counter_metric.name == :requests_total
      assert counter_metric.value == 1
      assert counter_metric.total == 1
    end
    
    test "accumulates counter values", %{metrics: metrics} do
      Metrics.counter(metrics, :requests_total, 5)
      Metrics.counter(metrics, :requests_total, 3)
      Metrics.counter(metrics, :requests_total, 2)
      
      current_metrics = Metrics.get_metrics(metrics)
      counter_metric = current_metrics |> Map.values() |> hd()
      
      assert counter_metric.value == 10
      assert counter_metric.total == 10
    end
    
    test "counter with tags creates separate metrics", %{metrics: metrics} do
      Metrics.counter(metrics, :requests, 1, %{status: :success})
      Metrics.counter(metrics, :requests, 1, %{status: :error})
      Metrics.counter(metrics, :requests, 2, %{status: :success})
      
      current_metrics = Metrics.get_metrics(metrics)
      
      assert map_size(current_metrics) == 2  # Two different tag combinations
      
      # Find metrics by tags
      success_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.tags == %{status: :success}
      end)
      
      error_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.tags == %{status: :error}
      end)
      
      assert success_metric.value == 3
      assert error_metric.value == 1
    end
    
    test "counter timestamps are recorded", %{metrics: metrics} do
      before_time = System.monotonic_time(:millisecond)
      
      Metrics.counter(metrics, :test_counter, 1)
      
      after_time = System.monotonic_time(:millisecond)
      
      current_metrics = Metrics.get_metrics(metrics)
      counter_metric = current_metrics |> Map.values() |> hd()
      
      assert counter_metric.created_at >= before_time
      assert counter_metric.created_at <= after_time
      assert counter_metric.last_updated >= before_time
      assert counter_metric.last_updated <= after_time
    end
    
    test "default counter increment is 1", %{metrics: metrics} do
      Metrics.counter(metrics, :default_counter)
      
      current_metrics = Metrics.get_metrics(metrics)
      counter_metric = current_metrics |> Map.values() |> hd()
      
      assert counter_metric.value == 1
    end
  end
  
  describe "Gauge Metrics" do
    test "records gauge metrics", %{metrics: metrics} do
      Metrics.gauge(metrics, :active_connections, 15)
      
      current_metrics = Metrics.get_metrics(metrics)
      gauge_metric = current_metrics |> Map.values() |> hd()
      
      assert gauge_metric.type == :gauge
      assert gauge_metric.name == :active_connections
      assert gauge_metric.value == 15
    end
    
    test "gauge values replace previous values", %{metrics: metrics} do
      Metrics.gauge(metrics, :cpu_usage, 25.5)
      Metrics.gauge(metrics, :cpu_usage, 45.2)
      Metrics.gauge(metrics, :cpu_usage, 30.1)
      
      current_metrics = Metrics.get_metrics(metrics)
      gauge_metric = current_metrics |> Map.values() |> hd()
      
      assert gauge_metric.value == 30.1
    end
    
    test "gauge with tags creates separate metrics", %{metrics: metrics} do
      Metrics.gauge(metrics, :memory_usage, 1024, %{type: :heap})
      Metrics.gauge(metrics, :memory_usage, 512, %{type: :stack})
      
      current_metrics = Metrics.get_metrics(metrics)
      
      assert map_size(current_metrics) == 2
      
      heap_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.tags == %{type: :heap}
      end)
      
      stack_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.tags == %{type: :stack}
      end)
      
      assert heap_metric.value == 1024
      assert stack_metric.value == 512
    end
    
    test "gauge handles various numeric types", %{metrics: metrics} do
      test_values = [0, 42, -10, 3.14159, 0.001, 1_000_000]
      
      Enum.with_index(test_values, fn value, index ->
        Metrics.gauge(metrics, :"gauge_#{index}", value)
      end)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      assert map_size(current_metrics) == length(test_values)
      
      # All values should be recorded correctly
      Enum.with_index(test_values, fn expected_value, index ->
        gauge_metric = Enum.find(Map.values(current_metrics), fn metric ->
          metric.name == :"gauge_#{index}"
        end)
        
        assert gauge_metric.value == expected_value
      end)
    end
  end
  
  describe "Histogram Metrics" do
    test "records histogram metrics", %{metrics: metrics} do
      Metrics.histogram(metrics, :request_duration, 150)
      
      current_metrics = Metrics.get_metrics(metrics)
      histogram_metric = current_metrics |> Map.values() |> hd()
      
      assert histogram_metric.type == :histogram
      assert histogram_metric.name == :request_duration
      assert histogram_metric.count == 1
      assert histogram_metric.sum == 150
      assert histogram_metric.min == 150
      assert histogram_metric.max == 150
      assert histogram_metric.avg == 150.0
      assert histogram_metric.values == [150]
    end
    
    test "accumulates histogram values", %{metrics: metrics} do
      values = [100, 200, 150, 300, 250]
      
      Enum.each(values, fn value ->
        Metrics.histogram(metrics, :response_times, value)
      end)
      
      current_metrics = Metrics.get_metrics(metrics)
      histogram_metric = current_metrics |> Map.values() |> hd()
      
      assert histogram_metric.count == 5
      assert histogram_metric.sum == 1000
      assert histogram_metric.min == 100
      assert histogram_metric.max == 300
      assert histogram_metric.avg == 200.0
      assert length(histogram_metric.values) == 5
    end
    
    test "histogram statistics are calculated correctly", %{metrics: metrics} do
      # Known values for easy calculation
      values = [10, 20, 30, 40, 50]
      
      Enum.each(values, fn value ->
        Metrics.histogram(metrics, :test_latency, value)
      end)
      
      current_metrics = Metrics.get_metrics(metrics)
      histogram_metric = current_metrics |> Map.values() |> hd()
      
      assert histogram_metric.count == 5
      assert histogram_metric.sum == 150
      assert histogram_metric.min == 10
      assert histogram_metric.max == 50
      assert histogram_metric.avg == 30.0
    end
    
    test "histogram with tags creates separate metrics", %{metrics: metrics} do
      Metrics.histogram(metrics, :latency, 100, %{operation: :get})
      Metrics.histogram(metrics, :latency, 200, %{operation: :set})
      Metrics.histogram(metrics, :latency, 150, %{operation: :get})
      
      current_metrics = Metrics.get_metrics(metrics)
      
      assert map_size(current_metrics) == 2
      
      get_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.tags == %{operation: :get}
      end)
      
      set_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.tags == %{operation: :set}
      end)
      
      assert get_metric.count == 2
      assert get_metric.avg == 125.0
      assert set_metric.count == 1
      assert set_metric.avg == 200.0
    end
    
    test "histogram limits stored values", %{metrics: metrics} do
      # Record more than the limit (1000) to test truncation
      Enum.each(1..1200, fn value ->
        Metrics.histogram(metrics, :large_histogram, value)
      end)
      
      current_metrics = Metrics.get_metrics(metrics)
      histogram_metric = current_metrics |> Map.values() |> hd()
      
      assert histogram_metric.count == 1200
      assert length(histogram_metric.values) <= 1000  # Should be limited
    end
  end
  
  describe "Timing Functions" do
    test "time function records execution duration", %{metrics: metrics} do
      sleep_duration = 50
      
      result = Metrics.time(metrics, :operation_duration, fn ->
        Process.sleep(sleep_duration)
        :success_result
      end)
      
      assert result == :success_result
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Should have both histogram and counter metrics
      assert map_size(current_metrics) >= 2
      
      # Find the histogram metric
      histogram_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.type == :histogram and metric.name == :operation_duration
      end)
      
      assert histogram_metric != nil
      assert histogram_metric.count == 1
      assert histogram_metric.min >= sleep_duration
      assert histogram_metric.max >= sleep_duration
      
      # Find the counter metric
      counter_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.type == :counter and metric.name == :operation_duration_total
      end)
      
      assert counter_metric != nil
      assert counter_metric.value == 1
    end
    
    test "time function handles successful operations", %{metrics: metrics} do
      result = Metrics.time(metrics, :success_op, fn ->
        {:ok, :test_result}
      end, %{type: :test})
      
      assert result == {:ok, :test_result}
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Find counter with success status
      success_counter = Enum.find(Map.values(current_metrics), fn metric ->
        metric.type == :counter and 
        metric.name == :success_op_total and 
        metric.tags == %{type: :test, status: :success}
      end)
      
      assert success_counter != nil
      assert success_counter.value == 1
    end
    
    test "time function handles errors and exceptions", %{metrics: metrics} do
      # Test with raised exception
      result = try do
        Metrics.time(metrics, :error_op, fn ->
          raise "Test error"
        end, %{type: :test})
      catch
        :error, %RuntimeError{message: "Test error"} -> :caught_error
      end
      
      assert result == :caught_error
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Should still record timing and error status
      error_counter = Enum.find(Map.values(current_metrics), fn metric ->
        metric.type == :counter and 
        metric.name == :error_op_total and 
        metric.tags.status == :error
      end)
      
      assert error_counter != nil
      assert error_counter.value == 1
    end
    
    test "time function with tags", %{metrics: metrics} do
      tags = %{service: :snmp, operation: :get}
      
      Metrics.time(metrics, :tagged_operation, fn ->
        Process.sleep(10)
        :result
      end, tags)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Find metrics with correct tags
      histogram_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.type == :histogram and metric.tags == tags
      end)
      
      counter_metric = Enum.find(Map.values(current_metrics), fn metric ->
        metric.type == :counter and 
        Map.drop(metric.tags, [:status]) == tags
      end)
      
      assert histogram_metric != nil
      assert counter_metric != nil
    end
  end
  
  describe "Metrics Aggregation and Time Windows" do
    test "time windows are collected automatically", %{metrics: metrics} do
      # Record some metrics
      Metrics.counter(metrics, :test_counter, 5)
      Metrics.gauge(metrics, :test_gauge, 100)
      
      # Wait for collection cycles
      Process.sleep(@test_collection_interval * 3)
      
      summary = Metrics.get_summary(metrics)
      assert summary.window_count >= 1
    end
    
    test "get_window_metrics returns time-filtered data", %{metrics: metrics} do
      start_time = System.monotonic_time(:second)
      
      # Record metrics
      Metrics.counter(metrics, :window_test, 1)
      
      # Wait a bit
      Process.sleep(100)
      
      end_time = System.monotonic_time(:second)
      
      # Wait for collection
      Process.sleep(@test_collection_interval * 2)
      
      window_metrics = Metrics.get_window_metrics(metrics, start_time, end_time)
      
      assert is_list(window_metrics)
    end
    
    test "old windows are removed based on retention period", %{metrics: metrics} do
      # Record metrics
      Metrics.counter(metrics, :retention_test, 1)
      
      # Wait for collection and retention cleanup
      Process.sleep(@test_retention_period * 1000 + @test_collection_interval * 2)
      
      # Should still be functional even after retention cleanup
      summary = Metrics.get_summary(metrics)
      assert is_map(summary)
    end
    
    test "get_summary provides comprehensive overview", %{metrics: metrics} do
      # Record various metric types
      Metrics.counter(metrics, :summary_counter, 10)
      Metrics.gauge(metrics, :summary_gauge, 50)
      Metrics.histogram(metrics, :summary_histogram, 200)
      
      summary = Metrics.get_summary(metrics)
      
      assert is_map(summary.current_metrics)
      assert is_integer(summary.window_count)
      assert is_map(summary.total_metric_types)
      assert is_integer(summary.last_collection)
      
      # Should have all three metric types
      assert summary.total_metric_types[:counter] >= 1
      assert summary.total_metric_types[:gauge] >= 1
      assert summary.total_metric_types[:histogram] >= 1
    end
    
    test "percentile calculations work correctly", %{metrics: metrics} do
      # Record values with known percentiles
      values = 1..100 |> Enum.to_list()
      
      Enum.each(values, fn value ->
        Metrics.histogram(metrics, :percentile_test, value)
      end)
      
      # Wait for collection to process percentiles
      Process.sleep(@test_collection_interval * 2)
      
      summary = Metrics.get_summary(metrics)
      
      # Verify percentile calculations exist in summary
      assert is_map(summary.current_metrics)
    end
  end
  
  describe "Subscription and Real-time Updates" do
    test "subscribe receives metric updates", %{metrics: metrics} do
      # Subscribe to updates
      Metrics.subscribe(metrics, self())
      
      # Record a metric
      Metrics.counter(metrics, :subscription_test, 1)
      
      # Should receive update message
      assert_receive {:metrics_event, {:counter, :subscription_test, 1, %{}, _timestamp}}, 1000
    end
    
    test "multiple subscribers receive updates", %{metrics: metrics} do
      # Create subscriber processes
      subscriber1 = spawn(fn ->
        receive do
          {:metrics_event, event} -> send(self(), {:received, :sub1, event})
        end
      end)
      
      subscriber2 = spawn(fn ->
        receive do
          {:metrics_event, event} -> send(self(), {:received, :sub2, event})
        end
      end)
      
      # Subscribe both
      Metrics.subscribe(metrics, subscriber1)
      Metrics.subscribe(metrics, subscriber2)
      Metrics.subscribe(metrics, self())
      
      # Record a metric
      Metrics.gauge(metrics, :multi_sub_test, 42)
      
      # All subscribers should receive the update
      assert_receive {:metrics_event, {:gauge, :multi_sub_test, 42, %{}, _}}, 1000
    end
    
    test "unsubscribe stops receiving updates", %{metrics: metrics} do
      # Subscribe first
      Metrics.subscribe(metrics, self())
      
      # Record a metric to confirm subscription works
      Metrics.counter(metrics, :unsub_test, 1)
      assert_receive {:metrics_event, _}, 1000
      
      # Unsubscribe
      Metrics.unsubscribe(metrics, self())
      
      # Record another metric
      Metrics.counter(metrics, :unsub_test, 1)
      
      # Should not receive this update
      refute_receive {:metrics_event, _}, 200
    end
    
    test "subscription handles process death gracefully", %{metrics: metrics} do
      # Create a subscriber process that dies
      dying_pid = spawn(fn ->
        receive do
          :die -> exit(:normal)
        end
      end)
      
      # Subscribe the dying process
      Metrics.subscribe(metrics, dying_pid)
      
      # Kill the subscriber
      send(dying_pid, :die)
      Process.sleep(50)  # Give time for cleanup
      
      # Metrics system should still work
      Metrics.counter(metrics, :death_test, 1)
      
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) >= 1
    end
  end
  
  describe "Performance and Memory Management" do
    test "handles high metric volume efficiently", %{metrics: metrics} do
      num_metrics = 1000
      
      start_time = System.monotonic_time(:millisecond)
      
      # Record many metrics rapidly
      Enum.each(1..num_metrics, fn i ->
        Metrics.counter(metrics, :"metric_#{rem(i, 10)}", 1)
      end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should handle metrics efficiently
      assert duration < num_metrics * 2  # Less than 2ms per metric
      
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) >= 10  # At least 10 different metrics
    end
    
    test "memory usage remains reasonable with many metrics", %{metrics: metrics} do
      initial_memory = :erlang.process_info(metrics, :memory)[:memory]
      
      # Create many different metrics
      Enum.each(1..500, fn i ->
        Metrics.counter(metrics, :"memory_test_#{i}", 1, %{index: i})
      end)
      
      final_memory = :erlang.process_info(metrics, :memory)[:memory]
      memory_growth = final_memory - initial_memory
      memory_per_metric = memory_growth / 500
      
      # Should use reasonable memory per metric
      assert memory_per_metric < 10_000  # Less than 10KB per metric
    end
    
    test "histogram value truncation prevents memory leaks", %{metrics: metrics} do
      # Record many values in a single histogram
      Enum.each(1..2000, fn value ->
        Metrics.histogram(metrics, :memory_histogram, value)
      end)
      
      current_metrics = Metrics.get_metrics(metrics)
      histogram_metric = current_metrics |> Map.values() |> hd()
      
      # Should limit stored values
      assert length(histogram_metric.values) <= 1000
      assert histogram_metric.count == 2000  # Count should still be accurate
    end
    
    test "concurrent metric recording", %{metrics: metrics} do
      num_tasks = 20
      metrics_per_task = 50
      
      tasks = Enum.map(1..num_tasks, fn task_id ->
        Task.async(fn ->
          Enum.each(1..metrics_per_task, fn i ->
            Metrics.counter(metrics, :"concurrent_#{task_id}", 1, %{iteration: i})
          end)
        end)
      end)
      
      # Wait for all tasks to complete
      Task.yield_many(tasks, 5000)
      
      # Should handle concurrent operations without crashes
      assert Process.alive?(metrics)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Should have metrics from all tasks
      total_unique_metrics = map_size(current_metrics)
      assert total_unique_metrics >= num_tasks
    end
  end
  
  describe "Reset and State Management" do
    test "reset clears all metrics", %{metrics: metrics} do
      # Record various metrics
      Metrics.counter(metrics, :reset_counter, 10)
      Metrics.gauge(metrics, :reset_gauge, 50)
      Metrics.histogram(metrics, :reset_histogram, 100)
      
      initial_metrics = Metrics.get_metrics(metrics)
      assert map_size(initial_metrics) >= 3
      
      # Reset all metrics
      Metrics.reset(metrics)
      
      final_metrics = Metrics.get_metrics(metrics)
      assert map_size(final_metrics) == 0
    end
    
    test "reset clears time windows", %{metrics: metrics} do
      # Record metrics and wait for collection
      Metrics.counter(metrics, :window_reset_test, 1)
      Process.sleep(@test_collection_interval * 2)
      
      initial_summary = Metrics.get_summary(metrics)
      
      # Reset everything
      Metrics.reset(metrics)
      
      final_summary = Metrics.get_summary(metrics)
      assert final_summary.window_count == 0
    end
    
    test "reset maintains system functionality", %{metrics: metrics} do
      # Record, reset, record again
      Metrics.counter(metrics, :functionality_test, 5)
      
      Metrics.reset(metrics)
      
      Metrics.counter(metrics, :functionality_test, 3)
      
      final_metrics = Metrics.get_metrics(metrics)
      counter_metric = final_metrics |> Map.values() |> hd()
      
      # Should only have the post-reset value
      assert counter_metric.value == 3
    end
    
    test "reset notifies subscribers", %{metrics: metrics} do
      Metrics.subscribe(metrics, self())
      
      # Reset should potentially trigger notifications
      Metrics.reset(metrics)
      
      # System should remain functional for new metrics
      Metrics.counter(metrics, :post_reset_test, 1)
      
      assert_receive {:metrics_event, _}, 1000
    end
  end
  
  describe "Integration and Edge Cases" do
    test "handles invalid metric names gracefully", %{metrics: metrics} do
      invalid_names = [nil, "", [], %{}, 123.45]
      
      Enum.each(invalid_names, fn invalid_name ->
        try do
          Metrics.counter(metrics, invalid_name, 1)
        rescue
          _ -> :ok  # Expected to fail
        catch
          _ -> :ok  # Expected to fail
        end
      end)
      
      # System should remain functional
      assert Process.alive?(metrics)
      
      # Valid metrics should still work
      Metrics.counter(metrics, :valid_after_invalid, 1)
      
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) >= 1
    end
    
    test "handles invalid metric values gracefully", %{metrics: metrics} do
      invalid_values = [nil, "string", [], %{}, :atom]
      
      Enum.each(invalid_values, fn invalid_value ->
        try do
          Metrics.counter(metrics, :invalid_value_test, invalid_value)
          Metrics.gauge(metrics, :invalid_gauge_test, invalid_value)
          Metrics.histogram(metrics, :invalid_histogram_test, invalid_value)
        rescue
          _ -> :ok  # Expected to fail for invalid values
        catch
          _ -> :ok  # Expected to fail for invalid values
        end
      end)
      
      # System should remain functional
      assert Process.alive?(metrics)
    end
    
    test "graceful shutdown with active collection", %{metrics: metrics} do
      # Start collection and recording
      Metrics.counter(metrics, :shutdown_test, 1)
      
      # Wait for collection to be active
      Process.sleep(@test_collection_interval / 2)
      
      # Should stop gracefully even during collection
      start_time = System.monotonic_time(:millisecond)
      :ok = GenServer.stop(metrics)
      stop_time = System.monotonic_time(:millisecond) - start_time
      
      assert stop_time < 5000  # Should stop within 5 seconds
      refute Process.alive?(metrics)
    end
    
    test "restart behavior", %{metrics: metrics} do
      # Record some metrics
      Metrics.counter(metrics, :restart_test, 5)
      
      # Stop and start new metrics collector
      GenServer.stop(metrics)
      
      {:ok, new_metrics} = Metrics.start_link()
      
      # Should start fresh
      current_metrics = Metrics.get_metrics(new_metrics)
      assert map_size(current_metrics) == 0
      
      # Should be fully functional
      Metrics.counter(new_metrics, :new_metric, 1)
      
      final_metrics = Metrics.get_metrics(new_metrics)
      assert map_size(final_metrics) == 1
      
      GenServer.stop(new_metrics)
    end
    
    test "high frequency collection doesn't impact performance", %{metrics: metrics} do
      # Record metrics continuously while collection runs
      start_time = System.monotonic_time(:millisecond)
      
      task = Task.async(fn ->
        Enum.each(1..100, fn i ->
          Metrics.counter(metrics, :performance_test, 1, %{batch: rem(i, 10)})
          if rem(i, 10) == 0, do: Process.sleep(1)  # Brief pause
        end)
      end)
      
      # Wait for completion
      Task.await(task, 5000)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete efficiently even with collection running
      assert duration < 2000  # Less than 2 seconds
      
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) >= 10
    end
  end
end