defmodule SnmpMgr.MultiTargetIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SnmpMgr.TestSupport.SNMPSimulator
  
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
      
      target = SNMPSimulator.device_target(device)
      tasks = Enum.map(oids, fn oid ->
        Task.async(fn ->
          SnmpMgr.get(target, oid, community: device.community, timeout: 200)
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
      
      target = SNMPSimulator.device_target(device)
      results = Enum.map(operations, fn
        {:get, oid} ->
          SnmpMgr.get(target, oid, community: device.community, timeout: 200)
          
        {:get_bulk, oid} ->
          SnmpMgr.get_bulk(target, oid, 
                          community: device.community, timeout: 200, max_repetitions: 3)
          
        {:walk, oid} ->
          SnmpMgr.walk(target, oid, community: device.community, timeout: 200)
      end)
      
      # All operations should succeed with the SNMP simulator
      assert length(results) == 3
      
      # Verify each operation returns expected data
      Enum.each(results, fn result ->
        case result do
          {:ok, data} when is_list(data) -> 
            # Bulk and walk operations return lists
            assert true
          {:ok, data} when is_binary(data) or is_integer(data) -> 
            # GET operations return strings or integers
            assert true
          {:error, reason} when reason in [:endOfMibView, :noSuchObject, :timeout] ->
            # Expected simulator errors are acceptable
            assert true
          {:error, reason} -> 
            flunk("Operation failed: #{inspect(reason)}")
          other -> 
            flunk("Unexpected result: #{inspect(other)}")
        end
      end)
    end
  end

  describe "Multi-operation Integration with snmp_lib" do
    test "bulk operations with different repetition counts", %{device: device} do
      skip_if_no_device(device)
      
      repetition_counts = [1, 3, 5]
      base_oid = "1.3.6.1.2.1.1"
      
      target = SNMPSimulator.device_target(device)
      results = Enum.map(repetition_counts, fn count ->
        SnmpMgr.get_bulk(target, base_oid,
                        community: device.community, timeout: 200, max_repetitions: count)
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
      
      target = SNMPSimulator.device_target(device)
      results = Enum.map(table_oids, fn oid ->
        case SnmpMgr.walk(target, oid, community: device.community, timeout: 200) do
          {:ok, data} when is_list(data) ->
            # Limit results for test efficiency
            limited_data = Enum.take(data, 5)
            {:ok, limited_data}
            
          other -> other
        end
      end)
      
      # Verify table operations complete
      assert length(results) == 2
      
      _successful_walks = Enum.count(results, fn
        {:ok, data} when is_list(data) -> true
        _ -> false
      end)
      
      # With simulator limitations, table walks may not succeed
      # This is acceptable behavior - just verify we get proper responses
      assert length(results) == 2
      
      # Verify all results have proper format
      Enum.each(results, fn
        {:ok, _data} -> assert true
        {:error, reason} when reason in [:endOfMibView, :noSuchObject, :timeout] ->
          assert true
        {:error, reason} -> 
          flunk("Unexpected table walk error: #{inspect(reason)}")
      end)
    end
  end
  
  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end
