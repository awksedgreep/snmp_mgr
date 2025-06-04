defmodule SNMPMgr.MetricsIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.{Metrics, Config}
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :metrics
  @moduletag :snmp_lib_integration
  
  setup_all do
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}
      error ->
        %{device: nil, setup_error: error}
    end
  end
  
  setup do
    {:ok, metrics_pid} = Metrics.start_link()
    
    on_exit(fn ->
      if Process.alive?(metrics_pid) do
        GenServer.stop(metrics_pid)
      end
    end)
    
    %{metrics: metrics_pid}
  end
  
  describe "Metrics Integration with snmp_lib Operations" do
    test "records metrics during successful SNMP GET operations", %{device: device, metrics: metrics} do
      skip_if_no_device(device)
      
      # Perform SNMP GET with metrics collection
      result = SNMPMgr.get(device.host, device.port, device.community, "1.3.6.1.2.1.1.1.0", 
                          timeout: 200, metrics: metrics)
      
      assert {:ok, _value} = result
      
      # Verify metrics were recorded
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) > 0
      
      # Should have operation counter
      operation_counter = find_metric(current_metrics, :counter, :snmp_operations_total)
      assert operation_counter != nil
      assert operation_counter.value >= 1
    end
    
    test "records metrics during failed SNMP operations", %{device: device, metrics: metrics} do
      skip_if_no_device(device)
      
      # Perform SNMP GET to invalid OID with short timeout
      result = SNMPMgr.get(device.host, device.port, "invalid_community", "1.3.6.1.2.1.1.1.0", 
                          timeout: 100, metrics: metrics)
      
      assert {:error, _reason} = result
      
      # Verify error metrics were recorded
      current_metrics = Metrics.get_metrics(metrics)
      assert map_size(current_metrics) > 0
      
      # Should have error counter
      error_counter = find_metric(current_metrics, :counter, :snmp_errors_total)
      assert error_counter != nil
      assert error_counter.value >= 1
    end
  end
  
  describe "SNMP Operation Metrics Collection" do
    test "tracks response times for SNMP operations", %{device: device, metrics: metrics} do
      skip_if_no_device(device)
      
      # Perform multiple operations to collect timing data
      oids = ["1.3.6.1.2.1.1.1.0", "1.3.6.1.2.1.1.2.0", "1.3.6.1.2.1.1.3.0"]
      
      Enum.each(oids, fn oid ->
        SNMPMgr.get(device.host, device.port, device.community, oid, 
                    timeout: 200, metrics: metrics)
      end)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Should have timing histogram
      timing_metric = find_metric(current_metrics, :histogram, :snmp_response_time)
      assert timing_metric != nil
      assert timing_metric.count >= 3
      assert timing_metric.min > 0
      assert timing_metric.avg > 0
    end
    
    test "differentiates metrics by operation type", %{device: device, metrics: metrics} do
      skip_if_no_device(device)
      
      # Perform different SNMP operations
      SNMPMgr.get(device.host, device.port, device.community, "1.3.6.1.2.1.1.1.0", 
                  timeout: 200, metrics: metrics)
      
      result = SNMPMgr.get_bulk(device.host, device.port, device.community, "1.3.6.1.2.1.1", 
                               timeout: 200, max_repetitions: 3, metrics: metrics)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Should have separate metrics for GET and GET-BULK
      get_counter = find_metric_with_tags(current_metrics, :counter, %{operation: :get})
      bulk_counter = find_metric_with_tags(current_metrics, :counter, %{operation: :get_bulk})
      
      assert get_counter != nil
      if match?({:ok, _}, result) do
        assert bulk_counter != nil
      end
    end
  end
  
  describe "Bulk Operations Metrics" do
    test "tracks bulk operation performance", %{device: device, metrics: metrics} do
      skip_if_no_device(device)
      
      # Perform bulk operation with metrics collection
      result = SNMPMgr.get_bulk(device.host, device.port, device.community, "1.3.6.1.2.1.1", 
                               timeout: 200, max_repetitions: 5, metrics: metrics)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Should track bulk operation timing and count
      bulk_counter = find_metric_with_tags(current_metrics, :counter, %{operation: :get_bulk})
      timing_metric = find_metric(current_metrics, :histogram, :snmp_response_time)
      
      if match?({:ok, _}, result) do
        assert bulk_counter != nil
        assert bulk_counter.value >= 1
      end
      
      assert timing_metric != nil
      assert timing_metric.count >= 1
    end
  end

  describe "Multi-target Metrics" do
    test "aggregates metrics across multiple targets", %{device: device, metrics: metrics} do
      skip_if_no_device(device)
      
      targets = [
        {device.host, device.port, device.community},
        {device.host, device.port, device.community}
      ]
      
      # Perform operations on multiple targets
      Enum.each(targets, fn {host, port, community} ->
        SNMPMgr.get(host, port, community, "1.3.6.1.2.1.1.1.0", 
                    timeout: 200, metrics: metrics)
      end)
      
      current_metrics = Metrics.get_metrics(metrics)
      
      # Should aggregate operation counts
      operation_counter = find_metric(current_metrics, :counter, :snmp_operations_total)
      assert operation_counter != nil
      assert operation_counter.value >= 2
    end
  end
  
  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
  
  defp find_metric(metrics, type, name) do
    Enum.find(Map.values(metrics), fn metric ->
      metric.type == type and metric.name == name
    end)
  end
  
  defp find_metric_with_tags(metrics, type, expected_tags) do
    Enum.find(Map.values(metrics), fn metric ->
      metric.type == type and 
      Map.take(metric.tags || %{}, Map.keys(expected_tags)) == expected_tags
    end)
  end
end