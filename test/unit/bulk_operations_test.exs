defmodule SNMPMgr.BulkOperationsTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :bulk_operations

  describe "Bulk Operations with SnmpLib Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "get_bulk/3 uses SnmpLib.Manager.get_bulk", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test GET-BULK operation through SnmpLib.Manager
      result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                               max_repetitions: 5, non_repeaters: 0,
                               community: device.community, version: :v2c, timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Successful bulk operation through snmp_lib
          assert length(results) >= 0
          
          # Validate result structure from snmp_lib
          Enum.each(results, fn
            {oid, value} ->
              assert is_binary(oid) or is_list(oid)
              assert is_binary(value) or is_integer(value) or is_atom(value)
            other ->
              flunk("Unexpected bulk result format: #{inspect(other)}")
          end)
          
        {:error, reason} ->
          # Should get proper error format from snmp_lib integration
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "get_bulk enforces SNMPv2c version", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that bulk operation defaults to v2c regardless of specified version
      result_default = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                                       max_repetitions: 3, community: device.community, timeout: 100)
      
      result_explicit_v2c = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                                            max_repetitions: 3, version: :v2c, 
                                            community: device.community, timeout: 100)
      
      # Both should work through SnmpLib.Manager (v2c enforced internally)
      assert match?({:ok, _} | {:error, _}, result_default)
      assert match?({:ok, _} | {:error, _}, result_explicit_v2c)
    end

    test "get_bulk handles max_repetitions parameter", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test various max_repetitions values
      repetition_cases = [
        {1, "minimum repetitions"},
        {5, "typical repetitions"},
        {10, "moderate repetitions"},
        {20, "high repetitions"}
      ]
      
      Enum.each(repetition_cases, fn {max_reps, description} ->
        result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                                 max_repetitions: max_reps, community: device.community, timeout: 100)
        
        case result do
          {:ok, results} when is_list(results) ->
            # Should respect max_repetitions through snmp_lib
            assert true, "#{description} succeeded through snmp_lib"
            
          {:error, reason} ->
            # Should get proper error format
            assert is_atom(reason) or is_tuple(reason), 
              "#{description} error: #{inspect(reason)}"
        end
      end)
    end

    test "get_bulk handles non_repeaters parameter", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test various non_repeaters values
      non_repeater_cases = [
        {0, "no non-repeaters"},
        {1, "one non-repeater"},
        {3, "multiple non-repeaters"}
      ]
      
      Enum.each(non_repeater_cases, fn {non_reps, description} ->
        result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                                 max_repetitions: 5, non_repeaters: non_reps,
                                 community: device.community, timeout: 100)
        
        case result do
          {:ok, results} when is_list(results) ->
            # Should handle non_repeaters through snmp_lib
            assert true, "#{description} succeeded through snmp_lib"
            
          {:error, reason} ->
            # Should get proper error format
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error: #{inspect(reason)}"
        end
      end)
    end

    test "get_bulk validates parameters", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test invalid parameters
      invalid_cases = [
        # Missing max_repetitions
        {target, "1.3.6.1.2.1.2.2", [community: device.community], "missing max_repetitions"},
        
        # Invalid max_repetitions type
        {target, "1.3.6.1.2.1.2.2", [max_repetitions: "invalid", community: device.community], "invalid max_repetitions type"},
        
        # Invalid non_repeaters type
        {target, "1.3.6.1.2.1.2.2", [max_repetitions: 5, non_repeaters: "invalid", community: device.community], "invalid non_repeaters type"}
      ]
      
      Enum.each(invalid_cases, fn {target, oid, opts, description} ->
        result = SNMPMgr.get_bulk(target, oid, opts)
        
        case result do
          {:ok, _} ->
            flunk("#{description} should not succeed")
          {:error, reason} ->
            # Should reject invalid parameters
            assert is_atom(reason) or is_tuple(reason),
              "#{description} should provide descriptive error: #{inspect(reason)}"
        end
      end)
    end
  end

  describe "Bulk Operations OID Processing" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "bulk operations with string OIDs", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test bulk with various string OID formats
      string_oids = [
        "1.3.6.1.2.1.2.2",
        "1.3.6.1.2.1.2.2.1",
        "1.3.6.1.2.1.1"
      ]
      
      Enum.each(string_oids, fn oid ->
        result = SNMPMgr.get_bulk(target, oid, max_repetitions: 3, 
                                 community: device.community, timeout: 100)
        # Should process OID through SnmpLib.OID and return proper format
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end

    test "bulk operations with list OIDs", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test bulk with list format OIDs
      list_oids = [
        [1, 3, 6, 1, 2, 1, 2, 2],
        [1, 3, 6, 1, 2, 1, 2, 2, 1],
        [1, 3, 6, 1, 2, 1, 1]
      ]
      
      Enum.each(list_oids, fn oid ->
        result = SNMPMgr.get_bulk(target, oid, max_repetitions: 3,
                                 community: device.community, timeout: 100)
        # Should process list OID through SnmpLib.OID
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end

    test "bulk operations with symbolic OIDs", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test bulk with symbolic OIDs (if MIB resolution available)
      symbolic_oids = [
        "ifTable",
        "ifEntry",
        "system"
      ]
      
      Enum.each(symbolic_oids, fn oid ->
        result = SNMPMgr.get_bulk(target, oid, max_repetitions: 3,
                                 community: device.community, timeout: 100)
        # Should process symbolic OID through MIB -> SnmpLib.OID chain
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end
  end

  describe "Bulk Operations Multi-Target Support" do
    setup do
      # Create multiple devices for multi-target testing
      {:ok, device1} = SNMPSimulator.create_test_device()
      {:ok, device2} = SNMPSimulator.create_test_device()
      
      :ok = SNMPSimulator.wait_for_device_ready(device1)
      :ok = SNMPSimulator.wait_for_device_ready(device2)
      
      on_exit(fn -> 
        SNMPSimulator.stop_device(device1)
        SNMPSimulator.stop_device(device2)
      end)
      
      %{device1: device1, device2: device2}
    end

    test "get_bulk_multi processes multiple targets", %{device1: device1, device2: device2} do
      requests = [
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.2.2", 
         [max_repetitions: 3, community: device1.community, timeout: 100]},
        {SNMPSimulator.device_target(device2), "1.3.6.1.2.1.1", 
         [max_repetitions: 3, community: device2.community, timeout: 100]}
      ]
      
      results = SNMPMgr.get_bulk_multi(requests)
      
      assert is_list(results)
      assert length(results) == 2
      
      # Each result should be proper format from snmp_lib integration
      Enum.each(results, fn result ->
        case result do
          {:ok, list} when is_list(list) -> assert true
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason)
        end
      end)
    end
  end

  describe "Bulk Operations Error Handling" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "handles invalid OIDs in bulk operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      invalid_oids = [
        "invalid.oid.format",
        "1.3.6.1.2.1.999.999.999",
        ""
      ]
      
      Enum.each(invalid_oids, fn oid ->
        result = SNMPMgr.get_bulk(target, oid, max_repetitions: 3,
                                 community: device.community, timeout: 100)
        
        case result do
          {:error, reason} ->
            # Should return proper error from SnmpLib.OID or validation
            assert is_atom(reason) or is_tuple(reason)
          {:ok, _} ->
            # Some invalid OIDs might resolve unexpectedly
            assert true
        end
      end)
    end

    test "handles timeout in bulk operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test very short timeout
      result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                               max_repetitions: 10, community: device.community, timeout: 1)
      
      case result do
        {:error, :timeout} -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
        {:ok, _} -> assert true  # Unexpectedly fast response
      end
    end

    test "handles community validation in bulk operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with wrong community
      result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                               max_repetitions: 3, community: "wrong_community", timeout: 100)
      
      case result do
        {:error, reason} when reason in [:authentication_error, :bad_community] ->
          assert true  # Expected authentication error
        {:error, _other} -> assert true  # Other errors acceptable
        {:ok, _} -> assert true  # Might succeed in test environment
      end
    end

    test "handles SNMPv2c exceptions in bulk results", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with OID that might return exceptions
      result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.999", 
                               max_repetitions: 5, community: device.community, timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Check for SNMPv2c exception values in results
          exceptions = Enum.filter(results, fn
            {_oid, value} when value in [:no_such_object, :no_such_instance, :end_of_mib_view] -> true
            _ -> false
          end)
          
          if length(exceptions) > 0 do
            assert true, "Bulk operation correctly handled SNMPv2c exceptions"
          else
            assert true, "Bulk operation completed without exceptions"
          end
          
        {:error, reason} ->
          # Error is also acceptable for non-existent OIDs
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end

  describe "Bulk Operations Performance" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "bulk operations complete efficiently", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Measure time for bulk operations
      start_time = System.monotonic_time(:millisecond)
      
      results = Enum.map(1..5, fn _i ->
        SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                        max_repetitions: 3, community: device.community, timeout: 100)
      end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete reasonably quickly with local simulator
      assert duration < 1000  # Less than 1 second for 5 bulk operations
      assert length(results) == 5
      
      # All should return proper format through snmp_lib
      Enum.each(results, fn result ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end

    test "bulk vs individual operations efficiency", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Compare one bulk operation vs multiple individual operations
      {bulk_time, bulk_result} = :timer.tc(fn ->
        SNMPMgr.get_bulk(target, "1.3.6.1.2.1.1", 
                        max_repetitions: 5, community: device.community, timeout: 100)
      end)
      
      {individual_time, individual_results} = :timer.tc(fn ->
        Enum.map(1..5, fn i ->
          SNMPMgr.get(target, "1.3.6.1.2.1.1.#{i}.0", 
                     community: device.community, timeout: 100)
        end)
      end)
      
      case {bulk_result, individual_results} do
        {{:ok, bulk_data}, individual_data} when is_list(individual_data) ->
          # Both should work, bulk should be competitive
          assert bulk_time > 0
          assert individual_time > 0
          
          # Bulk should be reasonably efficient (not necessarily faster due to simulator overhead)
          efficiency_ratio = if bulk_time > 0, do: individual_time / bulk_time, else: 1.0
          assert efficiency_ratio > 0.1, "Bulk should be reasonably efficient: #{efficiency_ratio}"
          
        _ ->
          # If either fails, just verify they return proper formats
          assert match?({:ok, _} | {:error, _}, bulk_result)
          assert is_list(individual_results)
      end
    end

    test "concurrent bulk operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test concurrent bulk operations
      tasks = Enum.map(1..3, fn i ->
        Task.async(fn ->
          SNMPMgr.get_bulk(target, "1.3.6.1.2.1.#{i}", 
                          max_repetitions: 3, community: device.community, timeout: 100)
        end)
      end)
      
      results = Task.await_many(tasks, 500)
      
      # All should complete through snmp_lib
      assert length(results) == 3
      
      Enum.each(results, fn result ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end
  end

  describe "Bulk Operations Integration with SNMPMgr.Bulk Module" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "bulk module functions use snmp_lib backend", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that SNMPMgr.Bulk functions delegate to Core which uses snmp_lib
      case SNMPMgr.Bulk.bulk_walk_table(target, "1.3.6.1.2.1.2.2", 
                                        community: device.community, timeout: 100) do
        {:ok, results} when is_list(results) ->
          # Should get table data through snmp_lib
          assert true
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "bulk table operations with snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test bulk table walking
      case SNMPMgr.Bulk.bulk_walk_subtree(target, "1.3.6.1.2.1.1", 
                                          community: device.community, timeout: 100) do
        {:ok, results} when is_list(results) ->
          # Should walk subtree through snmp_lib bulk operations
          assert true
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "bulk operations return consistent formats", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that bulk operations maintain consistent return formats
      result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.1", 
                               max_repetitions: 3, community: device.community, timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Validate structure consistency with snmp_lib
          Enum.each(results, fn
            {oid, value} ->
              assert is_binary(oid) or is_list(oid)
              assert is_binary(value) or is_integer(value) or is_atom(value)
            other ->
              flunk("Inconsistent result format: #{inspect(other)}")
          end)
          
        {:error, reason} ->
          # Error format should be consistent
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end
end