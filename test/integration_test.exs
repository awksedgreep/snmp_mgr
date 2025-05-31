defmodule SNMPMgr.IntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :integration
  
  setup_all do
    # Start the simulator application if needed
    case Application.ensure_all_started(:snmp_sim_ex) do
      {:ok, _} -> :ok
      {:error, _} -> 
        # SNMPSimEx might not be available in all environments
        ExUnit.configure(exclude: [:integration])
    end
    
    :ok
  end
  
  describe "Basic SNMP Operations with Simulator" do
    setup do
      {:ok, device_info} = SNMPSimulator.create_test_device()
      
      # Wait for device to be ready
      :ok = SNMPSimulator.wait_for_device_ready(device_info)
      
      on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
      
      %{device: device_info}
    end
    
    test "basic get operation", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test sysDescr.0
      {:ok, result} = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community)
      assert is_binary(result)
      assert String.contains?(result, "SNMP Simulator Device") or String.contains?(result, "Test Device")
    end
    
    test "get_next operation", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test get_next on system tree
      {:ok, {oid, value}} = SNMPMgr.get_next(target, "1.3.6.1.2.1.1", community: device.community)
      assert is_binary(oid)
      assert is_binary(value)
      assert String.starts_with?(oid, "1.3.6.1.2.1.1")
    end
    
    test "bulk operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test get_bulk
      {:ok, results} = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.1", 
                                        community: device.community, max_repetitions: 5)
      assert is_list(results)
      assert length(results) > 0
      
      # Each result should be {oid, value}
      Enum.each(results, fn {oid, value} ->
        assert is_binary(oid)
        assert String.starts_with?(oid, "1.3.6.1.2.1.1")
        assert is_binary(value)
      end)
    end
    
    test "walk operation", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test walking system tree
      {:ok, results} = SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                                    community: device.community, version: :v2c)
      assert is_list(results)
      assert length(results) >= 5  # Should have at least system objects
      
      # Verify all results are in system subtree
      Enum.each(results, fn {oid, _value} ->
        assert String.starts_with?(oid, "1.3.6.1.2.1.1")
      end)
    end
  end
  
  describe "Switch Device Simulation" do
    setup do
      {:ok, switch} = SNMPSimulator.create_switch_device(interface_count: 12)
      :ok = SNMPSimulator.wait_for_device_ready(switch)
      
      on_exit(fn -> SNMPSimulator.stop_device(switch) end)
      
      %{switch: switch}
    end
    
    test "interface table access", %{switch: switch} do
      target = SNMPSimulator.device_target(switch)
      
      # Test ifNumber
      {:ok, if_count} = SNMPMgr.get(target, "1.3.6.1.2.1.2.1.0", community: switch.community)
      assert if_count == "12"
      
      # Test getting interface descriptions
      {:ok, results} = SNMPMgr.walk(target, "1.3.6.1.2.1.2.2.1.2", 
                                    community: switch.community, version: :v2c)
      assert length(results) == 12
      
      # Verify interface names
      interface_names = Enum.map(results, fn {_oid, value} -> value end)
      assert "eth1" in interface_names
      assert "eth12" in interface_names
    end
    
    test "table processing", %{switch: switch} do
      target = SNMPSimulator.device_target(switch)
      
      # Get interface table data
      {:ok, table_data} = SNMPMgr.get_table(target, "1.3.6.1.2.1.2.2", 
                                            community: switch.community)
      
      # Analyze table structure
      {:ok, analysis} = SNMPMgr.analyze_table(table_data)
      assert analysis.row_count == 12
      assert analysis.completeness > 0.5  # Should have good data coverage
      
      # Test table filtering
      {:ok, active_interfaces} = SNMPMgr.Table.filter_by_column(table_data, 8, fn status ->
        status == "1"  # ifOperStatus == up
      end)
      
      # Should have some active interfaces (first 12 are up in our simulation)
      assert map_size(active_interfaces) > 0
    end
  end
  
  describe "Phase 5 Engine Integration" do
    setup do
      # Create a fleet of test devices
      {:ok, devices} = SNMPSimulator.create_device_fleet(count: 5, device_type: :test_device)
      
      # Wait for all devices to be ready
      Enum.each(devices, fn device ->
        :ok = SNMPSimulator.wait_for_device_ready(device)
      end)
      
      on_exit(fn -> SNMPSimulator.stop_devices(devices) end)
      
      %{devices: devices}
    end
    
    @tag :slow
    test "engine request processing", %{devices: devices} do
      # Start the streaming engine
      {:ok, _pid} = SNMPMgr.start_engine(
        engine: [pool_size: 5, batch_size: 10],
        router: [strategy: :round_robin],
        pool: [pool_size: 10]
      )
      
      # Test individual requests through engine
      device = hd(devices)
      target = SNMPSimulator.device_target(device)
      
      request = %{
        type: :get,
        target: target,
        oid: "1.3.6.1.2.1.1.1.0",
        community: device.community
      }
      
      {:ok, result} = SNMPMgr.engine_request(request)
      assert is_binary(result)
    end
    
    @tag :slow
    test "batch request processing", %{devices: devices} do
      # Start the streaming engine
      {:ok, _pid} = SNMPMgr.start_engine(
        engine: [pool_size: 5, batch_size: 20],
        router: [strategy: :least_connections]
      )
      
      # Create batch requests
      requests = 
        devices
        |> Enum.take(3)
        |> Enum.map(fn device ->
          %{
            type: :get,
            target: SNMPSimulator.device_target(device),
            oid: "1.3.6.1.2.1.1.1.0",
            community: device.community
          }
        end)
      
      {:ok, results} = SNMPMgr.engine_batch(requests)
      assert length(results) == 3
      
      # Verify all results are successful
      Enum.each(results, fn result ->
        case result do
          {:ok, _engine_name, batch_results} ->
            assert is_list(batch_results)
          {:error, _engine_name, reason} ->
            flunk("Batch request failed: #{inspect(reason)}")
        end
      end)
    end
  end
  
  describe "Streaming Operations" do
    setup do
      {:ok, switch} = SNMPSimulator.create_switch_device(interface_count: 24)
      :ok = SNMPSimulator.wait_for_device_ready(switch)
      
      on_exit(fn -> SNMPSimulator.stop_device(switch) end)
      
      %{switch: switch}
    end
    
    test "memory-efficient streaming", %{switch: switch} do
      target = SNMPSimulator.device_target(switch)
      
      # Test streaming walk
      results = 
        target
        |> SNMPMgr.walk_stream("1.3.6.1.2.1.2.2.1", 
                               community: switch.community, chunk_size: 5)
        |> Stream.take(10)
        |> Enum.to_list()
      
      assert length(results) == 10
      
      # Verify results are {oid, value} tuples
      Enum.each(results, fn {oid, value} ->
        assert is_binary(oid)
        assert is_binary(value)
        assert String.starts_with?(oid, "1.3.6.1.2.1.2.2.1")
      end)
    end
    
    test "adaptive walking", %{switch: switch} do
      target = SNMPSimulator.device_target(switch)
      
      # Test adaptive bulk walking
      {:ok, results} = SNMPMgr.adaptive_walk(target, "1.3.6.1.2.1.2.2.1", 
                                             community: switch.community, 
                                             adaptive_tuning: true)
      
      assert is_list(results)
      assert length(results) > 0
      
      # Should contain interface table data
      interface_data = Enum.filter(results, fn {oid, _} ->
        String.contains?(oid, "1.3.6.1.2.1.2.2.1.2")  # ifDescr
      end)
      
      assert length(interface_data) > 0
    end
  end
  
  describe "Circuit Breaker Protection" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end
    
    test "successful operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with circuit breaker protection
      {:ok, result} = SNMPMgr.with_circuit_breaker(target, fn ->
        SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community)
      end, timeout: 5000)
      
      assert {:ok, _value} = result
    end
    
    test "timeout protection", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with very short timeout to trigger circuit breaker
      result = SNMPMgr.with_circuit_breaker(target, fn ->
        # Simulate slow operation
        Process.sleep(100)
        SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community)
      end, timeout: 50)
      
      # Should handle timeout gracefully
      assert {:error, _reason} = result
    end
  end
  
  describe "Performance and Metrics" do
    setup do
      {:ok, devices} = SNMPSimulator.create_device_fleet(count: 3)
      
      Enum.each(devices, fn device ->
        :ok = SNMPSimulator.wait_for_device_ready(device)
      end)
      
      on_exit(fn -> SNMPSimulator.stop_devices(devices) end)
      
      %{devices: devices}
    end
    
    test "metrics collection", %{devices: devices} do
      # Record some custom metrics
      SNMPMgr.record_metric(:counter, :test_operations, 5, %{test: "integration"})
      SNMPMgr.record_metric(:gauge, :active_devices, length(devices), %{type: "test"})
      
      # Test timing operations
      device = hd(devices)
      target = SNMPSimulator.device_target(device)
      
      result = SNMPMgr.Metrics.time(SNMPMgr.Metrics, :test_snmp_get, fn ->
        SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community)
      end, %{device: "test", operation: "get"})
      
      assert {:ok, _value} = result
    end
    
    @tag :slow
    test "performance benchmarking", %{devices: devices} do
      device = hd(devices)
      target = SNMPSimulator.device_target(device)
      
      # Run a simple benchmark
      start_time = System.monotonic_time(:millisecond)
      
      # Perform multiple operations
      results = 
        1..10
        |> Enum.map(fn _ ->
          SNMPMgr.get(target, "1.3.6.1.2.1.1.3.0", community: device.community)
        end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Verify all operations succeeded
      successful_operations = Enum.count(results, fn 
        {:ok, _} -> true
        _ -> false
      end)
      
      assert successful_operations == 10
      assert duration < 5000  # Should complete within 5 seconds
      
      avg_latency = duration / 10
      assert avg_latency < 500  # Average less than 500ms per operation
    end
  end
  
  describe "Error Handling" do
    test "invalid device handling" do
      # Test against non-existent device
      result = SNMPMgr.get("127.0.0.1:99999", "1.3.6.1.2.1.1.1.0", 
                           community: "public", timeout: 1000)
      
      assert {:error, _reason} = result
    end
    
    test "invalid OID handling" do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      target = SNMPSimulator.device_target(device)
      
      # Test with invalid OID
      result = SNMPMgr.get(target, "1.3.6.1.2.1.99.99.99", 
                           community: device.community, timeout: 1000)
      
      # Should handle gracefully (might be noSuchName or timeout)
      assert {:error, _reason} = result
      
      SNMPSimulator.stop_device(device)
    end
    
    test "community string validation" do
      {:ok, device} = SNMPSimulator.create_test_device(community: "private")
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      target = SNMPSimulator.device_target(device)
      
      # Test with wrong community
      result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                           community: "wrong", timeout: 1000)
      
      assert {:error, _reason} = result
      
      # Test with correct community
      result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                           community: "private", timeout: 1000)
      
      assert {:ok, _value} = result
      
      SNMPSimulator.stop_device(device)
    end
  end
end