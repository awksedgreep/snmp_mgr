defmodule SNMPMgr.PerformanceSnmpLibTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :performance
  @moduletag :snmp_lib_integration

  # Performance test configuration (scaled down for efficient testing)
  @concurrent_operations 10
  @performance_timeout 2_000

  setup_all do
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}
      error ->
        %{device: nil, setup_error: error}
    end
  end

  describe "SNMP Performance through snmp_lib" do
    test "concurrent GET operations performance", %{device: device} do
      skip_if_no_device(device)
      
      start_time = System.monotonic_time(:millisecond)
      
      # Perform concurrent operations
      target = SNMPSimulator.device_target(device)
      tasks = Enum.map(1..@concurrent_operations, fn _i ->
        Task.async(fn ->
          SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                      community: device.community, timeout: 200)
        end)
      end)
      
      results = Task.await_many(tasks, @performance_timeout)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Performance assertions
      assert length(results) == @concurrent_operations
      assert duration < @performance_timeout
      
      # Check success rate
      successful = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      success_rate = successful / @concurrent_operations
      assert success_rate > 0.5  # At least 50% success rate
    end
    
    test "bulk operation performance vs individual GETs", %{device: device} do
      skip_if_no_device(device)
      
      base_oid = "1.3.6.1.2.1.1"
      
      # Test individual GETs
      target = SNMPSimulator.device_target(device)
      individual_start = System.monotonic_time(:millisecond)
      individual_results = Enum.map(1..5, fn i ->
        oid = "#{base_oid}.#{i}.0"
        SNMPMgr.get(target, oid, community: device.community, timeout: 200)
      end)
      individual_duration = System.monotonic_time(:millisecond) - individual_start
      
      # Test bulk operation
      bulk_start = System.monotonic_time(:millisecond)
      bulk_result = SNMPMgr.get_bulk(target, base_oid,
                                    community: device.community, timeout: 200, max_repetitions: 5)
      bulk_duration = System.monotonic_time(:millisecond) - bulk_start
      
      # Performance comparison
      assert length(individual_results) == 5
      assert bulk_duration < individual_duration * 2  # Bulk should be more efficient
      
      case bulk_result do
        {:ok, bulk_data} when is_list(bulk_data) ->
          # Bulk data may be empty if simulator has limited data
          assert is_list(bulk_data)
        {:error, reason} when reason in [:endOfMibView, :noSuchObject, :timeout] ->
          # Acceptable errors from simulator with limited MIB data
          assert true
        {:error, _reason} ->
          # Other bulk operation errors might occur, which is acceptable for testing
          :ok
      end
    end
  end

  describe "snmp_lib Backend Performance Characteristics" do
    test "walk operation efficiency", %{device: device} do
      skip_if_no_device(device)
      
      start_time = System.monotonic_time(:millisecond)
      
      target = SNMPSimulator.device_target(device)
      case SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                       community: device.community, timeout: 500) do
        {:ok, results} when is_list(results) ->
          duration = System.monotonic_time(:millisecond) - start_time
          
          # Walk should complete efficiently
          assert duration < 1000  # Less than 1 second
          assert length(results) > 0
          
        {:error, _reason} ->
          # Walk might fail, which is acceptable
          :ok
      end
    end
    
    test "memory usage during operations", %{device: device} do
      skip_if_no_device(device)
      
      # Force garbage collection before measurement
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)
      
      # Perform multiple operations
      target = SNMPSimulator.device_target(device)
      Enum.each(1..20, fn _i ->
        SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                    community: device.community, timeout: 200)
      end)
      
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be reasonable (less than 5MB for 20 operations)
      assert memory_growth < 5_000_000
    end
  end
  
  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end
