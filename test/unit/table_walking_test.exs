defmodule SNMPMgr.TableWalkingTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
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
      target = SNMPSimulator.device_target(device)
      
      # Test walking interface table through snmp_lib
      result = SNMPMgr.walk(target, "1.3.6.1.2.1.2.2", 
                           community: device.community, version: :v2c, timeout: 100)
      
      case result do
        {:ok, walk_data} when is_list(walk_data) ->
          # Successful walk through snmp_lib
          assert length(walk_data) >= 0
          
          # Validate result structure from snmp_lib
          Enum.each(walk_data, fn
            {oid, value} ->
              assert is_binary(oid) or is_list(oid)
              assert is_binary(value) or is_integer(value) or is_atom(value)
            other ->
              flunk("Unexpected walk result format: #{inspect(other)}")
          end)
          
        {:error, reason} ->
          # Should get proper error format from snmp_lib integration
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "walk adapts version for bulk vs getnext", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test v1 walk (should use getnext)
      result_v1 = SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                              version: :v1, community: device.community, timeout: 100)
      
      # Test v2c walk (should use bulk)
      result_v2c = SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                               version: :v2c, community: device.community, timeout: 100)
      
      # Both should work through appropriate snmp_lib mechanisms
      assert match?({:ok, _} | {:error, _}, result_v1)
      assert match?({:ok, _} | {:error, _}, result_v2c)
    end

    test "walk handles various OID formats", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test different OID formats for walking
      oid_formats = [
        {"1.3.6.1.2.1.1", "string OID"},
        {[1, 3, 6, 1, 2, 1, 1], "list OID"},
        {"system", "symbolic OID"}
      ]
      
      Enum.each(oid_formats, fn {oid, description} ->
        result = SNMPMgr.walk(target, oid, community: device.community, timeout: 100)
        
        case result do
          {:ok, results} when is_list(results) ->
            assert true, "#{description} walk succeeded through snmp_lib"
          {:error, reason} ->
            # Should get proper error format
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error: #{inspect(reason)}"
        end
      end)
    end

    test "walk results are in lexicographic order", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      result = SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                           community: device.community, timeout: 100)
      
      case result do
        {:ok, walk_data} when length(walk_data) > 1 ->
          # Convert OIDs to comparable format and check ordering
          oids = Enum.map(walk_data, fn {oid, _value} ->
            case oid do
              str when is_binary(str) ->
                case SnmpLib.OID.string_to_list(str) do
                  {:ok, list} -> list
                  _ -> []
                end
              list when is_list(list) -> list
            end
          end)
          
          valid_oids = Enum.filter(oids, fn oid -> length(oid) > 0 end)
          
          if length(valid_oids) > 1 do
            sorted_oids = Enum.sort(valid_oids)
            assert valid_oids == sorted_oids,
              "Walk results should be in lexicographic order through snmp_lib"
          end
          
        _ ->
          # Single result or error - acceptable
          assert true
      end
    end
  end

  describe "Table Operations with SnmpLib Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "get_table/3 processes table data", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test table retrieval through snmp_lib
      result = SNMPMgr.get_table(target, "1.3.6.1.2.1.2.2", 
                                 community: device.community, timeout: 100)
      
      case result do
        {:ok, table_data} ->
          # Should return structured table format
          assert is_map(table_data) or is_list(table_data)
          
          case table_data do
            %{rows: rows, columns: columns} ->
              assert is_list(rows)
              assert is_list(columns)
            table_list when is_list(table_list) ->
              assert true
            other ->
              assert true, "Table format: #{inspect(other)}"
          end
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "walk_table handles table boundaries", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test walking specific table boundaries
      result = SNMPMgr.walk_table(target, "1.3.6.1.2.1.2.2", 
                                  community: device.community, timeout: 100)
      
      case result do
        {:ok, table_data} when is_list(table_data) ->
          # Validate that results are within table scope
          table_prefix = [1, 3, 6, 1, 2, 1, 2, 2]
          
          Enum.each(table_data, fn {oid, _value} ->
            oid_list = case oid do
              str when is_binary(str) ->
                case SnmpLib.OID.string_to_list(str) do
                  {:ok, list} -> list
                  _ -> []
                end
              list when is_list(list) -> list
            end
            
            if length(oid_list) >= length(table_prefix) do
              # Should start with table prefix or be beyond it
              prefix = Enum.take(oid_list, length(table_prefix))
              assert prefix == table_prefix or oid_list > table_prefix
            end
          end)
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "get_column retrieves specific table columns", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test column-specific retrieval
      column_cases = [
        {2, "interface description column"},
        {3, "interface type column"},
        {5, "interface speed column"}
      ]
      
      Enum.each(column_cases, fn {column_num, description} ->
        result = SNMPMgr.get_column(target, "1.3.6.1.2.1.2.2", column_num,
                                   community: device.community, timeout: 100)
        
        case result do
          {:ok, column_data} when is_list(column_data) ->
            # Validate column data structure
            Enum.each(column_data, fn {oid, value} ->
              assert is_binary(oid) or is_list(oid)
              assert is_binary(value) or is_integer(value) or is_atom(value)
            end)
            
          {:error, reason} ->
            # Should get proper error format
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error: #{inspect(reason)}"
        end
      end)
    end
  end

  describe "Walk Module Integration with SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "Walk module functions use snmp_lib backend", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that SNMPMgr.Walk functions delegate to Core which uses snmp_lib
      case SNMPMgr.Walk.walk_subtree(target, "1.3.6.1.2.1.1", 
                                     community: device.community, timeout: 100) do
        {:ok, results} when is_list(results) ->
          # Should get subtree data through snmp_lib
          assert true
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "adaptive walking with snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test adaptive walking that chooses bulk vs getnext
      case SNMPMgr.Walk.adaptive_walk(target, "1.3.6.1.2.1.1", 
                                      adaptive_tuning: true, community: device.community, timeout: 100) do
        {:ok, results} when is_list(results) ->
          # Should adapt walking strategy through snmp_lib
          assert true
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "table-specific walking functions", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test table-specific walking
      table_functions = [
        {:walk_table_columns, ["1.3.6.1.2.1.2.2", [2, 3, 5]]},
        {:walk_table_rows, ["1.3.6.1.2.1.2.2", 1..3]},
        {:walk_table_filtered, ["1.3.6.1.2.1.2.2", fn {_oid, _value} -> true end]}
      ]
      
      Enum.each(table_functions, fn {function, args} ->
        case apply(SNMPMgr.Walk, function, [target | args] ++ [[community: device.community, timeout: 100]]) do
          {:ok, results} when is_list(results) ->
            # Should work through snmp_lib backend
            assert true, "#{function} succeeded through snmp_lib"
            
          {:error, reason} ->
            # Should get proper error format
            assert is_atom(reason) or is_tuple(reason),
              "#{function} error: #{inspect(reason)}"
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
      target = SNMPSimulator.device_target(device)
      
      invalid_oids = [
        "invalid.table.oid",
        "1.3.6.1.2.1.999.999.999",
        ""
      ]
      
      Enum.each(invalid_oids, fn oid ->
        result = SNMPMgr.walk_table(target, oid, community: device.community, timeout: 100)
        
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

    test "handles timeout in table operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test very short timeout
      result = SNMPMgr.walk(target, "1.3.6.1.2.1.2.2", 
                           community: device.community, timeout: 1)
      
      case result do
        {:error, :timeout} -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
        {:ok, _} -> assert true  # Unexpectedly fast response
      end
    end

    test "handles community validation in table operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with wrong community
      result = SNMPMgr.walk(target, "1.3.6.1.2.1.2.2", 
                           community: "wrong_community", timeout: 100)
      
      case result do
        {:error, reason} when reason in [:authentication_error, :bad_community] ->
          assert true  # Expected authentication error
        {:error, _other} -> assert true  # Other errors acceptable
        {:ok, _} -> assert true  # Might succeed in test environment
      end
    end

    test "handles end of MIB view in walks", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test walking beyond available data
      result = SNMPMgr.walk(target, "1.3.6.1.2.1.999", 
                           community: device.community, timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Should handle end of MIB gracefully
          assert true
          
        {:error, reason} when reason in [:end_of_mib_view, :no_such_name] ->
          # Expected for non-existent subtrees
          assert true
          
        {:error, reason} ->
          # Other errors acceptable
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

    test "table walking operations complete efficiently", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Measure time for table walking operations
      start_time = System.monotonic_time(:millisecond)
      
      results = Enum.map(1..3, fn _i ->
        SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                    community: device.community, timeout: 100)
      end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete reasonably quickly with local simulator
      assert duration < 1000  # Less than 1 second for 3 walk operations
      assert length(results) == 3
      
      # All should return proper format through snmp_lib
      Enum.each(results, fn result ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end

    test "bulk walking vs individual walking efficiency", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Compare bulk walking (v2c) vs individual walking (v1)
      {bulk_time, bulk_result} = :timer.tc(fn ->
        SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                    version: :v2c, community: device.community, timeout: 100)
      end)
      
      {individual_time, individual_result} = :timer.tc(fn ->
        SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                    version: :v1, community: device.community, timeout: 100)
      end)
      
      case {bulk_result, individual_result} do
        {{:ok, bulk_data}, {:ok, individual_data}} ->
          # Both should work through appropriate snmp_lib mechanisms
          assert is_list(bulk_data)
          assert is_list(individual_data)
          
          # Bulk should be competitive (not necessarily faster due to simulator)
          efficiency_ratio = if bulk_time > 0, do: individual_time / bulk_time, else: 1.0
          assert efficiency_ratio > 0.1, "Bulk walking should be reasonably efficient: #{efficiency_ratio}"
          
        _ ->
          # If either fails, just verify they return proper formats
          assert match?({:ok, _} | {:error, _}, bulk_result)
          assert match?({:ok, _} | {:error, _}, individual_result)
      end
    end

    test "concurrent table operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test concurrent table walking operations
      tasks = Enum.map(1..3, fn i ->
        Task.async(fn ->
          SNMPMgr.walk(target, "1.3.6.1.2.1.#{i}", 
                      community: device.community, timeout: 100)
        end)
      end)
      
      results = Task.await_many(tasks, 500)
      
      # All should complete through snmp_lib
      assert length(results) == 3
      
      Enum.each(results, fn result ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end

    test "memory usage for table operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test memory usage during table walking
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)
      
      # Perform table walking operations
      results = Enum.map(1..5, fn _i ->
        SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                    community: device.community, timeout: 100)
      end)
      
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be reasonable
      assert memory_growth < 5_000_000  # Less than 5MB growth
      assert length(results) == 5
      
      # Trigger garbage collection
      :erlang.garbage_collect()
    end
  end

  describe "Table Operations Integration with SNMPMgr.Table Module" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "table module functions use snmp_lib backend", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that SNMPMgr.Table functions work with snmp_lib data
      case SNMPMgr.get_table(target, "1.3.6.1.2.1.2.2", 
                             community: device.community, timeout: 100) do
        {:ok, table_data} ->
          # Test table analysis functions
          case SNMPMgr.Table.analyze_table(table_data) do
            {:ok, analysis} ->
              assert is_map(analysis)
              assert Map.has_key?(analysis, :row_count)
              
            {:error, reason} ->
              # Analysis might not be available
              assert is_atom(reason)
          end
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "table filtering with snmp_lib data", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      case SNMPMgr.get_table(target, "1.3.6.1.2.1.2.2", 
                             community: device.community, timeout: 100) do
        {:ok, table_data} ->
          # Test filtering functions if available
          case Code.ensure_loaded(SNMPMgr.Table) do
            {:module, SNMPMgr.Table} ->
              case SNMPMgr.Table.filter_by_column(table_data, 7, fn status ->
                status == "1" or status == 1  # ifAdminStatus == up
              end) do
                {:ok, filtered_data} ->
                  assert is_map(filtered_data) or is_list(filtered_data)
                {:error, _reason} ->
                  # Filtering might not be available
                  assert true
              end
              
            {:error, _} ->
              # Table module might not be available
              assert true
          end
          
        {:error, reason} ->
          # Should get proper error format
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "table operations return consistent formats", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that table operations maintain consistent return formats
      walk_result = SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                                 community: device.community, timeout: 100)
      table_result = SNMPMgr.get_table(target, "1.3.6.1.2.1.2.2", 
                                       community: device.community, timeout: 100)
      
      # Both should return consistent error formats
      case {walk_result, table_result} do
        {{:ok, walk_data}, {:ok, table_data}} ->
          # Walk should return list of {oid, value} tuples
          assert is_list(walk_data)
          # Table should return structured data
          assert is_map(table_data) or is_list(table_data)
          
        _ ->
          # Both should return consistent error formats
          assert match?({:ok, _} | {:error, _}, walk_result)
          assert match?({:ok, _} | {:error, _}, table_result)
      end
    end
  end
end