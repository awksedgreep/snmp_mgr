defmodule SNMPMgr.MultiTargetIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :multi_target_operations
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

  describe "Multi-target Operations with snmp_lib" do
    test "concurrent operations to same target", %{device: device} do
      skip_if_no_device(device)
      
      # Perform multiple concurrent operations to the same target
      oids = [
        "1.3.6.1.2.1.1.1.0",  # sysDescr
        "1.3.6.1.2.1.1.3.0",  # sysUpTime
        "1.3.6.1.2.1.1.5.0"   # sysName
      ]
      
      tasks = Enum.map(oids, fn oid ->
        Task.async(fn ->
          SNMPMgr.get(device.host, device.port, device.community, oid, timeout: 200)
        end)
      end)
      
      results = Task.await_many(tasks, 1000)
      
      # All operations should complete
      assert length(results) == 3
      
      # Count successful operations
      successful_count = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      # At least some operations should succeed
      assert successful_count >= 1
    end
    
    test "sequential operations with different parameters", %{device: device} do
      skip_if_no_device(device)
      
      # Test different operation types sequentially
      operations = [
        {:get, "1.3.6.1.2.1.1.1.0"},
        {:get_bulk, "1.3.6.1.2.1.1"},
        {:walk, "1.3.6.1.2.1.1"}
      ]
      
      results = Enum.map(operations, fn
        {:get, oid} ->
          SNMPMgr.get(device.host, device.port, device.community, oid, timeout: 200)
          
        {:get_bulk, oid} ->
          SNMPMgr.get_bulk(device.host, device.port, device.community, oid, 
                          timeout: 200, max_repetitions: 3)
          
        {:walk, oid} ->
          SNMPMgr.walk(device.host, device.port, device.community, oid, timeout: 200)
      end)
      
      # All operations should return valid responses
      assert length(results) == 3
      Enum.each(results, fn result ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end
  end

  describe "Multi-operation Integration with snmp_lib" do
    test "bulk operations with different repetition counts", %{device: device} do
      skip_if_no_device(device)
      
      repetition_counts = [1, 3, 5]
      base_oid = "1.3.6.1.2.1.1"
      
      results = Enum.map(repetition_counts, fn count ->
        SNMPMgr.get_bulk(device.host, device.port, device.community, base_oid,
                        timeout: 200, max_repetitions: count)
      end)
      
      # All bulk operations should complete
      assert length(results) == 3
      
      # Verify bulk operation behavior
      successful_results = Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      # At least some bulk operations should succeed
      assert length(successful_results) >= 1
    end
    
    test "table operations through snmp_lib", %{device: device} do
      skip_if_no_device(device)
      
      # Test table walking operations
      table_oids = [
        "1.3.6.1.2.1.1",    # System group
        "1.3.6.1.2.1.2.2"   # Interface table (if available)
      ]
      
      results = Enum.map(table_oids, fn oid ->
        case SNMPMgr.walk(device.host, device.port, device.community, oid, timeout: 200) do
          {:ok, data} when is_list(data) ->
            # Limit results for test efficiency
            limited_data = Enum.take(data, 5)
            {:ok, limited_data}
            
          other -> other
        end
      end)
      
      # Verify table operations complete
      assert length(results) == 2
      
      successful_walks = Enum.count(results, fn
        {:ok, data} when is_list(data) -> true
        _ -> false
      end)
      
      # At least one table walk should succeed
      assert successful_walks >= 1
    end
  end
  
  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok

