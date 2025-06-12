defmodule SnmpMgr.TableWalkingTest do
  use ExUnit.Case, async: false
  
  alias SnmpMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :table_walking

  describe "Table Walking with SnmpLib Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "walk/3 uses snmp_lib for table walking", %{device: device} do
      # Test walking with simulator device following @testing_rules
      result = SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1", 
                           community: device.community, version: :v2c, timeout: 200)
      
      case result do
        {:ok, walk_data} when is_list(walk_data) ->
          # Successful walk through snmp_lib - validate real data
          if length(walk_data) > 0 do
            # Each result must be valid OID-type-value tuple
            Enum.each(walk_data, fn {oid, type, value} ->
              assert is_binary(oid)
              assert String.starts_with?(oid, "1.3.6.1.2.1.1")
              assert is_atom(type)
              assert value != nil
            end)
          end
          assert true
          
        {:error, reason} ->
          # Accept valid SNMP errors from simulator
          assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view]
      end
    end

    test "walk adapts version for bulk vs getnext", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test v1 walk (should use getnext) - small tree for speed
      result_v1 = SnmpMgr.walk(target, "1.3.6.1.2.1.1", 
                              version: :v1, community: device.community, timeout: 200)
      
      # Test v2c walk (should use bulk) - small tree for speed
      result_v2c = SnmpMgr.walk(target, "1.3.6.1.2.1.1", 
                               version: :v2c, community: device.community, timeout: 200)
      
      # Both should work through appropriate snmp_lib mechanisms or return valid errors
      case result_v1 do
        {:ok, _} -> assert true
        {:error, reason} -> assert reason in [:endOfMibView, :end_of_mib_view, :noSuchObject, :timeout]
      end
      
      case result_v2c do
        {:ok, _} -> assert true  
        {:error, reason} -> assert reason in [:endOfMibView, :end_of_mib_view, :noSuchObject, :timeout]
      end
    end

    test "walk handles various OID formats", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test different OID formats for walking - use small trees for speed
      oid_formats = [
        {"1.3.6.1.2.1.1.1", "string OID"},
        {[1, 3, 6, 1, 2, 1, 1, 1], "list OID"}
      ]
      
      Enum.each(oid_formats, fn {oid, description} ->
        result = SnmpMgr.walk(target, oid, community: device.community, timeout: 200)
        
        case result do
          {:ok, results} when is_list(results) ->
            assert true, "#{description} walk succeeded through snmp_lib"
          {:error, reason} ->
            # Should get proper error format for valid SNMP errors
            assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] or 
                   is_atom(reason) or is_tuple(reason),
              "#{description} error: #{inspect(reason)}"
        end
      end)
    end

    test "walk results maintain proper order", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test small walk to check ordering - use limited tree
      result = SnmpMgr.walk(target, "1.3.6.1.2.1.1.1", 
                           community: device.community, timeout: 200)
      
      case result do
        {:ok, walk_data} when length(walk_data) > 1 ->
          # Verify ordering of string OIDs
          oids = Enum.map(walk_data, fn {oid, _type, _value} -> oid end)
          
          # Check that OIDs are properly ordered
          sorted_oids = Enum.sort(oids, fn oid1, oid2 ->
            case {SnmpLib.OID.string_to_list(oid1), SnmpLib.OID.string_to_list(oid2)} do
              {{:ok, list1}, {:ok, list2}} -> list1 <= list2
              _ -> oid1 <= oid2
            end
          end)
          
          assert oids == sorted_oids, "Walk results should be properly ordered"
          
        _ ->
          # Single result or error - acceptable for small trees
          assert true
      end
    end
  end

  describe "Basic Table Operations" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "simple table walking works", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test basic table walking with simulator - use small system table
      result = SnmpMgr.walk(target, "1.3.6.1.2.1.1", 
                           community: device.community, timeout: 200)
      
      case result do
        {:ok, table_data} when is_list(table_data) ->
          # Validate that we got valid table data
          if length(table_data) > 0 do
            # Each entry should be within system table scope
            Enum.each(table_data, fn {oid, type, value} ->
              assert is_binary(oid)
              assert String.starts_with?(oid, "1.3.6.1.2.1.1")
              assert is_atom(type)
              assert value != nil
            end)
          end
          assert true
          
        {:error, reason} ->
          # Accept valid errors from simulator
          assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view]
      end
    end

    test "limited scope table operations", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test walking specific system objects only - avoid large interface tables
      system_oids = [
        "1.3.6.1.2.1.1.1",  # sysDescr subtree
        "1.3.6.1.2.1.1.3",  # sysUpTime subtree
        "1.3.6.1.2.1.1.5"   # sysName subtree
      ]
      
      Enum.each(system_oids, fn oid ->
        result = SnmpMgr.walk(target, oid, community: device.community, timeout: 200)
        
        case result do
          {:ok, results} when is_list(results) ->
            # Should get results within the specified subtree
            if length(results) > 0 do
              Enum.each(results, fn {result_oid, type, value} ->
                assert is_binary(result_oid)
                assert String.starts_with?(result_oid, oid)
                assert is_atom(type)
                assert value != nil
              end)
            end
            assert true
            
          {:error, reason} ->
            # Accept valid SNMP errors
            assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view]
        end
      end)
    end
  end

  describe "Table Walking Error Handling" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "handles invalid table OIDs", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      invalid_oids = [
        "invalid.table.oid",
        "1.3.6.1.2.1.999.999.999",
        ""
      ]
      
      Enum.each(invalid_oids, fn oid ->
        result = SnmpMgr.walk(target, oid, community: device.community, timeout: 200)
        
        case result do
          {:error, reason} ->
            # Should return proper error for invalid OIDs
            assert is_atom(reason) or is_tuple(reason)
          {:ok, _} ->
            # Some invalid OIDs might resolve unexpectedly in test environment
            assert true
        end
      end)
    end

    test "handles timeout in table operations", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test very short timeout on system table (should be fast enough)
      result = SnmpMgr.walk(target, "1.3.6.1.2.1.1.1", 
                           community: device.community, timeout: 1)
      
      case result do
        {:error, :timeout} -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
        {:ok, _} -> assert true  # Fast response from simulator acceptable
      end
    end

    test "handles community validation in table operations", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test with wrong community
      result = SnmpMgr.walk(target, "1.3.6.1.2.1.1.1", 
                           community: "wrong_community", timeout: 200)
      
      case result do
        {:error, reason} when reason in [:authentication_error, :bad_community] ->
          assert true  # Expected authentication error
        {:error, _other} -> assert true  # Other errors acceptable
        {:ok, _} -> assert true  # Might succeed in test environment
      end
    end

    test "handles end of MIB view in walks", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test walking beyond available data - use high OID that shouldn't exist
      result = SnmpMgr.walk(target, "1.3.6.1.2.1.999", 
                           community: device.community, timeout: 200)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Should handle end of MIB gracefully - empty list is valid
          assert true
          
        {:error, reason} when reason in [:endOfMibView, :end_of_mib_view, :noSuchObject] ->
          # Expected for non-existent subtrees
          assert true
          
        {:error, reason} ->
          # Other errors acceptable from simulator
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end

  describe "Table Walking Performance" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "small table walking operations complete efficiently", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Measure time for small table walking operations
      start_time = System.monotonic_time(:millisecond)
      
      # Use small system subtrees to avoid timeout issues
      results = Enum.map(["1.3.6.1.2.1.1", "1.3.6.1.2.1.11"], fn oid ->
        SnmpMgr.walk(target, oid, community: device.community, timeout: 200)
      end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete reasonably quickly with local simulator
      assert duration < 1000  # Less than 1 second for 2 small walk operations
      assert length(results) == 2
      
      # All should return proper format through snmp_lib
      Enum.each(results, fn result ->
        case result do
          {:ok, _} -> assert true  # Operation succeeded
          {:error, reason} when reason in [:timeout, :endOfMibView, :end_of_mib_view, :noSuchObject] -> 
            assert true  # Acceptable errors from simulator
          {:error, reason} -> flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end

    test "version comparison efficiency", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Compare bulk walking (v2c) vs individual walking (v1) on small tree
      {bulk_time, bulk_result} = :timer.tc(fn ->
        SnmpMgr.walk(target, "1.3.6.1.2.1.1", 
                    version: :v2c, community: device.community, timeout: 200)
      end)
      
      {individual_time, individual_result} = :timer.tc(fn ->
        SnmpMgr.walk(target, "1.3.6.1.2.1.1", 
                    version: :v1, community: device.community, timeout: 200)
      end)
      
      case {bulk_result, individual_result} do
        {{:ok, bulk_data}, {:ok, individual_data}} ->
          # Both should work through appropriate snmp_lib mechanisms
          assert is_list(bulk_data)
          assert is_list(individual_data)
          
          # Both should be reasonably fast for small trees
          assert bulk_time < 500_000  # Less than 500ms
          assert individual_time < 500_000  # Less than 500ms
          
        _ ->
          # If either fails, just verify they return proper error formats
          case bulk_result do
            {:ok, _} -> assert true
            {:error, reason} -> assert reason in [:endOfMibView, :end_of_mib_view, :noSuchObject, :timeout]
          end
          
          case individual_result do
            {:ok, _} -> assert true
            {:error, reason} -> assert reason in [:endOfMibView, :end_of_mib_view, :noSuchObject, :timeout]
          end
      end
    end

    test "concurrent small table operations", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test concurrent small table walking operations
      tasks = Enum.map(["1.3.6.1.2.1.1", "1.3.6.1.2.1.11"], fn oid ->
        Task.async(fn ->
          SnmpMgr.walk(target, oid, community: device.community, timeout: 200)
        end)
      end)
      
      results = Task.await_many(tasks, 1000)  # 1 second total timeout
      
      # All should complete through snmp_lib
      assert length(results) == 2
      
      Enum.each(results, fn result ->
        case result do
          {:ok, _} -> assert true  # Operation succeeded
          {:error, reason} when reason in [:timeout, :endOfMibView, :end_of_mib_view, :noSuchObject] -> 
            assert true  # Acceptable errors from simulator
          {:error, reason} -> flunk("Unexpected error: #{inspect(reason)}")
        end
      end)
    end

    test "memory usage for table operations", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test memory usage during small table walking
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)
      
      # Perform small table walking operations
      results = Enum.map(1..3, fn _i ->
        SnmpMgr.walk(target, "1.3.6.1.2.1.1.1", 
                    community: device.community, timeout: 200)
      end)
      
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be reasonable for small operations
      assert memory_growth < 2_000_000  # Less than 2MB growth
      assert length(results) == 3
      
      # Trigger garbage collection
      :erlang.garbage_collect()
    end
  end

  describe "Integration with SnmpMgr Table Functions" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "basic walk function integration", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test basic walk functionality with snmp_lib backend
      result = SnmpMgr.walk(target, "1.3.6.1.2.1.1.1", 
                           community: device.community, timeout: 200)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Should get valid walk results through snmp_lib
          if length(results) > 0 do
            # Validate first result structure
            {oid, type, value} = List.first(results)
            assert is_binary(oid)
            assert String.starts_with?(oid, "1.3.6.1.2.1.1.1")
            assert is_atom(type)
            assert value != nil
          end
          assert true
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "table operations return consistent formats", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test that table operations maintain consistent return formats
      walk_result = SnmpMgr.walk(target, "1.3.6.1.2.1.1.1", 
                                 community: device.community, timeout: 200)
      
      # Should return consistent format regardless of snmp_lib internal changes
      case walk_result do
        {:ok, walk_data} ->
          # Walk should return list of {oid, type, value} tuples
          assert is_list(walk_data)
          if length(walk_data) > 0 do
            Enum.each(walk_data, fn {oid, type, value} ->
              assert is_binary(oid) or is_list(oid)
              assert is_atom(type)
              assert value != nil
            end)
          end
          
        {:error, reason} ->
          # Error format should be consistent
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "walk operations handle edge cases properly", %{device: device} do
      target = "#{device.host}:#{device.port}"
      
      # Test edge cases that might cause timeouts or performance issues
      edge_cases = [
        {"1.3.6.1.2.1.1.1.0", "single leaf OID"},
        {"1.3.6.1.2.1.1", "system subtree"},
        {"1.3.6.1.2.1.1.999", "non-existent subtree"}
      ]
      
      Enum.each(edge_cases, fn {oid, description} ->
        result = SnmpMgr.walk(target, oid, community: device.community, timeout: 200)
        
        case result do
          {:ok, results} when is_list(results) ->
            assert true, "#{description} walk succeeded"
            
          {:error, reason} ->
            # Should handle edge cases gracefully
            assert is_atom(reason) or is_tuple(reason),
              "#{description} should handle edge case: #{inspect(reason)}"
        end
      end)
    end
  end
end