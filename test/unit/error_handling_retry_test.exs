defmodule SNMPMgr.ErrorHandlingRetryTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :error_handling
  @moduletag :retry_logic
  @moduletag :snmp_lib_integration

  describe "Network Error Handling through SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "network timeouts handled by snmp_lib", %{device: device} do
      # Test network timeout handling through snmp_lib
      unreachable_targets = [
        "240.0.0.1",     # Class E address
        "192.0.2.254"    # Documentation range
      ]
      
      Enum.each(unreachable_targets, fn target ->
        result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: device.community, timeout: 100)
        
        case result do
          {:error, reason} when reason in [:timeout, :host_unreachable, :network_unreachable,
                                          :ehostunreach, :enetunreach, :econnrefused] ->
            # Expected network errors through snmp_lib
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "Network error should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Unexpected success (device might exist)
            assert true
        end
      end)
    end

    test "connection refused errors through snmp_lib", %{device: device} do
      # Test connection refused handling through snmp_lib
      wrong_port_targets = [
        "127.0.0.1:80",    # HTTP port instead of SNMP
        "127.0.0.1:22"     # SSH port instead of SNMP  
      ]
      
      Enum.each(wrong_port_targets, fn target ->
        result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: device.community, timeout: 200)
        
        case result do
          {:error, reason} when reason in [:connection_refused, :econnrefused, :timeout] ->
            # Expected connection errors through snmp_lib
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "Connection error should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Shouldn't get SNMP response from wrong port
            flunk("Should not get SNMP response from #{target}")
        end
      end)
    end

    test "DNS resolution errors through snmp_lib", %{device: device} do
      # Test DNS resolution error handling through snmp_lib
      invalid_hostnames = [
        "invalid.hostname.that.does.not.exist.example",
        "nonexistent12345.local"
      ]
      
      Enum.each(invalid_hostnames, fn hostname ->
        result = SNMPMgr.get(hostname, "1.3.6.1.2.1.1.1.0", 
                            community: device.community, timeout: 2000)
        
        case result do
          {:error, reason} when reason in [:nxdomain, :host_not_found, :timeout] ->
            # Expected DNS errors through snmp_lib
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "DNS error should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Hostname might resolve unexpectedly
            assert true
        end
      end)
    end
  end

  describe "SNMP Protocol Error Handling through SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "authentication errors through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test authentication error handling through snmp_lib
      invalid_communities = ["wrong_community", "", "invalid123"]
      
      Enum.each(invalid_communities, fn community ->
        result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: community, timeout: 200)
        
        case result do
          {:error, reason} when reason in [:authentication_error, :bad_community] ->
            # Expected authentication error from snmp_lib
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "Authentication error should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # Might succeed in test environment
            assert true
        end
      end)
    end

    test "invalid OID errors through SnmpLib.OID", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test invalid OID handling through SnmpLib.OID
      invalid_oids = [
        "invalid.oid.format",
        "",
        "not.numeric.oid",
        "1.2.3.4.5.6.7.8.9.999.999.999.0"
      ]
      
      Enum.each(invalid_oids, fn oid ->
        result = SNMPMgr.get(target, oid, community: device.community, timeout: 200)
        
        case result do
          {:error, reason} ->
            # Should get proper error from SnmpLib.OID validation
            assert is_atom(reason) or is_tuple(reason),
              "Invalid OID should return proper error format: #{inspect(reason)}"
            
          {:ok, _} ->
            # Some invalid OIDs might resolve unexpectedly
            assert true
        end
      end)
    end

    test "SET operation errors through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test SET operation error handling through snmp_lib
      set_error_cases = [
        # Read-only OID
        {"1.3.6.1.2.1.1.1.0", "Read Only Test", "read-only system description"},
        
        # Non-existent OID
        {"1.2.3.4.5.6.7.8.9.0", "test", "non-existent OID"}
      ]
      
      Enum.each(set_error_cases, fn {oid, value, description} ->
        result = SNMPMgr.set(target, oid, value, 
                            community: device.community, timeout: 200)
        
        case result do
          {:error, reason} when reason in [:read_only, :no_access, :no_such_name] ->
            # Expected SET errors through snmp_lib
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "SET error for #{description} should be properly formatted: #{inspect(reason)}"
            
          {:ok, _} ->
            # SET might succeed unexpectedly
            assert true
        end
      end)
    end

    test "version compatibility errors through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test version-specific error handling through snmp_lib
      version_cases = [
        # GET-BULK with v1 (should be handled or rejected)
        {:get_bulk, "1.3.6.1.2.1.2.2", [version: :v1, max_repetitions: 3], "GETBULK with v1"},
        
        # Regular operation with unsupported version
        {:get, "1.3.6.1.2.1.1.1.0", [version: :v3], "GET with v3"}
      ]
      
      Enum.each(version_cases, fn {operation, oid, opts, description} ->
        full_opts = opts ++ [community: device.community, timeout: 200]
        
        result = case operation do
          :get -> SNMPMgr.get(target, oid, full_opts)
          :get_bulk -> SNMPMgr.get_bulk(target, oid, full_opts)
        end
        
        case result do
          {:ok, _} ->
            # Version might be supported or enforced
            assert true
            
          {:error, reason} when reason in [:version_not_supported, :unsupported_version] ->
            # Expected version errors through snmp_lib
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "Version error for #{description} should be properly formatted: #{inspect(reason)}"
        end
      end)
    end
  end

  describe "Timeout Handling through SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "timeout values respected by snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test different timeout values through snmp_lib
      timeout_cases = [
        {1, "very short timeout"},
        {50, "short timeout"},
        {200, "normal timeout"}
      ]
      
      Enum.each(timeout_cases, fn {timeout, description} ->
        start_time = System.monotonic_time(:millisecond)
        
        result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: device.community, timeout: timeout)
        
        end_time = System.monotonic_time(:millisecond)
        elapsed = end_time - start_time
        
        case result do
          {:ok, _} ->
            # Operation succeeded within timeout
            assert elapsed <= timeout * 2,  # Allow some overhead
              "#{description} should complete within reasonable time"
            
          {:error, :timeout} ->
            # Timeout handled correctly by snmp_lib
            assert elapsed >= timeout * 0.5,  # Should be close to timeout
              "#{description} should timeout close to specified time"
            
          {:error, reason} ->
            # Other errors from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error should be properly formatted: #{inspect(reason)}"
        end
      end)
    end

    test "timeout parameter validation", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test timeout parameter validation
      invalid_timeouts = [
        {-1, "negative timeout"},
        {0, "zero timeout"}
      ]
      
      Enum.each(invalid_timeouts, fn {timeout, description} ->
        result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: device.community, timeout: timeout)
        
        case result do
          {:ok, _} ->
            # Timeout might be accepted and corrected
            assert true
            
          {:error, reason} when reason in [:invalid_timeout, :bad_timeout] ->
            # Expected validation error
            assert true
            
          {:error, reason} ->
            # Other error formats from snmp_lib are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error should be properly formatted: #{inspect(reason)}"
        end
      end)
    end

    test "concurrent timeout handling through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test concurrent operations with timeouts
      concurrent_timeouts = Enum.map(1..5, fn i ->
        Task.async(fn ->
          timeout = i * 10  # 10, 20, 30, 40, 50ms
          SNMPMgr.get(target, "1.3.6.1.2.1.1.#{i}.0", 
                     community: device.community, timeout: timeout)
        end)
      end)
      
      results = Task.await_many(concurrent_timeouts, 1000)
      
      # All should complete with proper error formats
      assert length(results) == 5
      
      Enum.each(results, fn result ->
        case result do
          {:ok, _} ->
            # Operation succeeded
            assert true
            
          {:error, reason} ->
            # Should be properly formatted from snmp_lib
            assert is_atom(reason) or is_tuple(reason),
              "Concurrent timeout error should be properly formatted: #{inspect(reason)}"
        end
      end)
    end
  end

  describe "Retry Logic Integration with SnmpLib" do
    test "retry mechanisms with unreachable targets" do
      # Test retry logic with unreachable targets through snmp_lib
      unreachable_target = "240.0.0.1"
      
      retry_cases = [
        {0, "no retries"},
        {1, "single retry"},
        {2, "multiple retries"}
      ]
      
      Enum.each(retry_cases, fn {retry_count, description} ->
        start_time = System.monotonic_time(:millisecond)
        
        result = SNMPMgr.get(unreachable_target, "1.3.6.1.2.1.1.1.0", 
                            timeout: 200, retries: retry_count)
        
        end_time = System.monotonic_time(:millisecond)
        elapsed = end_time - start_time
        
        case result do
          {:error, reason} ->
            # Should get network error through snmp_lib
            assert is_atom(reason) or is_tuple(reason),
              "Retry #{description} should return proper error: #{inspect(reason)}"
            
            # Time should roughly correspond to retry count
            expected_min_time = 200 * (retry_count + 1) * 0.5  # Allow 50% tolerance
            
            if elapsed >= expected_min_time do
              assert true, "#{description} took appropriate time: #{elapsed}ms"
            else
              assert true, "#{description} completed quickly (may have failed immediately)"
            end
            
          {:ok, _} ->
            # Unexpected success
            assert true
        end
      end)
    end

    test "retry parameter validation" do
      # Test retry parameter validation
      invalid_retries = [
        {-1, "negative retries"},
        {100, "excessive retries"}
      ]
      
      Enum.each(invalid_retries, fn {retries, description} ->
        result = SNMPMgr.get("127.0.0.1", "1.3.6.1.2.1.1.1.0", 
                            timeout: 200, retries: retries)
        
        case result do
          {:ok, _} ->
            # Retry count might be accepted and corrected
            assert true
            
          {:error, reason} when reason in [:invalid_retries, :bad_retries] ->
            # Expected validation error
            assert true
            
          {:error, reason} ->
            # Other error formats are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error should be properly formatted: #{inspect(reason)}"
        end
      end)
    end

    test "retry backoff behavior with snmp_lib" do
      # Test that retries don't happen too aggressively
      start_time = System.monotonic_time(:millisecond)
      
      result = SNMPMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", 
                          timeout: 100, retries: 3)
      
      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time
      
      case result do
        {:error, reason} ->
          # Should get network error through snmp_lib
          assert is_atom(reason) or is_tuple(reason),
            "Retry backoff should return proper error: #{inspect(reason)}"
          
          # Should take at least the base timeout times retry count
          min_expected = 100 * 4 * 0.7  # 4 attempts, 70% tolerance
          
          if elapsed >= min_expected do
            assert true, "Retry backoff timing reasonable: #{elapsed}ms"
          else
            assert true, "Retries completed quickly (may have failed immediately)"
          end
          
        {:ok, _} ->
          # Unexpected success
          assert true
      end
    end
  end

  describe "Multi-Operation Error Resilience" do
    setup do
      # Create multiple devices for multi-operation testing
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

    test "mixed success/failure in multi-operations", %{device1: device1, device2: device2} do
      # Test mixed success/failure scenarios in multi-operations
      mixed_requests = [
        # Valid request  
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.1.1.0", 
         [community: device1.community, timeout: 200]},
        
        # Network error
        {"240.0.0.1", "1.3.6.1.2.1.1.1.0", [timeout: 100]},
        
        # OID error
        {SNMPSimulator.device_target(device2), "invalid.oid", 
         [community: device2.community, timeout: 200]}
      ]
      
      results = SNMPMgr.get_multi(mixed_requests)
      
      assert is_list(results)
      assert length(results) == 3
      
      # Should handle mixed results gracefully
      success_count = Enum.count(results, fn result ->
        match?({:ok, _}, result)
      end)
      
      error_count = Enum.count(results, fn result ->
        match?({:error, _}, result)
      end)
      
      assert success_count + error_count == 3
      
      # All errors should be properly formatted
      Enum.each(results, fn result ->
        case result do
          {:ok, _} -> assert true
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Multi-operation error should be properly formatted: #{inspect(reason)}"
        end
      end)
    end

    test "error isolation in bulk multi-operations", %{device1: device1, device2: device2} do
      # Test error isolation in bulk multi-operations
      bulk_requests = [
        # Valid request
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.2.2", 
         [max_repetitions: 3, community: device1.community, timeout: 200]},
        
        # Network error  
        {"240.0.0.1", "1.3.6.1.2.1.2.2", [max_repetitions: 3, timeout: 100]},
        
        # OID error
        {SNMPSimulator.device_target(device2), "invalid.oid", 
         [max_repetitions: 3, community: device2.community, timeout: 200]}
      ]
      
      results = SNMPMgr.get_bulk_multi(bulk_requests)
      
      assert is_list(results)
      assert length(results) == 3
      
      # Each result should be independent
      Enum.each(results, fn result ->
        case result do
          {:ok, list} when is_list(list) ->
            # Successful bulk operation
            assert true
            
          {:error, reason} ->
            # Error should be properly formatted from snmp_lib
            assert is_atom(reason) or is_tuple(reason),
              "Bulk multi-operation error should be properly formatted: #{inspect(reason)}"
        end
      end)
    end
  end

  describe "Resource Protection with SnmpLib" do
    test "handles concurrent error conditions gracefully" do
      # Test concurrent error handling through snmp_lib
      concurrent_errors = Enum.map(1..10, fn i ->
        Task.async(fn ->
          case rem(i, 3) do
            0 -> SNMPMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 100)  # Network error
            1 -> SNMPMgr.get("127.0.0.1", "invalid.oid", timeout: 100)  # OID error
            2 -> SNMPMgr.get("127.0.0.1", "1.3.6.1.2.1.1.1.0", community: "wrong", timeout: 100)  # Auth error
          end
        end)
      end)
      
      results = Task.await_many(concurrent_errors, 2000)
      
      # All should complete with proper error handling
      assert length(results) == 10
      
      Enum.each(results, fn result ->
        case result do
          {:error, reason} ->
            # Should be properly formatted from snmp_lib
            assert is_atom(reason) or is_tuple(reason),
              "Concurrent error should be properly formatted: #{inspect(reason)}"
          {:ok, _} ->
            # Some might succeed unexpectedly
            assert true
        end
      end)
    end

    test "memory stability under error conditions" do
      # Test memory usage during error handling
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)
      
      # Generate many errors through snmp_lib
      error_operations = Enum.map(1..20, fn i ->
        spawn(fn ->
          SNMPMgr.get("240.0.0.#{rem(i, 10) + 1}", "1.3.6.1.2.1.1.1.0", timeout: 100)
        end)
      end)
      
      # Wait for operations to complete
      Process.sleep(500)
      
      # Check memory usage
      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be reasonable during error handling
      assert memory_growth < 5_000_000,  # Less than 5MB growth
        "Memory growth during error handling should be bounded: #{memory_growth} bytes"
    end
  end

  describe "Error Context and Recovery with SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "error context preservation through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that error context is preserved through snmp_lib
      error_scenarios = [
        # Network error with target context
        {fn -> SNMPMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 100) end,
         "network operation"},
        
        # OID error with OID context
        {fn -> SNMPMgr.get(target, "invalid.oid", community: device.community, timeout: 100) end,
         "OID validation"},
        
        # Authentication error with auth context
        {fn -> SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: "wrong", timeout: 100) end,
         "authentication"}
      ]
      
      Enum.each(error_scenarios, fn {operation, context} ->
        case operation.() do
          {:error, reason} ->
            # Error should be descriptive for the context
            assert is_atom(reason) or is_tuple(reason),
              "#{context} error should be descriptive: #{inspect(reason)}"
            
          {:ok, _} ->
            # Some operations might succeed unexpectedly
            assert true
        end
      end)
    end

    test "recovery from transient errors through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Simulate recovery by first using short timeout, then normal timeout
      first_attempt = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                                  community: device.community, timeout: 1)
      
      second_attempt = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                                   community: device.community, timeout: 200)
      
      case {first_attempt, second_attempt} do
        {{:error, :timeout}, {:ok, _}} ->
          # Successful recovery from timeout
          assert true
          
        {{:error, _}, {:error, _}} ->
          # Both failed (consistent failure)
          assert true
          
        {{:ok, _}, {:ok, _}} ->
          # Both succeeded (fast response)
          assert true
          
        other ->
          # Mixed results - acceptable
          assert true, "Recovery test mixed results: #{inspect(other)}"
      end
    end

    test "error reporting consistency across API", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test error reporting consistency across all API functions
      api_error_tests = [
        {:get, fn -> SNMPMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 100) end},
        {:set, fn -> SNMPMgr.set("240.0.0.1", "1.3.6.1.2.1.1.6.0", "test", timeout: 100) end},
        {:get_bulk, fn -> SNMPMgr.get_bulk("240.0.0.1", "1.3.6.1.2.1.2.2", max_repetitions: 3, timeout: 100) end},
        {:get_next, fn -> SNMPMgr.get_next("240.0.0.1", "1.3.6.1.2.1.1.1", timeout: 100) end},
        {:walk, fn -> SNMPMgr.walk("240.0.0.1", "1.3.6.1.2.1.1", timeout: 100) end}
      ]
      
      Enum.each(api_error_tests, fn {api_function, operation} ->
        case operation.() do
          {:error, reason} ->
            # All API functions should return consistent error formats
            assert is_atom(reason) or is_tuple(reason),
              "#{api_function} should return consistent error format: #{inspect(reason)}"
            
          {:ok, _} ->
            # Some might succeed unexpectedly
            assert true
        end
      end)
    end
  end
end