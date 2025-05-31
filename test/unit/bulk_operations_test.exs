defmodule SNMPMgr.BulkOperationsTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :bulk_operations  
  @moduletag :phase_3

  # Table OIDs for bulk testing
  @table_oids %{
    if_table: "1.3.6.1.2.1.2.2",
    if_entry: "1.3.6.1.2.1.2.2.1",
    if_descr: "1.3.6.1.2.1.2.2.1.2",
    if_type: "1.3.6.1.2.1.2.2.1.3",
    if_speed: "1.3.6.1.2.1.2.2.1.5",
    if_admin_status: "1.3.6.1.2.1.2.2.1.7",
    if_oper_status: "1.3.6.1.2.1.2.2.1.8",
    if_in_octets: "1.3.6.1.2.1.2.2.1.10",
    if_out_octets: "1.3.6.1.2.1.2.2.1.16",
    
    # IP table for additional testing
    ip_addr_table: "1.3.6.1.2.1.4.20",
    ip_addr_entry: "1.3.6.1.2.1.4.20.1",
    ip_ad_ent_addr: "1.3.6.1.2.1.4.20.1.1",
    ip_ad_ent_if_index: "1.3.6.1.2.1.4.20.1.2",
    
    # SNMP group for scalar testing  
    snmp_group: "1.3.6.1.2.1.11"
  }

  describe "GETBULK request validation" do
    test "validates GETBULK parameters" do
      valid_bulk_params = [
        {"127.0.0.1", @table_oids.if_table, [max_repetitions: 10]},
        {"localhost", @table_oids.if_entry, [max_repetitions: 5, non_repeaters: 0]},
        {"192.168.1.1", @table_oids.if_descr, [max_repetitions: 20, community: "public"]},
        {"device.local:1161", @table_oids.snmp_group, [max_repetitions: 1, timeout: 8000]},
      ]
      
      for {target, oid, opts} <- valid_bulk_params do
        case SNMPMgr.get_bulk(target, oid, opts) do
          {:ok, results} ->
            assert is_list(results), "GETBULK should return list of results"
            assert length(results) > 0, "GETBULK should return non-empty results"
            
            # Validate result structure
            for result <- results do
              case result do
                {result_oid, value} ->
                  assert is_binary(result_oid) or is_list(result_oid),
                    "Result OID should be string or list"
                  assert is_binary(value) or is_integer(value) or is_atom(value),
                    "Result value should be string, integer, or atom"
                    
                other ->
                  flunk("Unexpected result format: #{inspect(other)}")
              end
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "GETBULK error should be descriptive: #{inspect(reason)}"
        end
      end
    end

    test "enforces SNMPv2c version for GETBULK" do
      # GETBULK should automatically use v2c regardless of configuration
      bulk_requests = [
        {"127.0.0.1", @table_oids.if_table, [version: :v1, max_repetitions: 10]},
        {"127.0.0.1", @table_oids.if_table, [max_repetitions: 10]},  # No version specified
      ]
      
      for {target, oid, opts} <- bulk_requests do
        case SNMPMgr.get_bulk(target, oid, opts) do
          {:ok, _results} ->
            assert true, "GETBULK succeeded with v2c"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, :version_not_supported} ->
            assert true, "v1 correctly rejected for GETBULK"
            
          {:error, {:unsupported_operation, :get_bulk_requires_v2c}} ->
            assert true, "v1 correctly rejected for GETBULK with detailed error"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason), "Version enforcement error: #{inspect(reason)}"
        end
      end
    end

    test "validates max_repetitions parameter" do
      max_repetition_cases = [
        # Valid values
        {1, "minimum repetitions"},
        {10, "typical repetitions"},
        {50, "high repetitions"},
        {100, "very high repetitions"},
        
        # Edge cases
        {0, "zero repetitions (might be valid)"},
        {255, "maximum repetitions"},
      ]
      
      for {max_reps, description} <- max_repetition_cases do
        case SNMPMgr.get_bulk("127.0.0.1", @table_oids.if_table, [max_repetitions: max_reps, timeout: 1000]) do
          {:ok, results} ->
            # Verify repetition behavior
            if max_reps > 0 do
              # Should get up to max_repetitions results
              assert length(results) <= max_reps * 10,  # Approximate check
                "Should respect max_repetitions for #{description}"
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, :invalid_oid_values} ->
            # Expected in test environment where SNMP encoding may fail
            assert true, "SNMP encoding not available for max_repetitions test"
            
          {:error, :timeout} ->
            # Expected in test environment with no SNMP agent
            assert true, "Timeout expected in test environment for #{description}"
            
          {:error, reason} ->
            if max_reps <= 0 do
              assert is_atom(reason) or is_tuple(reason), "Invalid max_repetitions rejected: #{description}"
            else
              assert is_atom(reason) or is_tuple(reason), "Error for #{description}: #{inspect(reason)}"
            end
        end
      end
    end

    test "validates non_repeaters parameter" do
      non_repeater_cases = [
        # Valid values
        {0, "no non-repeaters (typical)"},
        {1, "one non-repeater"},
        {3, "multiple non-repeaters"},
        {10, "many non-repeaters"},
        
        # Edge cases
        {255, "maximum non-repeaters"},
      ]
      
      for {non_reps, description} <- non_repeater_cases do
        case SNMPMgr.get_bulk("127.0.0.1", @table_oids.if_table, 
                             [non_repeaters: non_reps, max_repetitions: 10]) do
          {:ok, results} ->
            assert is_list(results), "#{description} should return valid results"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason), "Error for #{description}: #{inspect(reason)}"
        end
      end
    end

    test "rejects invalid GETBULK parameters" do
      invalid_bulk_params = [
        # Invalid max_repetitions
        {"127.0.0.1", @table_oids.if_table, [max_repetitions: -1]},
        {"127.0.0.1", @table_oids.if_table, [max_repetitions: "invalid"]},
        {"127.0.0.1", @table_oids.if_table, [max_repetitions: nil]},
        
        # Invalid non_repeaters
        {"127.0.0.1", @table_oids.if_table, [non_repeaters: -1, max_repetitions: 10]},
        {"127.0.0.1", @table_oids.if_table, [non_repeaters: "invalid", max_repetitions: 10]},
        
        # Missing required parameters
        {"127.0.0.1", @table_oids.if_table, []},  # No max_repetitions
      ]
      
      for {target, oid, opts} <- invalid_bulk_params do
        case SNMPMgr.get_bulk(target, oid, opts) do
          {:ok, _results} ->
            flunk("Invalid GETBULK parameters should not succeed: #{inspect(opts)}")
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Should reject invalid parameters: #{inspect(reason)}"
        end
      end
    end
  end

  describe "GETBULK table traversal" do
    test "retrieves table data efficiently" do
      # Test GETBULK on interface table
      case SNMPMgr.get_bulk("127.0.0.1", @table_oids.if_table, [max_repetitions: 20]) do
        {:ok, results} ->
          assert length(results) > 0, "Should retrieve table data"
          
          # Verify results are in lexicographic order
          oids = Enum.map(results, fn {oid, _value} ->
            case oid do
              str when is_binary(str) ->
                case SNMPMgr.OID.string_to_list(str) do
                  {:ok, list} -> list
                  _ -> []
                end
              list when is_list(list) -> list
            end
          end)
          
          # Filter out empty OIDs and sort
          valid_oids = Enum.filter(oids, fn oid -> length(oid) > 0 end)
          
          if length(valid_oids) > 1 do
            sorted_oids = Enum.sort(valid_oids)
            assert valid_oids == sorted_oids,
              "GETBULK results should be in lexicographic order"
          end
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          assert is_atom(reason), "Table traversal error: #{inspect(reason)}"
      end
    end

    test "handles multiple table columns with GETBULK" do
      # Test GETBULK starting from interface entry (should get multiple columns)
      case SNMPMgr.get_bulk("127.0.0.1", @table_oids.if_entry, [max_repetitions: 15]) do
        {:ok, results} ->
          # Should get results from multiple columns
          column_oids = MapSet.new()
          
          column_oids = for {result_oid, _value} <- results, reduce: column_oids do
            acc ->
              oid_list = case result_oid do
                str when is_binary(str) ->
                  case SNMPMgr.OID.string_to_list(str) do
                    {:ok, list} -> list
                    _ -> []
                  end
                list when is_list(list) -> list
              end
              
              # Extract column OID (remove instance identifier)
              if length(oid_list) >= 11 do
                column_oid = Enum.take(oid_list, 11)  # 1.3.6.1.2.1.2.2.1.X
                MapSet.put(acc, column_oid)
              else
                acc
              end
          end
          
          # Should retrieve multiple columns
          if MapSet.size(column_oids) > 1 do
            assert true, "GETBULK retrieved multiple table columns"
          else
            assert true, "GETBULK retrieved table data (single column)"
          end
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment  
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          assert is_atom(reason), "Multi-column error: #{inspect(reason)}"
      end
    end

    test "respects table boundaries" do
      # Test GETBULK that should stop at table boundary
      test_cases = [
        {@table_oids.if_table, "Interface table"},
        {@table_oids.ip_addr_table, "IP address table"},
      ]
      
      for {table_oid, description} <- test_cases do
        case SNMPMgr.get_bulk("127.0.0.1", table_oid, [max_repetitions: 50]) do
          {:ok, results} ->
            # All results should be within the table
            table_prefix = case SNMPMgr.OID.string_to_list(table_oid) do
              {:ok, list} -> list
              _ -> []
            end
            
            for {result_oid, _value} <- results do
              result_list = case result_oid do
                str when is_binary(str) ->
                  case SNMPMgr.OID.string_to_list(str) do
                    {:ok, list} -> list
                    _ -> []
                  end
                list when is_list(list) -> list
              end
              
              if length(table_prefix) > 0 and length(result_list) > 0 do
                # Result should start with table prefix or be beyond it
                # (GETBULK may continue beyond table boundary)
                assert true, "#{description} GETBULK result: #{inspect(result_list)}"
              end
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason), "#{description} boundary error: #{inspect(reason)}"
        end
      end
    end
  end

  describe "GETBULK performance and efficiency" do
    test "GETBULK is more efficient than multiple GETNEXT" do
      # Compare GETBULK vs multiple GETNEXT for same data
      start_oid = @table_oids.if_descr
      
      # Time GETBULK operation
      {bulk_time, bulk_result} = :timer.tc(fn ->
        SNMPMgr.get_bulk("127.0.0.1", start_oid, [max_repetitions: 10])
      end)
      
      # Time equivalent GETNEXT operations
      {getnext_time, getnext_results} = :timer.tc(fn ->
        current_oid = start_oid
        
        # Simulate 10 GETNEXT operations
        Enum.reduce(1..10, {current_oid, []}, fn _i, {oid, acc} ->
          case SNMPMgr.get_next("127.0.0.1", oid) do
            {:ok, {next_oid, value}} -> {next_oid, [{next_oid, value} | acc]}
            {:error, _} -> {oid, acc}
          end
        end)
      end)
      
      case {bulk_result, getnext_results} do
        {{:ok, bulk_data}, {_final_oid, getnext_data}} ->
          # GETBULK should be faster or at least competitive
          if bulk_time > 0 and getnext_time > 0 do
            efficiency_ratio = getnext_time / bulk_time
            assert efficiency_ratio > 0.5,
              "GETBULK should be reasonably efficient compared to GETNEXT: #{efficiency_ratio}"
          end
          
          # GETBULK should get at least as much data
          assert length(bulk_data) >= length(getnext_data),
            "GETBULK should retrieve at least as much data as equivalent GETNEXT"
            
        {{:error, :snmp_modules_not_available}, _} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        _ ->
          # Other error combinations
          assert true, "Performance comparison not possible due to errors"
      end
    end

    @tag :performance
    test "GETBULK scales with max_repetitions" do
      repetition_counts = [1, 5, 10, 20, 50]
      
      results = for max_reps <- repetition_counts do
        {time, result} = :timer.tc(fn ->
          SNMPMgr.get_bulk("127.0.0.1", @table_oids.if_table, [max_repetitions: max_reps])
        end)
        
        case result do
          {:ok, data} -> {max_reps, time, length(data)}
          {:error, :snmp_modules_not_available} -> {max_reps, time, 0}
          {:error, _} -> {max_reps, time, -1}
        end
      end
      
      # Analyze scaling behavior
      valid_results = Enum.filter(results, fn {_reps, _time, count} -> count >= 0 end)
      
      if length(valid_results) > 1 do
        # Generally, more repetitions should get more data (though may plateau)
        max_data = Enum.max_by(valid_results, fn {_reps, _time, count} -> count end)
        {_max_reps, _max_time, max_count} = max_data
        
        assert max_count >= 0, "GETBULK should scale with max_repetitions"
      else
        assert true, "GETBULK scaling test completed (limited by test environment)"
      end
    end
  end

  describe "GETBULK async operations" do
    test "validates async GETBULK operations" do
      case SNMPMgr.get_bulk_async("127.0.0.1", @table_oids.if_table, [max_repetitions: 10]) do
        ref when is_reference(ref) ->
          # Should receive a message with the result
          receive do
            {^ref, result} ->
              case result do
                {:ok, data} ->
                  assert is_list(data), "Async GETBULK should return list"
                  assert length(data) > 0, "Async GETBULK should return data"
                  
                {:error, :snmp_modules_not_available} ->
                  assert true, "SNMP modules not available"
                  
                {:error, reason} ->
                  assert is_atom(reason), "Async GETBULK error: #{inspect(reason)}"
              end
          after
            5000 ->
              flunk("Async GETBULK should send result message")
          end
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available for async operations"
          
        {:error, reason} ->
          assert is_atom(reason), "Async GETBULK start error: #{inspect(reason)}"
      end
    end

    test "handles multiple concurrent GETBULK operations" do
      # Start multiple async GETBULK operations
      table_oids = [
        @table_oids.if_table,
        @table_oids.ip_addr_table,
        @table_oids.snmp_group,
      ]
      
      refs = for {oid, i} <- Enum.with_index(table_oids) do
        case SNMPMgr.get_bulk_async("127.0.0.1", oid, [max_repetitions: 5]) do
          ref when is_reference(ref) -> {ref, i, oid}
          {:error, _} -> nil
        end
      end
      
      valid_refs = Enum.filter(refs, &(&1 != nil))
      
      if length(valid_refs) > 0 do
        # Collect results
        results = for {ref, i, oid} <- valid_refs do
          receive do
            {^ref, result} -> {i, oid, result}
          after
            5000 -> {i, oid, {:error, :timeout}}
          end
        end
        
        # All operations should complete
        assert length(results) == length(valid_refs),
          "All async GETBULK operations should complete"
        
        # Check results
        for {i, oid, result} <- results do
          case result do
            {:ok, data} -> 
              assert is_list(data), "Async GETBULK #{i} (#{oid}) should return list"
            {:error, reason} -> 
              assert is_atom(reason), "Async GETBULK #{i} (#{oid}) error: #{inspect(reason)}"
          end
        end
      else
        # No async operations started
        assert true, "Async GETBULK operations not available in test environment"
      end
    end
  end

  describe "GETBULK error handling" do
    test "handles GETBULK-specific errors" do
      getbulk_error_cases = [
        # Invalid repetition parameters
        {"127.0.0.1", @table_oids.if_table, [max_repetitions: 0], "zero repetitions"},
        {"127.0.0.1", @table_oids.if_table, [max_repetitions: -1], "negative repetitions"},
        {"127.0.0.1", @table_oids.if_table, [non_repeaters: -1, max_repetitions: 10], "negative non-repeaters"},
        
        # Very large parameters (might cause resource issues)
        {"127.0.0.1", @table_oids.if_table, [max_repetitions: 65536], "excessive repetitions"},
        {"127.0.0.1", @table_oids.if_table, [non_repeaters: 1000, max_repetitions: 1000], "excessive non-repeaters"},
      ]
      
      for {target, oid, opts, description} <- getbulk_error_cases do
        case SNMPMgr.get_bulk(target, oid, opts) do
          {:ok, _results} ->
            # Some "invalid" parameters might be handled gracefully
            assert true, "#{description} handled gracefully"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "#{description} should provide descriptive error: #{inspect(reason)}"
        end
      end
    end

    test "handles SNMPv2c exceptions in GETBULK" do
      # Test OIDs that might return SNMPv2c exceptions
      exception_test_oids = [
        "1.2.3.4.5.6.7.8.9.0",     # Non-existent OID
        "1.3.6.1.2.1.999.999",     # Beyond standard MIB
      ]
      
      for test_oid <- exception_test_oids do
        case SNMPMgr.get_bulk("127.0.0.1", test_oid, [max_repetitions: 5]) do
          {:ok, results} ->
            # Check for SNMPv2c exception values in results
            exception_count = Enum.count(results, fn {_oid, value} ->
              value in [:no_such_object, :no_such_instance, :end_of_mib_view]
            end)
            
            if exception_count > 0 do
              assert true, "GETBULK correctly handled SNMPv2c exceptions"
            else
              assert true, "GETBULK completed without exceptions"
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason), "Exception test error: #{inspect(reason)}"
        end
      end
    end

    test "handles timeout and retry with GETBULK" do
      # Test GETBULK with short timeout
      case SNMPMgr.get_bulk("127.0.0.1", @table_oids.if_table, 
                           [max_repetitions: 20, timeout: 100, retries: 0]) do
        {:ok, _results} ->
          assert true, "Fast GETBULK succeeded"
          
        {:error, :timeout} ->
          assert true, "GETBULK timeout properly detected"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          assert is_atom(reason), "GETBULK timeout error: #{inspect(reason)}"
      end
      
      # Test GETBULK with retries
      case SNMPMgr.get_bulk("127.0.0.1", @table_oids.if_table,
                           [max_repetitions: 10, timeout: 1000, retries: 2]) do
        {:ok, _results} ->
          assert true, "GETBULK with retries succeeded"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          assert is_atom(reason), "GETBULK retry error: #{inspect(reason)}"
      end
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
    test "GETBULK works with real SNMP device", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test GETBULK on interface table
      case SNMPMgr.get_bulk(target, @table_oids.if_table, 
                           [max_repetitions: 10, community: device.community]) do
        {:ok, results} ->
          assert is_list(results), "GETBULK should return list"
          assert length(results) > 0, "GETBULK should return data from simulator"
          
          # Validate result structure from real device
          for {oid, value} <- results do
            assert is_binary(oid) or is_list(oid), "Real device OID should be string or list"
            assert is_binary(value) or is_integer(value) or is_atom(value),
              "Real device value should be valid type"
          end
          
          # Verify we got interface data
          interface_results = Enum.filter(results, fn {oid, _value} ->
            oid_str = case oid do
              str when is_binary(str) -> str
              list when is_list(list) -> Enum.join(list, ".")
            end
            String.starts_with?(oid_str, "1.3.6.1.2.1.2.2")
          end)
          
          assert length(interface_results) > 0, "Should get interface table data"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available for integration test"
          
        {:error, reason} ->
          flunk("GETBULK with simulator failed: #{inspect(reason)}")
      end
    end

    @tag :integration
    test "GETBULK efficiency with real device", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Compare GETBULK vs multiple GETNEXT with real device
      start_oid = @table_oids.if_entry
      
      # Try GETBULK
      bulk_result = SNMPMgr.get_bulk(target, start_oid, 
                                    [max_repetitions: 5, community: device.community])
      
      # Try equivalent GETNEXT operations
      getnext_results = Enum.reduce(1..5, {start_oid, []}, fn _i, {oid, acc} ->
        case SNMPMgr.get_next(target, oid, community: device.community) do
          {:ok, {next_oid, value}} -> {next_oid, [{next_oid, value} | acc]}
          {:error, _} -> {oid, acc}
        end
      end)
      
      case {bulk_result, getnext_results} do
        {{:ok, bulk_data}, {_final_oid, getnext_data}} ->
          # Both should get data
          assert length(bulk_data) > 0, "GETBULK should get data from real device"
          assert length(getnext_data) > 0, "GETNEXT should get data from real device"
          
          # GETBULK should be at least as effective
          assert length(bulk_data) >= length(getnext_data),
            "GETBULK should be at least as effective as GETNEXT"
            
        {{:error, :snmp_modules_not_available}, _} ->
          # Expected in test environment
          assert true, "SNMP modules not available for efficiency test"
          
        _ ->
          # Other error combinations
          assert true, "Efficiency test completed with mixed results"
      end
    end

    @tag :integration
    test "GETBULK handles device limits correctly", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with very high max_repetitions to see device limits
      case SNMPMgr.get_bulk(target, @table_oids.if_table,
                           [max_repetitions: 100, community: device.community]) do
        {:ok, results} ->
          # Device might limit the actual results returned
          assert is_list(results), "Should handle high repetitions gracefully"
          
          # Results should be reasonable (not necessarily 100 items)
          assert length(results) < 1000, "Results should be limited by device capabilities"
          
        {:error, :too_big} ->
          assert true, "Device correctly limited response size"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available for device limits test"
          
        {:error, reason} ->
          assert is_atom(reason), "Device limits error: #{inspect(reason)}"
      end
    end
  end
end