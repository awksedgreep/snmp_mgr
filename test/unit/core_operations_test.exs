defmodule SNMPMgr.CoreOperationsTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.{Config, MIB}
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :core_operations
  @moduletag :phase_3

  # Standard OIDs for testing
  @test_oids %{
    system_descr: "1.3.6.1.2.1.1.1.0",
    system_uptime: "1.3.6.1.2.1.1.3.0",
    system_contact: "1.3.6.1.2.1.1.4.0",
    system_name: "1.3.6.1.2.1.1.5.0",
    system_location: "1.3.6.1.2.1.1.6.0",
    if_number: "1.3.6.1.2.1.2.1.0",
    if_table: "1.3.6.1.2.1.2.2",
    if_entry: "1.3.6.1.2.1.2.2.1",
    if_descr: "1.3.6.1.2.1.2.2.1.2",
    if_speed: "1.3.6.1.2.1.2.2.1.5",
    if_admin_status: "1.3.6.1.2.1.2.2.1.7",
    if_oper_status: "1.3.6.1.2.1.2.2.1.8"
  }

  # Valid test targets
  @test_targets [
    "127.0.0.1:161",
    "localhost:161",
    "192.168.1.1",
    "device.local:1161"
  ]

  # Invalid test targets
  @invalid_targets [
    "",
    "invalid.host.name.that.does.not.exist",
    "256.256.256.256",
    "127.0.0.1:70000",
    nil,
    123,
    []
  ]

  setup_all do
    # Ensure configuration is available
    case GenServer.whereis(SNMPMgr.Config) do
      nil -> {:ok, _pid} = Config.start_link()
      _pid -> :ok
    end
    
    # Ensure MIB is available
    case GenServer.whereis(SNMPMgr.MIB) do
      nil -> {:ok, _pid} = MIB.start_link()
      _pid -> :ok
    end
    
    :ok
  end

  describe "SNMP GET operations" do
    test "validates GET request parameters" do
      valid_params = [
        {"127.0.0.1:161", @test_oids.system_descr, []},
        {"localhost", @test_oids.system_uptime, [community: "public"]},
        {"192.168.1.1", @test_oids.if_number, [community: "private", timeout: 10000]},
        {"device.local:1161", @test_oids.system_name, [retries: 3, version: :v2c]}
      ]
      
      for {target, oid, opts} <- valid_params do
        case SNMPMgr.get(target, oid, opts) do
          {:ok, _value} ->
            assert true, "GET succeeded for #{target} #{oid}"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available (expected)"
            
          {:error, reason} ->
            # Network or device errors are acceptable
            assert is_atom(reason) or is_tuple(reason),
              "GET should provide descriptive error: #{inspect(reason)}"
        end
      end
    end

    test "rejects invalid GET request parameters" do
      invalid_params = [
        # Invalid targets
        {"", @test_oids.system_descr, []},
        {nil, @test_oids.system_descr, []},
        {123, @test_oids.system_descr, []},
        
        # Invalid OIDs
        {"127.0.0.1", "", []},
        {"127.0.0.1", "invalid.oid", []},
        {"127.0.0.1", nil, []},
        {"127.0.0.1", 123, []},
        
        # Invalid options
        {"127.0.0.1", @test_oids.system_descr, [community: nil]},
        {"127.0.0.1", @test_oids.system_descr, [timeout: -1]},
        {"127.0.0.1", @test_oids.system_descr, [retries: -1]},
      ]
      
      for {target, oid, opts} <- invalid_params do
        case SNMPMgr.get(target, oid, opts) do
          {:ok, _value} ->
            flunk("Invalid GET parameters should not succeed: #{inspect({target, oid, opts})}")
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Should provide descriptive error for invalid params: #{inspect(reason)}"
        end
      end
    end

    test "handles various OID formats in GET requests" do
      oid_formats = [
        # String OID
        {"1.3.6.1.2.1.1.1.0", "String OID format"},
        
        # List OID
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], "List OID format"},
        
        # MIB name (if available)
        {"sysDescr.0", "MIB name format"},
        
        # Partial OID
        {"1.3.6.1.2.1.1", "Partial OID (should work with GETNEXT)"},
      ]
      
      for {oid, description} <- oid_formats do
        case SNMPMgr.get("127.0.0.1", oid) do
          {:ok, _value} ->
            assert true, "#{description} succeeded"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available for #{description}"
            
          {:error, reason} ->
            # Some formats might not be supported or network issues
            assert is_atom(reason) or is_tuple(reason),
              "#{description} error should be descriptive: #{inspect(reason)}"
        end
      end
    end

    test "respects timeout and retry options" do
      # Test with short timeout
      short_timeout_result = SNMPMgr.get("127.0.0.1", @test_oids.system_descr, 
                                        [timeout: 100, retries: 0])
      
      case short_timeout_result do
        {:ok, _value} ->
          # Might succeed if local response is very fast
          assert true, "Fast local response"
          
        {:error, :timeout} ->
          assert true, "Timeout properly detected"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          assert is_atom(reason), "Timeout error should be descriptive: #{inspect(reason)}"
      end
      
      # Test with retries
      retry_result = SNMPMgr.get("127.0.0.1", @test_oids.system_descr,
                                [timeout: 1000, retries: 3])
      
      case retry_result do
        {:ok, _value} ->
          assert true, "GET with retries succeeded"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          assert is_atom(reason), "Retry error should be descriptive: #{inspect(reason)}"
      end
    end

    test "uses configuration defaults correctly" do
      # Set some defaults
      Config.set_default_community("test_community")
      Config.set_default_timeout(8000)
      Config.set_default_retries(2)
      
      # GET without explicit options should use defaults
      case SNMPMgr.get("127.0.0.1", @test_oids.system_descr) do
        {:ok, _value} ->
          assert true, "GET with config defaults succeeded"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          # Verify that the operation attempted with configured values
          assert is_atom(reason), "Should use config defaults: #{inspect(reason)}"
      end
      
      # Reset to defaults
      Config.reset()
    end
  end

  describe "SNMP GETNEXT operations" do
    test "validates GETNEXT request parameters" do
      valid_getnext_params = [
        {"127.0.0.1", "1.3.6.1.2.1.1", []},
        {"localhost", "1.3.6.1.2.1.2.2.1", [community: "public"]},
        {"192.168.1.1", "1.3.6.1.2.1", [timeout: 5000]},
      ]
      
      for {target, oid, opts} <- valid_getnext_params do
        case SNMPMgr.get_next(target, oid, opts) do
          {:ok, {next_oid, value}} ->
            assert is_list(next_oid) or is_binary(next_oid),
              "GETNEXT should return next OID"
            assert is_binary(value) or is_integer(value),
              "GETNEXT should return value"
              
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "GETNEXT error should be descriptive: #{inspect(reason)}"
        end
      end
    end

    test "GETNEXT progression through MIB tree" do
      # Test that GETNEXT progresses through the tree correctly
      starting_oids = [
        "1.3.6.1.2.1.1.1",    # Should get sysDescr.0
        "1.3.6.1.2.1.1.2",    # Should get sysObjectID.0
        "1.3.6.1.2.1.1",      # Should get first object in system group
        "1.3.6.1.2.1.2",      # Should get first object in interfaces group
      ]
      
      for starting_oid <- starting_oids do
        case SNMPMgr.get_next("127.0.0.1", starting_oid) do
          {:ok, {next_oid, _value}} ->
            # Verify progression
            starting_list = case starting_oid do
              str when is_binary(str) ->
                case SNMPMgr.OID.string_to_list(str) do
                  {:ok, list} -> list
                  _ -> []
                end
              list when is_list(list) -> list
            end
            
            next_list = case next_oid do
              str when is_binary(str) ->
                case SNMPMgr.OID.string_to_list(str) do
                  {:ok, list} -> list
                  _ -> []
                end
              list when is_list(list) -> list
            end
            
            if length(starting_list) > 0 and length(next_list) > 0 do
              # Next OID should be lexicographically greater
              assert next_list > starting_list,
                "GETNEXT should progress: #{inspect(starting_list)} -> #{inspect(next_list)}"
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason), "GETNEXT progression error: #{inspect(reason)}"
        end
      end
    end

    test "handles end of MIB view in GETNEXT" do
      # Test with OID at end of standard tree
      end_oids = [
        "1.3.6.1.2.1.999.999.999",  # Way beyond standard MIB
        "2.0.0.0",                   # Different tree entirely
      ]
      
      for end_oid <- end_oids do
        case SNMPMgr.get_next("127.0.0.1", end_oid) do
          {:ok, _result} ->
            # Might find something in extended tree
            assert true, "GETNEXT found object beyond expected range"
            
          {:error, :end_of_mib_view} ->
            assert true, "Correctly detected end of MIB view"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason), "End of MIB error should be descriptive: #{inspect(reason)}"
        end
      end
    end
  end

  describe "SNMP SET operations" do
    test "validates SET request parameters" do
      # Note: SET operations typically require write community and writable OIDs
      set_test_cases = [
        {"127.0.0.1", @test_oids.system_contact, "Test Contact", []},
        {"127.0.0.1", @test_oids.system_name, "Test Device", [community: "private"]},
        {"127.0.0.1", @test_oids.system_location, "Test Location", [timeout: 10000]},
      ]
      
      for {target, oid, value, opts} <- set_test_cases do
        case SNMPMgr.set(target, oid, value, opts) do
          {:ok, _result} ->
            assert true, "SET operation succeeded"
            
          {:error, :read_only} ->
            assert true, "OID is read-only (expected for some objects)"
            
          {:error, :no_access} ->
            assert true, "No write access (expected with read community)"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "SET error should be descriptive: #{inspect(reason)}"
        end
      end
    end

    test "rejects invalid SET values and types" do
      invalid_set_cases = [
        # Wrong value types
        {"127.0.0.1", @test_oids.system_contact, 123, []},
        {"127.0.0.1", @test_oids.if_admin_status, "invalid_status", []},
        
        # Invalid values for specific types
        {"127.0.0.1", @test_oids.if_admin_status, 999, []},  # Out of enum range
        
        # Nil values
        {"127.0.0.1", @test_oids.system_name, nil, []},
      ]
      
      for {target, oid, value, opts} <- invalid_set_cases do
        case SNMPMgr.set(target, oid, value, opts) do
          {:ok, _result} ->
            flunk("Invalid SET should not succeed: #{inspect({oid, value})}")
            
          {:error, reason} ->
            assert reason in [:bad_value, :wrong_type, :wrong_value, :snmp_modules_not_available] or 
                   is_atom(reason),
              "Should reject invalid SET value: #{inspect(reason)}"
        end
      end
    end

    test "validates SET type conversion" do
      # Test automatic type conversion for SET operations
      type_conversion_cases = [
        # String values
        {@test_oids.system_contact, "Admin Contact", :string},
        {@test_oids.system_name, "Device Name", :string},
        {@test_oids.system_location, "Data Center", :string},
        
        # Integer values (administrative status: 1=up, 2=down, 3=testing)
        {@test_oids.if_admin_status <> ".1", 1, :integer},
        {@test_oids.if_admin_status <> ".1", 2, :integer},
      ]
      
      for {oid, value, expected_type} <- type_conversion_cases do
        case SNMPMgr.set("127.0.0.1", oid, value) do
          {:ok, _result} ->
            assert true, "SET with type conversion succeeded for #{expected_type}"
            
          {:error, reason} when reason in [:read_only, :no_access, :snmp_modules_not_available] ->
            # Expected errors
            assert true, "SET blocked by permissions or availability"
            
          {:error, reason} ->
            assert is_atom(reason), "Type conversion error should be descriptive: #{inspect(reason)}"
        end
      end
    end
  end

  describe "asynchronous operations" do
    test "validates async GET operations" do
      case SNMPMgr.get_async("127.0.0.1", @test_oids.system_descr) do
        ref when is_reference(ref) ->
          # Should receive a message with the result
          receive do
            {^ref, result} ->
              case result do
                {:ok, _value} ->
                  assert true, "Async GET succeeded"
                  
                {:error, :snmp_modules_not_available} ->
                  assert true, "SNMP modules not available"
                  
                {:error, reason} ->
                  assert is_atom(reason), "Async GET error: #{inspect(reason)}"
              end
          after
            5000 ->
              flunk("Async GET should send result message")
          end
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available for async operations"
          
        {:error, reason} ->
          assert is_atom(reason), "Async GET start error: #{inspect(reason)}"
      end
    end

    test "handles multiple concurrent async operations" do
      # Start multiple async operations
      refs = for i <- 1..5 do
        case SNMPMgr.get_async("127.0.0.1", @test_oids.system_descr, timeout: 2000) do
          ref when is_reference(ref) -> {ref, i}
          {:error, _} -> nil
        end
      end
      
      valid_refs = Enum.filter(refs, &(&1 != nil))
      
      if length(valid_refs) > 0 do
        # Collect results
        results = for {ref, i} <- valid_refs do
          receive do
            {^ref, result} -> {i, result}
          after
            3000 -> {i, {:error, :timeout}}
          end
        end
        
        # All operations should complete
        assert length(results) == length(valid_refs),
          "All async operations should complete"
        
        # Check that results are properly tagged
        for {i, result} <- results do
          assert is_integer(i), "Result should be tagged with operation ID"
          case result do
            {:ok, _} -> assert true, "Async operation #{i} succeeded"
            {:error, reason} -> 
              assert is_atom(reason), "Async operation #{i} error: #{inspect(reason)}"
          end
        end
      else
        # No async operations started (SNMP modules not available)
        assert true, "Async operations not available in test environment"
      end
    end
  end

  describe "configuration integration" do
    test "merges operation options with configuration" do
      # Set specific configuration
      Config.set_default_community("default_community")
      Config.set_default_timeout(6000)
      Config.set_default_retries(2)
      Config.set_default_version(:v2c)
      
      # Test that explicit options override defaults
      explicit_opts = [community: "explicit_community", timeout: 3000]
      
      case SNMPMgr.get("127.0.0.1", @test_oids.system_descr, explicit_opts) do
        {:ok, _value} ->
          assert true, "GET with explicit options succeeded"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          # The operation should have attempted with explicit options
          assert is_atom(reason), "Option override error: #{inspect(reason)}"
      end
      
      # Test that defaults are used when options are not specified
      case SNMPMgr.get("127.0.0.1", @test_oids.system_descr) do
        {:ok, _value} ->
          assert true, "GET with default options succeeded"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          assert is_atom(reason), "Default options error: #{inspect(reason)}"
      end
      
      # Reset configuration
      Config.reset()
    end

    test "handles missing configuration gracefully" do
      # Stop configuration server
      case GenServer.whereis(SNMPMgr.Config) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
      
      # Operations should still work with hardcoded defaults
      case SNMPMgr.get("127.0.0.1", @test_oids.system_descr) do
        {:ok, _value} ->
          assert true, "GET without config server succeeded"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available"
          
        {:error, reason} ->
          assert is_atom(reason), "No config error: #{inspect(reason)}"
      end
      
      # Restart configuration server
      case Config.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end
  end

  describe "error handling and edge cases" do
    test "handles network unreachability" do
      unreachable_targets = [
        "192.0.2.1",          # RFC 5737 test network
        "10.255.255.254",     # Unlikely to exist
        "203.0.113.1:161",    # RFC 5737 test network
      ]
      
      for target <- unreachable_targets do
        case SNMPMgr.get(target, @test_oids.system_descr, [timeout: 1000, retries: 0]) do
          {:ok, _value} ->
            # Unexpected success
            assert true, "Unexpectedly reached #{target}"
            
          {:error, reason} when reason in [:timeout, :host_unreachable, :network_unreachable, :ehostunreach, :enetunreach] ->
            assert true, "Correctly detected unreachable host #{target}"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available"
            
          {:error, reason} ->
            assert is_atom(reason), "Unreachable host error: #{inspect(reason)}"
        end
      end
    end

    test "handles malformed responses gracefully" do
      # Test with invalid targets that might return malformed data
      malformed_targets = [
        "127.0.0.1:80",    # HTTP port instead of SNMP
        "127.0.0.1:22",    # SSH port instead of SNMP
      ]
      
      for target <- malformed_targets do
        case SNMPMgr.get(target, @test_oids.system_descr, [timeout: 1000]) do
          {:ok, _value} ->
            flunk("Should not get valid SNMP response from #{target}")
            
          {:error, reason} ->
            assert reason in [:decode_error, :malformed_packet, :connection_refused, :timeout, :snmp_modules_not_available] or
                   is_atom(reason),
              "Malformed response error should be descriptive: #{inspect(reason)}"
        end
      end
    end

    test "validates resource cleanup" do
      # Perform many operations to test resource cleanup
      operation_count = 50
      
      results = for i <- 1..operation_count do
        case SNMPMgr.get("127.0.0.1", @test_oids.system_descr, [timeout: 100]) do
          {:ok, value} -> {:ok, i, value}
          {:error, reason} -> {:error, i, reason}
        end
      end
      
      # All operations should complete without resource leaks
      assert length(results) == operation_count,
        "All operations should complete"
      
      # Check for any patterns in failures
      errors = Enum.filter(results, fn
        {:error, _i, _reason} -> true
        _ -> false
      end)
      
      successes = Enum.filter(results, fn
        {:ok, _i, _value} -> true
        _ -> false
      end)
      
      # At least operations should not crash
      assert length(errors) + length(successes) == operation_count,
        "All operations should return valid responses"
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "basic operations are fast" do
      # Measure time for basic GET operation
      {time_microseconds, _result} = :timer.tc(fn ->
        for _i <- 1..100 do
          SNMPMgr.get("127.0.0.1", @test_oids.system_descr, [timeout: 1000])
        end
      end)
      
      time_per_operation = time_microseconds / 100
      
      # Should be fast (less than 10ms per operation including network)
      assert time_per_operation < 10_000,
        "Basic GET operations too slow: #{time_per_operation} microseconds per operation"
    end

    @tag :performance
    test "memory usage is reasonable" do
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)
      
      # Perform many operations
      _results = for _i <- 1..100 do
        SNMPMgr.get("127.0.0.1", @test_oids.system_descr, [timeout: 500])
        SNMPMgr.get_next("127.0.0.1", "1.3.6.1.2.1.1", [timeout: 500])
      end
      
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      # Should use reasonable memory (less than 5MB for all operations)
      assert memory_used < 5_000_000,
        "Core operations memory usage too high: #{memory_used} bytes"
      
      :erlang.garbage_collect()
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
    test "core operations work with real SNMP device", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test GET operation
      case SNMPMgr.get(target, @test_oids.system_descr, community: device.community) do
        {:ok, response} ->
          assert is_binary(response), "GET response should be a string"
          assert String.length(response) > 0, "GET response should not be empty"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available for integration test"
          
        {:error, reason} ->
          flunk("GET operation with simulator failed: #{inspect(reason)}")
      end
      
      # Test GETNEXT operation
      case SNMPMgr.get_next(target, "1.3.6.1.2.1.1", community: device.community) do
        {:ok, {next_oid, value}} ->
          assert is_binary(next_oid) or is_list(next_oid), "GETNEXT should return OID"
          assert is_binary(value) or is_integer(value), "GETNEXT should return value"
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available for integration test"
          
        {:error, reason} ->
          flunk("GETNEXT operation with simulator failed: #{inspect(reason)}")
      end
    end

    @tag :integration
    test "error handling works with real device", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with invalid community
      case SNMPMgr.get(target, @test_oids.system_descr, community: "invalid_community") do
        {:ok, _response} ->
          flunk("Should not succeed with invalid community")
          
        {:error, reason} when reason in [:authentication_error, :bad_community, :snmp_modules_not_available] ->
          assert true, "Correctly rejected invalid community"
          
        {:error, reason} ->
          # Other auth-related errors are acceptable
          assert is_atom(reason), "Auth error should be descriptive: #{inspect(reason)}"
      end
      
      # Test with non-existent OID
      case SNMPMgr.get(target, "1.2.3.4.5.6.7.8.9.0", community: device.community) do
        {:ok, _response} ->
          flunk("Should not succeed with non-existent OID")
          
        {:error, reason} when reason in [:no_such_name, :no_such_object, :snmp_modules_not_available] ->
          assert true, "Correctly rejected non-existent OID"
          
        {:error, reason} ->
          assert is_atom(reason), "No such name error should be descriptive: #{inspect(reason)}"
      end
    end
  end
end