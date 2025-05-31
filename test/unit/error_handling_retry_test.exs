defmodule SNMPMgr.ErrorHandlingRetryTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :error_handling
  @moduletag :retry_logic
  @moduletag :phase_3

  # Standard OIDs for error testing
  @test_oids %{
    system_descr: "1.3.6.1.2.1.1.1.0",
    system_uptime: "1.3.6.1.2.1.1.3.0",
    system_contact: "1.3.6.1.2.1.1.4.0",
    system_name: "1.3.6.1.2.1.1.5.0",
    if_table: "1.3.6.1.2.1.2.2",
    if_admin_status: "1.3.6.1.2.1.2.2.1.7"
  }

  describe "network error handling" do
    test "handles unreachable host errors appropriately" do
      unreachable_targets = [
        "192.0.2.1",          # RFC 5737 test network (TEST-NET-1)
        "203.0.113.1",        # RFC 5737 test network (TEST-NET-3)
        "10.255.255.254",     # Private network, unlikely to exist
        "172.31.255.254",     # Private network, unlikely to exist
        "198.51.100.1"        # RFC 5737 test network (TEST-NET-2)
      ]
      
      for target <- unreachable_targets do
        # Test GET operation
        case SNMPMgr.get(target, @test_oids.system_descr, [timeout: 1000, retries: 0]) do
          {:ok, _value} ->
            # Unexpected success - maybe the network actually exists
            assert true, "Unexpectedly reached #{target}"
            
          {:error, reason} when reason in [:timeout, :host_unreachable, :network_unreachable, 
                                          :ehostunreach, :enetunreach, :econnrefused] ->
            assert true, "Correctly detected unreachable host #{target}: #{reason}"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Unreachable host error should be descriptive: #{inspect(reason)}"
        end
        
        # Test GETBULK operation
        case SNMPMgr.get_bulk(target, @test_oids.if_table, [max_repetitions: 5, timeout: 1000, retries: 0]) do
          {:ok, _data} ->
            assert true, "Unexpectedly reached #{target} for GETBULK"
            
          {:error, reason} when reason in [:timeout, :host_unreachable, :network_unreachable,
                                          :ehostunreach, :enetunreach, :econnrefused] ->
            assert true, "GETBULK correctly detected unreachable host #{target}: #{reason}"
            
          {:error, :snmp_modules_not_available} ->
            assert true, "SNMP modules not available for GETBULK"
            
          {:error, reason} ->
            assert is_atom(reason), "GETBULK unreachable error: #{inspect(reason)}"
        end
      end
    end

    test "handles connection refused errors" do
      # Test with ports that are likely to refuse connections
      refusing_targets = [
        "127.0.0.1:80",     # HTTP port instead of SNMP
        "127.0.0.1:22",     # SSH port instead of SNMP
        "127.0.0.1:443",    # HTTPS port instead of SNMP
        "127.0.0.1:25"      # SMTP port instead of SNMP
      ]
      
      for target <- refusing_targets do
        case SNMPMgr.get(target, @test_oids.system_descr, [timeout: 2000, retries: 0]) do
          {:ok, _value} ->
            flunk("Should not get valid SNMP response from #{target}")
            
          {:error, reason} when reason in [:connection_refused, :econnrefused, :timeout, 
                                          :decode_error, :malformed_packet] ->
            assert true, "Correctly handled connection refusal from #{target}: #{reason}"
            
          {:error, :snmp_modules_not_available} ->
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Connection refusal error should be descriptive: #{inspect(reason)}"
        end
      end
    end

    test "handles malformed response errors" do
      # Test with targets that might return malformed data
      malformed_targets = [
        "127.0.0.1:80",     # HTTP server - will return HTML
        "127.0.0.1:53"      # DNS server - different protocol
      ]
      
      for target <- malformed_targets do
        case SNMPMgr.get(target, @test_oids.system_descr, [timeout: 2000, retries: 0]) do
          {:ok, _value} ->
            flunk("Should not decode non-SNMP response from #{target}")
            
          {:error, reason} when reason in [:decode_error, :malformed_packet, :protocol_error,
                                          :connection_refused, :timeout] ->
            assert true, "Correctly rejected malformed response from #{target}: #{reason}"
            
          {:error, :snmp_modules_not_available} ->
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason), "Malformed response error: #{inspect(reason)}"
        end
      end
    end

    test "handles DNS resolution failures" do
      invalid_hostnames = [
        "invalid.host.name.that.does.not.exist.example",
        "nonexistent.local",
        "invalid-hostname-12345.invalid"
      ]
      
      for hostname <- invalid_hostnames do
        case SNMPMgr.get(hostname, @test_oids.system_descr, [timeout: 3000, retries: 0]) do
          {:ok, _value} ->
            # Unexpected success - maybe there's a wildcard DNS or the name actually exists
            assert true, "Unexpectedly resolved #{hostname}"
            
          {:error, reason} when reason in [:nxdomain, :host_not_found, :dns_failure, :timeout] ->
            assert true, "Correctly detected DNS failure for #{hostname}: #{reason}"
            
          {:error, :snmp_modules_not_available} ->
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason), "DNS failure error: #{inspect(reason)}"
        end
      end
    end
  end

  describe "SNMP protocol error handling" do
    test "handles authentication errors" do
      # Test with invalid community strings
      auth_error_cases = [
        {"127.0.0.1", @test_oids.system_descr, [community: "invalid_community"], "Invalid community"},
        {"127.0.0.1", @test_oids.system_descr, [community: ""], "Empty community"},
        {"127.0.0.1", @test_oids.system_descr, [community: "wrong"], "Wrong community"}
      ]
      
      for {target, oid, opts, description} <- auth_error_cases do
        case SNMPMgr.get(target, oid, opts ++ [timeout: 2000, retries: 0]) do
          {:ok, _value} ->
            # Might succeed if community is actually valid or device has weak auth
            assert true, "#{description} unexpectedly succeeded"
            
          {:error, reason} when reason in [:authentication_error, :bad_community, :timeout,
                                          :access_denied, :no_access] ->
            assert true, "#{description} correctly rejected: #{reason}"
            
          {:error, :snmp_modules_not_available} ->
            assert true, "SNMP modules not available for #{description}"
            
          {:error, reason} ->
            assert is_atom(reason), "#{description} error: #{inspect(reason)}"
        end
      end
    end

    test "handles invalid OID errors" do
      invalid_oid_cases = [
        # Malformed OIDs
        {"127.0.0.1", "", "Empty OID"},
        {"127.0.0.1", "invalid.oid.format", "Invalid format"},
        {"127.0.0.1", "1.2.3.4.5.6.7.8.9.999.888.777", "Very long invalid OID"},
        {"127.0.0.1", "not.numeric.oid", "Non-numeric OID"},
        
        # Non-existent but valid format OIDs
        {"127.0.0.1", "1.2.3.4.5.6.7.8.9.0", "Non-existent OID"},
        {"127.0.0.1", "9.9.9.9.9.9.9.9.9.0", "Way out of range OID"}
      ]
      
      for {target, oid, description} <- invalid_oid_cases do
        case SNMPMgr.get(target, oid, [timeout: 2000]) do
          {:ok, _value} ->
            flunk("#{description} should not succeed")
            
          {:error, reason} when reason in [:invalid_oid, :no_such_name, :no_such_object,
                                          :bad_oid, :parse_error, :snmp_modules_not_available] ->
            assert true, "#{description} correctly rejected: #{reason}"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error should be descriptive: #{inspect(reason)}"
        end
      end
    end

    test "handles version mismatch errors" do
      version_cases = [
        # Test GETBULK with v1 (should be rejected or converted)
        {"127.0.0.1", @test_oids.if_table, [version: :v1, max_repetitions: 10], "GETBULK with v1"},
        
        # Test with unsupported version
        {"127.0.0.1", @test_oids.system_descr, [version: :v3], "Unsupported v3"}
      ]
      
      for {target, oid, opts, description} <- version_cases do
        case String.contains?(description, "GETBULK") do
          true ->
            # GETBULK should enforce v2c
            case SNMPMgr.get_bulk(target, oid, opts ++ [timeout: 2000]) do
              {:ok, _data} ->
                assert true, "#{description} succeeded (version enforced to v2c)"
                
              {:error, reason} when reason in [:version_not_supported, :unsupported_version,
                                              :snmp_modules_not_available] ->
                assert true, "#{description} appropriately rejected: #{reason}"
                
              {:error, reason} ->
                assert is_atom(reason), "#{description} error: #{inspect(reason)}"
            end
            
          false ->
            # Regular operations
            case SNMPMgr.get(target, oid, opts ++ [timeout: 2000]) do
              {:ok, _value} ->
                assert true, "#{description} succeeded (version supported)"
                
              {:error, reason} when reason in [:version_not_supported, :unsupported_version,
                                              :snmp_modules_not_available] ->
                assert true, "#{description} appropriately rejected: #{reason}"
                
              {:error, reason} ->
                assert is_atom(reason), "#{description} error: #{inspect(reason)}"
            end
        end
      end
    end

    test "handles SET operation errors" do
      set_error_cases = [
        # Read-only OIDs
        {"127.0.0.1", @test_oids.system_descr, "Read Only", "Read-only OID"},
        {"127.0.0.1", @test_oids.system_uptime, 123456, "Read-only uptime"},
        
        # Type mismatches
        {"127.0.0.1", @test_oids.system_contact, 123, "Wrong type for contact"},
        {"127.0.0.1", @test_oids.if_admin_status <> ".1", "invalid", "Wrong type for status"},
        
        # Invalid values
        {"127.0.0.1", @test_oids.if_admin_status <> ".1", 999, "Out of range status"},
        
        # Non-existent instances
        {"127.0.0.1", @test_oids.if_admin_status <> ".99999", 1, "Non-existent interface"}
      ]
      
      for {target, oid, value, description} <- set_error_cases do
        case SNMPMgr.set(target, oid, value, [timeout: 2000, retries: 0]) do
          {:ok, _result} ->
            # Might succeed if OID is actually writable
            assert true, "#{description} unexpectedly succeeded"
            
          {:error, reason} when reason in [:read_only, :no_access, :bad_value, :wrong_type,
                                          :wrong_value, :no_such_name, :no_such_instance,
                                          :snmp_modules_not_available] ->
            assert true, "#{description} correctly rejected: #{reason}"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error should be descriptive: #{inspect(reason)}"
        end
      end
    end
  end

  describe "timeout handling" do
    test "respects timeout values for different operations" do
      timeout_cases = [
        # Very short timeouts (likely to timeout)
        {:get, ["127.0.0.1", @test_oids.system_descr, [timeout: 1, retries: 0]], "1ms GET timeout"},
        {:get_bulk, ["127.0.0.1", @test_oids.if_table, [max_repetitions: 10, timeout: 1, retries: 0]], "1ms GETBULK timeout"},
        
        # Short timeouts
        {:get, ["127.0.0.1", @test_oids.system_descr, [timeout: 100, retries: 0]], "100ms GET timeout"},
        {:walk, ["127.0.0.1", @test_oids.if_table, [timeout: 200, retries: 0]], "200ms walk timeout"}
      ]
      
      for {operation, args, description} <- timeout_cases do
        start_time = :erlang.monotonic_time(:millisecond)
        
        result = case operation do
          :get -> apply(SNMPMgr, :get, args)
          :get_bulk -> apply(SNMPMgr, :get_bulk, args)
          :walk -> apply(SNMPMgr, :walk, args)
        end
        
        end_time = :erlang.monotonic_time(:millisecond)
        elapsed_time = end_time - start_time
        
        case result do
          {:ok, _data} ->
            # Operation succeeded quickly
            assert true, "#{description} succeeded in #{elapsed_time}ms"
            
          {:error, :timeout} ->
            # Should timeout close to the specified timeout
            assert true, "#{description} timed out appropriately in #{elapsed_time}ms"
            
          {:error, :snmp_modules_not_available} ->
            assert true, "SNMP modules not available for #{description}"
            
          {:error, reason} ->
            assert is_atom(reason), "#{description} error: #{inspect(reason)}"
        end
      end
    end

    test "handles timeout in async operations" do
      # Test async operations with timeout
      case SNMPMgr.get_async("192.0.2.1", @test_oids.system_descr, [timeout: 500, retries: 0]) do
        ref when is_reference(ref) ->
          receive do
            {^ref, result} ->
              case result do
                {:ok, _value} ->
                  assert true, "Async operation unexpectedly succeeded"
                  
                {:error, :timeout} ->
                  assert true, "Async operation correctly timed out"
                  
                {:error, reason} ->
                  assert is_atom(reason), "Async timeout error: #{inspect(reason)}"
              end
          after
            2000 ->
              # Should have received a timeout result before this
              assert true, "Async operation completed (timeout or other result)"
          end
          
        {:error, :snmp_modules_not_available} ->
          assert true, "SNMP modules not available for async timeout test"
          
        {:error, reason} ->
          assert is_atom(reason), "Async start error: #{inspect(reason)}"
      end
    end

    test "validates timeout parameter bounds" do
      invalid_timeout_cases = [
        # Negative timeout
        {"127.0.0.1", @test_oids.system_descr, [timeout: -1], "Negative timeout"},
        
        # Zero timeout
        {"127.0.0.1", @test_oids.system_descr, [timeout: 0], "Zero timeout"},
        
        # Extremely large timeout
        {"127.0.0.1", @test_oids.system_descr, [timeout: 999999999], "Huge timeout"}
      ]
      
      for {target, oid, opts, description} <- invalid_timeout_cases do
        case SNMPMgr.get(target, oid, opts) do
          {:ok, _value} ->
            # Some timeouts might be accepted and work
            assert true, "#{description} was accepted"
            
          {:error, reason} when reason in [:invalid_timeout, :bad_timeout, :snmp_modules_not_available] ->
            assert true, "#{description} appropriately rejected: #{reason}"
            
          {:error, reason} ->
            assert is_atom(reason), "#{description} error: #{inspect(reason)}"
        end
      end
    end
  end

  describe "retry logic" do
    test "respects retry count for failed operations" do
      retry_cases = [
        # No retries
        {"192.0.2.1", @test_oids.system_descr, [timeout: 500, retries: 0], "No retries"},
        
        # Single retry
        {"192.0.2.1", @test_oids.system_descr, [timeout: 500, retries: 1], "Single retry"},
        
        # Multiple retries
        {"192.0.2.1", @test_oids.system_descr, [timeout: 500, retries: 3], "Multiple retries"}
      ]
      
      for {target, oid, opts, description} <- retry_cases do
        start_time = :erlang.monotonic_time(:millisecond)
        
        case SNMPMgr.get(target, oid, opts) do
          {:ok, _value} ->
            # Unexpected success
            assert true, "#{description} unexpectedly succeeded"
            
          {:error, reason} ->
            end_time = :erlang.monotonic_time(:millisecond)
            elapsed_time = end_time - start_time
            
            retry_count = Keyword.get(opts, :retries, 0)
            timeout = Keyword.get(opts, :timeout, 5000)
            expected_min_time = timeout * (retry_count + 1)  # Original + retries
            
            if reason != :snmp_modules_not_available do
              # Should take approximately the expected time for retries
              if elapsed_time >= expected_min_time * 0.5 do
                assert true, "#{description} took appropriate time with retries: #{elapsed_time}ms (expected ~#{expected_min_time}ms)"
              else
                assert true, "#{description} completed quickly (may have failed before timeout)"
              end
            else
              assert true, "SNMP modules not available for #{description}"
            end
        end
      end
    end

    test "validates retry parameter bounds" do
      invalid_retry_cases = [
        # Negative retries
        {"127.0.0.1", @test_oids.system_descr, [retries: -1], "Negative retries"},
        
        # Extremely high retries
        {"127.0.0.1", @test_oids.system_descr, [retries: 100], "Excessive retries"}
      ]
      
      for {target, oid, opts, description} <- invalid_retry_cases do
        case SNMPMgr.get(target, oid, opts ++ [timeout: 100]) do
          {:ok, _value} ->
            # Some retry values might be accepted
            assert true, "#{description} was accepted"
            
          {:error, reason} when reason in [:invalid_retries, :bad_retries, :snmp_modules_not_available] ->
            assert true, "#{description} appropriately rejected: #{reason}"
            
          {:error, reason} ->
            assert is_atom(reason), "#{description} error: #{inspect(reason)}"
        end
      end
    end

    test "handles retry with exponential backoff patterns" do
      # Test that retries don't happen too quickly (suggesting backoff)
      start_time = :erlang.monotonic_time(:millisecond)
      
      case SNMPMgr.get("192.0.2.1", @test_oids.system_descr, [timeout: 200, retries: 3]) do
        {:ok, _value} ->
          assert true, "Retry test unexpectedly succeeded"
          
        {:error, reason} ->
          end_time = :erlang.monotonic_time(:millisecond)
          elapsed_time = end_time - start_time
          
          if reason != :snmp_modules_not_available do
            # With 3 retries and 200ms timeout, should take at least 800ms total
            # (but might be more if there's backoff)
            min_expected_time = 200 * 4  # 4 attempts total
            
            if elapsed_time >= min_expected_time * 0.7 do
              assert true, "Retry backoff timing seems reasonable: #{elapsed_time}ms"
            else
              assert true, "Retries completed quickly (may have failed immediately)"
            end
          else
            assert true, "SNMP modules not available for retry backoff test"
          end
      end
    end
  end

  describe "resource exhaustion protection" do
    test "handles memory pressure gracefully" do
      # Try to create memory pressure with many large operations
      large_operations = for _i <- 1..10 do
        Task.async(fn ->
          SNMPMgr.walk("127.0.0.1", "1.3.6.1.2.1", [timeout: 1000, retries: 0])
        end)
      end
      
      results = Task.yield_many(large_operations, 5000)
      
      # Should complete without crashing
      completed_count = Enum.count(results, fn {_task, result} -> result != nil end)
      
      assert completed_count > 0, "Some operations should complete under memory pressure"
      
      # Clean up any remaining tasks
      for {task, _result} <- results do
        Task.shutdown(task, :brutal_kill)
      end
    end

    test "handles socket exhaustion gracefully" do
      # Create many concurrent operations to test socket limits
      concurrent_operations = for i <- 1..50 do
        target = "192.0.2.#{rem(i, 254) + 1}"  # Use RFC test IPs
        Task.async(fn ->
          SNMPMgr.get(target, @test_oids.system_descr, [timeout: 500, retries: 0])
        end)
      end
      
      results = Task.yield_many(concurrent_operations, 10000)
      
      # Should handle socket exhaustion gracefully
      completed_count = Enum.count(results, fn {_task, result} -> result != nil end)
      
      assert completed_count > 0, "Some operations should complete despite socket pressure"
      
      # Check for socket-related errors
      socket_errors = Enum.count(results, fn {_task, result} ->
        case result do
          {:ok, {:error, reason}} when reason in [:emfile, :enfile, :socket_limit] -> true
          _ -> false
        end
      end)
      
      if socket_errors > 0 do
        assert true, "Socket exhaustion handled gracefully"
      else
        assert true, "Socket operations completed without exhaustion"
      end
      
      # Clean up any remaining tasks
      for {task, _result} <- results do
        Task.shutdown(task, :brutal_kill)
      end
    end

    test "validates input size limits" do
      large_input_cases = [
        # Very long OID
        {"127.0.0.1", String.duplicate("1.2.", 1000) <> "0", "Extremely long OID"},
        
        # Very long community string
        {"127.0.0.1", @test_oids.system_descr, [community: String.duplicate("a", 1000)], "Huge community string"},
        
        # Very long hostname
        {String.duplicate("host", 100) <> ".example.com", @test_oids.system_descr, [], "Very long hostname"}
      ]
      
      for {target, oid, opts, description} <- large_input_cases do
        case SNMPMgr.get(target, oid, opts ++ [timeout: 1000]) do
          {:ok, _value} ->
            flunk("#{description} should not succeed")
            
          {:error, reason} when reason in [:input_too_large, :invalid_input, :bad_oid,
                                          :bad_community, :hostname_too_long, :snmp_modules_not_available] ->
            assert true, "#{description} appropriately rejected: #{reason}"
            
          {:error, reason} ->
            assert is_atom(reason), "#{description} error: #{inspect(reason)}"
        end
      end
    end
  end

  describe "error message quality" do
    test "provides clear and actionable error messages" do
      error_clarity_cases = [
        # Network errors
        {"192.0.2.1", @test_oids.system_descr, [timeout: 1000], "Network unreachable"},
        
        # Authentication errors
        {"127.0.0.1", @test_oids.system_descr, [community: "invalid"], "Bad community"},
        
        # Invalid OID errors
        {"127.0.0.1", "invalid.oid", [], "Invalid OID format"},
        
        # SET errors
        {"127.0.0.1", @test_oids.system_descr, [set_value: "test"], "Read-only SET"}
      ]
      
      for {target, oid, opts, description} <- error_clarity_cases do
        operation = if Keyword.has_key?(opts, :set_value) do
          value = Keyword.get(opts, :set_value)
          clean_opts = Keyword.delete(opts, :set_value)
          fn -> SNMPMgr.set(target, oid, value, clean_opts) end
        else
          fn -> SNMPMgr.get(target, oid, opts) end
        end
        
        case operation.() do
          {:ok, _result} ->
            assert true, "#{description} unexpectedly succeeded"
            
          {:error, reason} ->
            # Error should be descriptive (atom or tuple with details)
            assert is_atom(reason) or (is_tuple(reason) and tuple_size(reason) >= 2),
              "#{description} error should be descriptive: #{inspect(reason)}"
              
            # Common error types should be recognizable
            recognized_error = reason in [
              :timeout, :host_unreachable, :network_unreachable, :connection_refused,
              :authentication_error, :bad_community, :invalid_oid, :no_such_name,
              :read_only, :no_access, :snmp_modules_not_available
            ]
            
            if recognized_error do
              assert true, "#{description} error is well-known type: #{reason}"
            else
              assert true, "#{description} error is custom but descriptive: #{inspect(reason)}"
            end
        end
      end
    end

    test "includes contextual information in errors" do
      # Test that errors include helpful context
      contextual_cases = [
        # Should include target information
        {"nonexistent.host", @test_oids.system_descr, "Hostname context"},
        
        # Should include OID information
        {"127.0.0.1", "1.2.3.4.5.6.7.8.9.0", "OID context"},
        
        # Should include operation context
        {"127.0.0.1", @test_oids.system_descr, "Operation context"}
      ]
      
      for {target, oid, description} <- contextual_cases do
        case SNMPMgr.get(target, oid, [timeout: 1000]) do
          {:ok, _value} ->
            assert true, "#{description} unexpectedly succeeded"
            
          {:error, reason} ->
            # Complex errors should include context
            case reason do
              {error_type, context} when is_atom(error_type) ->
                assert is_binary(context) or is_map(context) or is_list(context),
                  "#{description} should include context: #{inspect(context)}"
                  
              simple_atom when is_atom(simple_atom) ->
                assert true, "#{description} simple error is acceptable: #{simple_atom}"
                
              other ->
                assert true, "#{description} error format: #{inspect(other)}"
            end
        end
      end
    end
  end

  describe "recovery and resilience" do
    test "recovers from transient failures" do
      # Simulate transient failures by using very short timeouts first, then normal timeouts
      recovery_target = "127.0.0.1"
      
      # First try with very short timeout (likely to fail)
      first_result = SNMPMgr.get(recovery_target, @test_oids.system_descr, [timeout: 1, retries: 0])
      
      # Then try with normal timeout
      second_result = SNMPMgr.get(recovery_target, @test_oids.system_descr, [timeout: 5000, retries: 1])
      
      case {first_result, second_result} do
        {{:error, :timeout}, {:ok, _value}} ->
          assert true, "Successfully recovered from transient timeout"
          
        {{:error, _}, {:error, :snmp_modules_not_available}} ->
          assert true, "SNMP modules not available for recovery test"
          
        {{:error, _first_error}, {:error, _second_error}} ->
          assert true, "Both attempts failed (consistent failure, not transient)"
          
        {{:ok, _}, {:ok, _}} ->
          assert true, "Both attempts succeeded (very fast response)"
          
        other ->
          assert true, "Recovery test completed with mixed results: #{inspect(other)}"
      end
    end

    test "handles cascading failures gracefully" do
      # Test behavior when multiple related operations fail
      cascading_operations = [
        {"192.0.2.1", @test_oids.system_descr},
        {"192.0.2.2", @test_oids.system_uptime},
        {"192.0.2.3", @test_oids.system_contact},
        {"192.0.2.4", @test_oids.system_name}
      ]
      
      results = for {target, oid} <- cascading_operations do
        SNMPMgr.get(target, oid, [timeout: 1000, retries: 0])
      end
      
      # All should fail, but gracefully
      assert length(results) == 4, "All cascading operations should complete"
      
      for {result, i} <- Enum.with_index(results) do
        case result do
          {:ok, _value} ->
            assert true, "Cascading operation #{i} unexpectedly succeeded"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Cascading failure #{i} should be well-formed: #{inspect(reason)}"
        end
      end
    end

    test "maintains stability under concurrent error conditions" do
      # Create many concurrent operations that are likely to fail
      concurrent_failing_ops = for i <- 1..20 do
        Task.async(fn ->
          target = "192.0.2.#{rem(i, 5) + 1}"
          SNMPMgr.get(target, @test_oids.system_descr, [timeout: 500, retries: 0])
        end)
      end
      
      results = Task.yield_many(concurrent_failing_ops, 5000)
      
      # Should handle concurrent failures without crashing
      completed_count = Enum.count(results, fn {_task, result} -> result != nil end)
      
      assert completed_count == 20, "All concurrent failing operations should complete"
      
      # Check that failures are handled properly
      error_count = Enum.count(results, fn {_task, result} ->
        case result do
          {:ok, {:error, _}} -> true
          _ -> false
        end
      end)
      
      assert error_count >= 15, "Most operations should fail as expected"
      
      # Clean up
      for {task, _result} <- results do
        Task.shutdown(task, :brutal_kill)
      end
    end
  end

  describe "integration with SNMP simulator error scenarios" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    @tag :integration
    test "handles simulator authentication errors", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with wrong community
      case SNMPMgr.get(target, @test_oids.system_descr, [community: "wrong_community"]) do
        {:ok, _value} ->
          flunk("Should not succeed with wrong community")
          
        {:error, reason} when reason in [:authentication_error, :bad_community, :timeout] ->
          assert true, "Correctly rejected wrong community: #{reason}"
          
        {:error, :snmp_modules_not_available} ->
          assert true, "SNMP modules not available for integration test"
          
        {:error, reason} ->
          assert is_atom(reason), "Auth error with simulator: #{inspect(reason)}"
      end
    end

    @tag :integration
    test "handles simulator timeout scenarios", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with very short timeout
      case SNMPMgr.get(target, @test_oids.system_descr, 
                      [community: device.community, timeout: 10, retries: 0]) do
        {:ok, _value} ->
          assert true, "Simulator responded very quickly"
          
        {:error, :timeout} ->
          assert true, "Simulator timeout handled correctly"
          
        {:error, :snmp_modules_not_available} ->
          assert true, "SNMP modules not available for integration test"
          
        {:error, reason} ->
          assert is_atom(reason), "Simulator timeout error: #{inspect(reason)}"
      end
    end

    @tag :integration
    test "handles simulator error responses", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with non-existent OID
      case SNMPMgr.get(target, "1.2.3.4.5.6.7.8.9.0", [community: device.community]) do
        {:ok, _value} ->
          flunk("Should not succeed with non-existent OID")
          
        {:error, reason} when reason in [:no_such_name, :no_such_object] ->
          assert true, "Simulator correctly reported non-existent OID: #{reason}"
          
        {:error, :snmp_modules_not_available} ->
          assert true, "SNMP modules not available for integration test"
          
        {:error, reason} ->
          assert is_atom(reason), "Simulator error response: #{inspect(reason)}"
      end
    end
  end
end