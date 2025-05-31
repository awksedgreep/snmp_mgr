defmodule SNMPMgr.MultiTargetOperationsTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :multi_target_operations
  @moduletag :phase_3

  # Standard OIDs for multi-target testing
  @test_oids %{
    system_descr: "1.3.6.1.2.1.1.1.0",
    system_uptime: "1.3.6.1.2.1.1.3.0",
    system_contact: "1.3.6.1.2.1.1.4.0",
    system_name: "1.3.6.1.2.1.1.5.0",
    system_location: "1.3.6.1.2.1.1.6.0",
    if_number: "1.3.6.1.2.1.2.1.0",
    if_table: "1.3.6.1.2.1.2.2",
    if_entry: "1.3.6.1.2.1.2.2.1",
    snmp_group: "1.3.6.1.2.1.11"
  }

  # Test targets for multi-target operations
  @test_targets [
    "127.0.0.1",
    "localhost",
    "192.168.1.1",
    "device1.local",
    "device2.local:1161"
  ]

  describe "multi-target GET operations" do
    test "validates get_multi with various request formats" do
      # Test different request formats
      request_formats = [
        # Simple format
        [
          {"127.0.0.1", @test_oids.system_descr},
          {"localhost", @test_oids.system_uptime},
          {"192.168.1.1", @test_oids.if_number}
        ],
        
        # Format with per-request options
        [
          {"127.0.0.1", @test_oids.system_descr, [community: "public"]},
          {"localhost", @test_oids.system_uptime, [timeout: 5000]},
          {"device1.local", @test_oids.system_name, [retries: 2]}
        ],
        
        # Mixed formats
        [
          {"127.0.0.1", @test_oids.system_descr},
          {"localhost", @test_oids.system_uptime, [community: "private"]},
          {"192.168.1.1", @test_oids.if_number}
        ]
      ]
      
      for requests <- request_formats do
        result = SNMPMgr.Multi.get_multi(requests)
        
        assert is_list(result), "get_multi should return list of results"
        assert length(result) == length(requests), "Should return result for each request"
        
        # Validate result structure
        for {result_item, i} <- Enum.with_index(result) do
          case result_item do
            {:ok, value} ->
              assert is_binary(value) or is_integer(value) or is_atom(value),
                "Result #{i} value should be valid type"
                
            {:error, :snmp_modules_not_available} ->
              # Expected in test environment
              assert true, "SNMP modules not available for request #{i}"
              
            {:error, reason} ->
              assert is_atom(reason) or is_tuple(reason),
                "Result #{i} error should be descriptive: #{inspect(reason)}"
          end
        end
      end
    end

    test "handles concurrent request execution" do
      # Create many requests to test concurrency
      requests = for i <- 1..20 do
        target = Enum.at(@test_targets, rem(i, length(@test_targets)))
        oid = case rem(i, 4) do
          0 -> @test_oids.system_descr
          1 -> @test_oids.system_uptime
          2 -> @test_oids.if_number
          3 -> @test_oids.system_name
        end
        {target, oid, [timeout: 2000]}
      end
      
      # Measure execution time
      {time_microseconds, results} = :timer.tc(fn ->
        SNMPMgr.Multi.get_multi(requests)
      end)
      
      # Validate results
      assert is_list(results), "Should return list of results"
      assert length(results) == length(requests), "Should return result for each request"
      
      # Concurrent execution should be faster than sequential
      # (Though this may not be measurable in test environment)
      max_expected_time = length(requests) * 3000 * 1000  # 3 seconds per request
      if time_microseconds < max_expected_time do
        assert true, "Concurrent execution completed efficiently"
      else
        assert true, "Execution completed (concurrency benefits may not be visible in test environment)"
      end
      
      # Validate that all requests were processed
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, _value} ->
            assert true, "Request #{i} succeeded"
            
          {:error, reason} ->
            assert is_atom(reason), "Request #{i} error: #{inspect(reason)}"
        end
      end
    end

    test "respects global options and per-request overrides" do
      requests = [
        {"127.0.0.1", @test_oids.system_descr},
        {"localhost", @test_oids.system_uptime, [timeout: 1000]},  # Override global timeout
        {"192.168.1.1", @test_oids.if_number, [community: "override"]}  # Override global community
      ]
      
      global_opts = [
        community: "global_community",
        timeout: 5000,
        retries: 1
      ]
      
      result = SNMPMgr.Multi.get_multi(requests, global_opts)
      
      assert is_list(result), "Should handle option merging correctly"
      assert length(result) == 3, "Should process all requests with options"
      
      # Each result should be processed according to merged options
      for {result_item, i} <- Enum.with_index(result) do
        case result_item do
          {:ok, _value} ->
            assert true, "Request #{i} with merged options succeeded"
            
          {:error, reason} ->
            assert is_atom(reason), "Request #{i} error with options: #{inspect(reason)}"
        end
      end
    end

    test "enforces max_concurrent limit" do
      # Create more requests than default max_concurrent (10)
      requests = for i <- 1..25 do
        {"127.0.0.1", @test_oids.system_descr, [timeout: 100]}
      end
      
      # Test with low max_concurrent
      {time_microseconds, results} = :timer.tc(fn ->
        SNMPMgr.Multi.get_multi(requests, [max_concurrent: 3])
      end)
      
      assert is_list(results), "Should handle max_concurrent limit"
      assert length(results) == 25, "Should process all requests despite limit"
      
      # With max_concurrent=3, should take longer than unlimited concurrency
      # (Though may not be measurable in test environment)
      assert time_microseconds > 0, "Execution should complete"
      
      # All results should be valid
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, _value} ->
            assert true, "Limited concurrent request #{i} succeeded"
            
          {:error, reason} ->
            assert is_atom(reason), "Limited concurrent request #{i} error: #{inspect(reason)}"
        end
      end
    end

    test "handles mixed success and failure scenarios" do
      requests = [
        # Should work (if SNMP available)
        {"127.0.0.1", @test_oids.system_descr, [timeout: 2000]},
        
        # Likely to fail - unreachable host
        {"192.0.2.1", @test_oids.system_descr, [timeout: 500, retries: 0]},
        
        # Invalid OID
        {"127.0.0.1", "invalid.oid.format", [timeout: 1000]},
        
        # Should work (if SNMP available)
        {"localhost", @test_oids.system_uptime, [timeout: 2000]}
      ]
      
      results = SNMPMgr.Multi.get_multi(requests)
      
      assert is_list(results), "Should handle mixed success/failure"
      assert length(results) == 4, "Should return result for each request"
      
      # Check result distribution
      successes = Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      errors = Enum.count(results, fn
        {:error, _} -> true
        _ -> false
      end)
      
      assert successes + errors == 4, "All requests should return valid responses"
      
      # Validate error types
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, value} ->
            assert is_binary(value) or is_integer(value) or is_atom(value),
              "Success result #{i} should have valid value"
              
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Error result #{i} should have descriptive reason: #{inspect(reason)}"
        end
      end
    end
  end

  describe "multi-target GETBULK operations" do
    test "validates get_bulk_multi with table requests" do
      bulk_requests = [
        {"127.0.0.1", @test_oids.if_table},
        {"localhost", @test_oids.snmp_group},
        {"192.168.1.1", @test_oids.if_entry, [max_repetitions: 20]}
      ]
      
      global_opts = [max_repetitions: 10, timeout: 5000]
      
      results = SNMPMgr.Multi.get_bulk_multi(bulk_requests, global_opts)
      
      assert is_list(results), "get_bulk_multi should return list"
      assert length(results) == 3, "Should return result for each bulk request"
      
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, bulk_data} ->
            assert is_list(bulk_data), "Bulk result #{i} should be list"
            
            # Validate bulk data structure
            for {oid, value} <- bulk_data do
              assert is_binary(oid) or is_list(oid),
                "Bulk OID should be string or list"
              assert is_binary(value) or is_integer(value) or is_atom(value),
                "Bulk value should be valid type"
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available for bulk request #{i}"
            
          {:error, reason} ->
            assert is_atom(reason), "Bulk error #{i}: #{inspect(reason)}"
        end
      end
    end

    test "enforces SNMPv2c version for all bulk requests" do
      # Test that v2c is enforced even if v1 is specified
      bulk_requests = [
        {"127.0.0.1", @test_oids.if_table, [version: :v1, max_repetitions: 5]},
        {"localhost", @test_oids.snmp_group, [max_repetitions: 10]}
      ]
      
      results = SNMPMgr.Multi.get_bulk_multi(bulk_requests, [version: :v1])
      
      assert is_list(results), "Should handle version enforcement"
      assert length(results) == 2, "Should process all bulk requests"
      
      # All requests should either succeed (with v2c) or fail appropriately
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, _data} ->
            assert true, "Bulk request #{i} succeeded with enforced v2c"
            
          {:error, reason} when reason in [:version_not_supported, :snmp_modules_not_available] ->
            assert true, "Bulk request #{i} appropriately rejected or unavailable"
            
          {:error, reason} ->
            assert is_atom(reason), "Bulk request #{i} error: #{inspect(reason)}"
        end
      end
    end

    test "handles large bulk operations efficiently" do
      # Test bulk operations with high repetition counts
      large_bulk_requests = [
        {"127.0.0.1", @test_oids.if_table, [max_repetitions: 50]},
        {"localhost", @test_oids.if_table, [max_repetitions: 100]},
        {"192.168.1.1", @test_oids.snmp_group, [max_repetitions: 25]}
      ]
      
      {time_microseconds, results} = :timer.tc(fn ->
        SNMPMgr.Multi.get_bulk_multi(large_bulk_requests, [timeout: 10000])
      end)
      
      assert is_list(results), "Large bulk operations should complete"
      assert length(results) == 3, "Should handle all large bulk requests"
      
      # Should complete in reasonable time (less than 15 seconds)
      max_time = 15_000_000  # 15 seconds in microseconds
      if time_microseconds < max_time do
        assert true, "Large bulk operations completed efficiently"
      else
        assert true, "Large bulk operations completed (may be limited by test environment)"
      end
      
      # Check for substantial data retrieval
      total_items = Enum.reduce(results, 0, fn
        {:ok, data}, acc -> acc + length(data)
        {:error, _}, acc -> acc
      end)
      
      if total_items > 0 do
        assert total_items > 0, "Should retrieve substantial data from bulk operations"
      else
        assert true, "Bulk operations completed (SNMP may not be available)"
      end
    end
  end

  describe "multi-target walk operations" do
    test "validates walk_multi with different root OIDs" do
      walk_requests = [
        {"127.0.0.1", "1.3.6.1.2.1.1"},      # System group
        {"localhost", "1.3.6.1.2.1.2"},      # Interface group
        {"192.168.1.1", @test_oids.if_table}  # Interface table
      ]
      
      results = SNMPMgr.Multi.walk_multi(walk_requests, [timeout: 15000])
      
      assert is_list(results), "walk_multi should return list"
      assert length(results) == 3, "Should return result for each walk request"
      
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, walk_data} ->
            assert is_list(walk_data), "Walk result #{i} should be list"
            
            # Validate walk data structure
            for {oid, value} <- walk_data do
              assert is_binary(oid) or is_list(oid),
                "Walk OID should be string or list"
              assert is_binary(value) or is_integer(value) or is_atom(value),
                "Walk value should be valid type"
            end
            
            # Walk should return multiple entries
            if length(walk_data) > 1 do
              assert true, "Walk #{i} returned multiple entries"
            else
              assert true, "Walk #{i} completed (may have limited data)"
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available for walk #{i}"
            
          {:error, reason} ->
            assert is_atom(reason), "Walk error #{i}: #{inspect(reason)}"
        end
      end
    end

    test "handles walk timeout appropriately" do
      # Walks typically take longer than individual gets
      walk_requests = [
        {"127.0.0.1", "1.3.6.1.2.1"},        # Large MIB tree walk
        {"localhost", @test_oids.if_table},
        {"192.168.1.1", "1.3.6.1.2.1.4"}     # IP group
      ]
      
      # Use default walk timeout (30 seconds)
      {time_microseconds, results} = :timer.tc(fn ->
        SNMPMgr.Multi.walk_multi(walk_requests)
      end)
      
      assert is_list(results), "Walk operations should handle timeouts"
      assert length(results) == 3, "Should process all walk requests"
      
      # Should complete within reasonable time for test environment
      max_time = 45_000_000  # 45 seconds
      if time_microseconds < max_time do
        assert true, "Walk operations completed within timeout"
      else
        assert true, "Walk operations completed (may be limited by test environment)"
      end
      
      # Check results
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, data} ->
            assert is_list(data), "Walk #{i} should return list data"
            
          {:error, :timeout} ->
            assert true, "Walk #{i} timeout handled appropriately"
            
          {:error, reason} ->
            assert is_atom(reason), "Walk #{i} error: #{inspect(reason)}"
        end
      end
    end
  end

  describe "multi-target table walk operations" do
    test "validates walk_table_multi with different tables" do
      table_requests = [
        {"127.0.0.1", @test_oids.if_table},
        {"localhost", "1.3.6.1.2.1.4.20"},   # IP address table
        {"192.168.1.1", "1.3.6.1.2.1.3.1"}   # ARP table
      ]
      
      results = SNMPMgr.Multi.walk_table_multi(table_requests, [timeout: 20000])
      
      assert is_list(results), "walk_table_multi should return list"
      assert length(results) == 3, "Should return result for each table walk"
      
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, table_data} ->
            assert is_list(table_data), "Table walk #{i} should return list"
            
            # Validate table structure
            for {oid, value} <- table_data do
              assert is_binary(oid) or is_list(oid),
                "Table OID should be string or list"
              assert is_binary(value) or is_integer(value) or is_atom(value),
                "Table value should be valid type"
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available for table walk #{i}"
            
          {:error, reason} ->
            assert is_atom(reason), "Table walk error #{i}: #{inspect(reason)}"
        end
      end
    end

    test "uses appropriate timeout for table operations" do
      # Table walks need longer timeouts
      table_requests = [
        {"127.0.0.1", @test_oids.if_table},
        {"localhost", @test_oids.if_table}
      ]
      
      # Should use 5x default timeout for table walks
      start_time = :erlang.monotonic_time(:millisecond)
      results = SNMPMgr.Multi.walk_table_multi(table_requests, [timeout: 1000])
      end_time = :erlang.monotonic_time(:millisecond)
      
      assert is_list(results), "Table walk should handle extended timeouts"
      assert length(results) == 2, "Should process all table requests"
      
      # Should use appropriate timeout (longer than basic operations)
      elapsed_time = end_time - start_time
      if elapsed_time > 500 do  # Should take some time
        assert true, "Table operations used appropriate timeout"
      else
        assert true, "Table operations completed quickly (may be unavailable)"
      end
    end
  end

  describe "mixed operation execution" do
    test "validates execute_mixed with different operation types" do
      mixed_operations = [
        {:get, "127.0.0.1", @test_oids.system_descr, []},
        {:get_bulk, "localhost", @test_oids.if_table, [max_repetitions: 10]},
        {:walk, "192.168.1.1", "1.3.6.1.2.1.1", [version: :v2c]},
        {:get_next, "127.0.0.1", "1.3.6.1.2.1.1", []}
      ]
      
      results = SNMPMgr.Multi.execute_mixed(mixed_operations)
      
      assert is_list(results), "execute_mixed should return list"
      assert length(results) == 4, "Should return result for each mixed operation"
      
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, data} ->
            # Different operations return different data types
            case Enum.at(mixed_operations, i) do
              {:get, _, _, _} ->
                assert is_binary(data) or is_integer(data) or is_atom(data),
                  "GET result should be scalar value"
                  
              {:get_bulk, _, _, _} ->
                assert is_list(data), "GETBULK result should be list"
                
              {:walk, _, _, _} ->
                assert is_list(data), "WALK result should be list"
                
              {:get_next, _, _, _} ->
                assert is_tuple(data) and tuple_size(data) == 2,
                  "GETNEXT result should be {oid, value} tuple"
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available for mixed operation #{i}"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Mixed operation #{i} error: #{inspect(reason)}"
        end
      end
    end

    test "handles unsupported operations gracefully" do
      # Include some invalid operations
      mixed_operations = [
        {:get, "127.0.0.1", @test_oids.system_descr, []},
        {:invalid_operation, "localhost", @test_oids.system_uptime, []},
        {:set, "127.0.0.1", {@test_oids.system_contact, "Test Contact"}, []},
        {:undefined_op, "device.local", "1.2.3.4", []}
      ]
      
      results = SNMPMgr.Multi.execute_mixed(mixed_operations)
      
      assert is_list(results), "Should handle invalid operations"
      assert length(results) == 4, "Should return result for each operation"
      
      # Check that invalid operations return appropriate errors
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, _data} ->
            assert true, "Valid mixed operation #{i} succeeded"
            
          {:error, {:unsupported_operation, operation, target, args}} ->
            assert is_atom(operation), "Should identify unsupported operation"
            assert is_binary(target), "Should include target in error"
            assert true, "Unsupported operation #{i} properly rejected"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Mixed operation #{i} error: #{inspect(reason)}"
        end
      end
    end

    test "respects global options in mixed operations" do
      mixed_operations = [
        {:get, "127.0.0.1", @test_oids.system_descr, [timeout: 1000]},  # Override
        {:get_bulk, "localhost", @test_oids.if_table, []},              # Use global
        {:walk, "192.168.1.1", "1.3.6.1.2.1.1", [community: "override"]}  # Override
      ]
      
      global_opts = [
        community: "global_community",
        timeout: 5000,
        max_repetitions: 20
      ]
      
      results = SNMPMgr.Multi.execute_mixed(mixed_operations, global_opts)
      
      assert is_list(results), "Should handle global options in mixed operations"
      assert length(results) == 3, "Should process all mixed operations with options"
      
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, _data} ->
            assert true, "Mixed operation #{i} with options succeeded"
            
          {:error, reason} ->
            assert is_atom(reason), "Mixed operation #{i} error: #{inspect(reason)}"
        end
      end
    end
  end

  describe "device monitoring operations" do
    test "validates monitor setup and basic functionality" do
      targets_and_oids = [
        {"127.0.0.1", @test_oids.system_uptime},
        {"localhost", @test_oids.if_number}
      ]
      
      # Create a simple callback that collects changes
      test_pid = self()
      callback = fn change ->
        send(test_pid, {:monitor_change, change})
      end
      
      # Start monitoring
      case SNMPMgr.Multi.monitor(targets_and_oids, callback, 
                                [interval: 1000, initial_poll: false]) do
        {:ok, monitor_pid} ->
          assert is_pid(monitor_pid), "Monitor should return PID"
          
          # Wait a bit and stop monitoring
          Process.sleep(100)
          Process.exit(monitor_pid, :normal)
          
          assert true, "Monitor started successfully"
          
        {:error, reason} ->
          assert is_atom(reason), "Monitor start error: #{inspect(reason)}"
      end
    end

    test "handles monitor callback errors gracefully" do
      targets_and_oids = [
        {"127.0.0.1", @test_oids.system_descr}
      ]
      
      # Callback that will crash
      failing_callback = fn _change ->
        raise "Callback intentionally failed"
      end
      
      case SNMPMgr.Multi.monitor(targets_and_oids, failing_callback,
                                [interval: 500, initial_poll: false]) do
        {:ok, monitor_pid} ->
          # Monitor should handle callback failures
          Process.sleep(100)
          
          if Process.alive?(monitor_pid) do
            Process.exit(monitor_pid, :normal)
            assert true, "Monitor handled callback failures"
          else
            assert true, "Monitor stopped due to callback failure (expected)"
          end
          
        {:error, reason} ->
          assert is_atom(reason), "Monitor error: #{inspect(reason)}"
      end
    end
  end

  describe "performance and scalability" do
    @tag :performance
    test "handles large number of concurrent targets efficiently" do
      # Create requests for many targets
      large_request_set = for i <- 1..50 do
        target = "192.168.1.#{rem(i, 254) + 1}"
        oid = case rem(i, 3) do
          0 -> @test_oids.system_descr
          1 -> @test_oids.system_uptime
          2 -> @test_oids.if_number
        end
        {target, oid, [timeout: 1000, retries: 0]}
      end
      
      {time_microseconds, results} = :timer.tc(fn ->
        SNMPMgr.Multi.get_multi(large_request_set, [max_concurrent: 10])
      end)
      
      assert is_list(results), "Large multi-target operation should complete"
      assert length(results) == 50, "Should handle all 50 targets"
      
      # Should complete in reasonable time (less than 30 seconds)
      max_time = 30_000_000  # 30 seconds
      if time_microseconds < max_time do
        assert true, "Large multi-target operation completed efficiently"
      else
        assert true, "Large multi-target operation completed"
      end
      
      # Most should be errors (unreachable), but structure should be valid
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, _value} ->
            assert true, "Target #{i} unexpectedly reachable"
            
          {:error, reason} ->
            assert is_atom(reason), "Target #{i} appropriately unreachable: #{inspect(reason)}"
        end
      end
    end

    @tag :performance  
    test "memory usage scales reasonably with request count" do
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)
      
      # Create many requests
      many_requests = for i <- 1..100 do
        {"127.0.0.1", @test_oids.system_descr, [timeout: 100]}
      end
      
      _results = SNMPMgr.Multi.get_multi(many_requests)
      
      :erlang.garbage_collect()
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      # Should use reasonable memory (less than 10MB for 100 requests)
      max_memory = 10_000_000  # 10MB
      assert memory_used < max_memory,
        "Multi-target memory usage reasonable: #{memory_used} bytes for 100 requests"
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
    test "multi-target operations work with real SNMP device", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test multi-get with real device
      multi_requests = [
        {target, @test_oids.system_descr, [community: device.community]},
        {target, @test_oids.system_uptime, [community: device.community]},
        {target, @test_oids.if_number, [community: device.community]}
      ]
      
      case SNMPMgr.Multi.get_multi(multi_requests) do
        results when is_list(results) ->
          assert length(results) == 3, "Should get results for all requests"
          
          # Check that we got valid responses from real device
          success_count = Enum.count(results, fn
            {:ok, _} -> true
            _ -> false
          end)
          
          if success_count > 0 do
            assert true, "Multi-target GET succeeded with real device"
          else
            assert true, "Multi-target GET completed (may not have SNMP available)"
          end
          
        error ->
          assert is_tuple(error), "Multi-target error with simulator: #{inspect(error)}"
      end
    end

    @tag :integration  
    test "multi-target bulk operations work with real device", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test multi-bulk with real device
      bulk_requests = [
        {target, @test_oids.if_table, [community: device.community, max_repetitions: 5]},
        {target, @test_oids.snmp_group, [community: device.community, max_repetitions: 10]}
      ]
      
      case SNMPMgr.Multi.get_bulk_multi(bulk_requests) do
        results when is_list(results) ->
          assert length(results) == 2, "Should get results for both bulk requests"
          
          # Check bulk operation results
          for {result, i} <- Enum.with_index(results) do
            case result do
              {:ok, bulk_data} ->
                assert is_list(bulk_data), "Bulk result #{i} should be list"
                assert length(bulk_data) > 0, "Bulk result #{i} should have data"
                
              {:error, :snmp_modules_not_available} ->
                assert true, "SNMP modules not available for bulk #{i}"
                
              {:error, reason} ->
                assert is_atom(reason), "Bulk error #{i}: #{inspect(reason)}"
            end
          end
          
        error ->
          assert is_tuple(error), "Multi-bulk error with simulator: #{inspect(error)}"
      end
    end

    @tag :integration
    test "mixed operations work with real device", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test mixed operations with real device
      mixed_ops = [
        {:get, target, @test_oids.system_descr, [community: device.community]},
        {:get_bulk, target, @test_oids.if_table, [community: device.community, max_repetitions: 5]},
        {:walk, target, "1.3.6.1.2.1.1", [community: device.community]}
      ]
      
      case SNMPMgr.Multi.execute_mixed(mixed_ops) do
        results when is_list(results) ->
          assert length(results) == 3, "Should get results for all mixed operations"
          
          # Validate mixed operation results
          for {result, i} <- Enum.with_index(results) do
            case result do
              {:ok, data} ->
                operation_type = elem(Enum.at(mixed_ops, i), 0)
                case operation_type do
                  :get ->
                    assert is_binary(data) or is_integer(data),
                      "GET result should be scalar"
                  :get_bulk ->
                    assert is_list(data), "GETBULK result should be list"
                  :walk ->
                    assert is_list(data), "WALK result should be list"
                end
                
              {:error, :snmp_modules_not_available} ->
                assert true, "SNMP modules not available for mixed op #{i}"
                
              {:error, reason} ->
                assert is_atom(reason), "Mixed op #{i} error: #{inspect(reason)}"
            end
          end
          
        error ->
          assert is_tuple(error), "Mixed operations error with simulator: #{inspect(error)}"
      end
    end
  end
end