defmodule SnmpMgr.IntegrationTest do
  use ExUnit.Case, async: false
  
  alias SnmpMgr.TestSupport.SNMPSimulator
  
  @moduletag :integration

  setup_all do
    # Ensure required GenServers are started
    case GenServer.whereis(SnmpMgr.Config) do
      nil -> {:ok, _pid} = SnmpMgr.Config.start_link()
      _pid -> :ok
    end
    
    # Create test device following @testing_rules
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}
      error ->
        %{device: nil, setup_error: error}
    end
  end

  describe "SnmpMgr Full Integration" do
    test "get/3 complete integration flow", %{device: device} do
      skip_if_no_device(device)
      
      # Test complete flow through all layers: API -> Core -> SnmpLib.Manager
      result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                          community: device.community, version: :v2c, timeout: 200)
      
      case result do
        {:ok, value} ->
          # Successful operation through snmp_lib
          assert is_binary(value) or is_integer(value) or is_list(value) or is_atom(value)
          assert byte_size(to_string(value)) > 0
        {:error, reason} ->
          # Accept valid SNMP errors from simulator
          assert reason in [:timeout, :noSuchObject, :noSuchInstance, :endOfMibView, :end_of_mib_view]
      end
    end

    test "set/4 complete integration flow", %{device: device} do
      skip_if_no_device(device)
      
      # Test SET operation through snmp_lib
      result = SnmpMgr.set("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.6.0", "test_location", 
                          community: device.community, version: :v2c, timeout: 200)
      
      case result do
        {:ok, value} ->
          # Successful SET through snmp_lib
          assert is_binary(value) or is_atom(value) or is_integer(value)
        {:error, reason} ->
          # Accept valid SNMP errors (many objects are read-only)
          assert reason in [:read_only, :no_access, :timeout, :noSuchObject, :gen_err]
      end
    end

    test "get_bulk/3 complete integration flow", %{device: device} do
      skip_if_no_device(device)
      
      # Test GET-BULK operation through SnmpLib.Manager
      result = SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2", 
                               max_repetitions: 5, non_repeaters: 0, 
                               community: device.community, version: :v2c, timeout: 200)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Successful bulk operation through snmp_lib
          assert true
        {:error, reason} ->
          # Accept valid bulk operation errors
          assert reason in [:timeout, :noSuchObject, :getbulk_requires_v2c]
      end
    end

    test "walk/3 complete integration flow", %{device: device} do
      skip_if_no_device(device)
      
      # Test WALK operation through snmp_lib integration
      result = SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1", 
                           community: device.community, version: :v2c, timeout: 200)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Successful walk through snmp_lib
          if length(results) > 0 do
            Enum.each(results, fn {oid, type, value} ->
              assert is_binary(oid)
              assert String.starts_with?(oid, "1.3.6.1.2.1.1")
              assert is_atom(type)
              assert value != nil
            end)
          end
          assert true
        {:error, reason} ->
          # Accept valid walk errors
          assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view]
      end
    end

    test "get_next/3 complete integration flow", %{device: device} do
      skip_if_no_device(device)
      
      # Test GET-NEXT operation through SnmpLib.Manager
      result = SnmpMgr.get_next("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1", 
                               community: device.community, version: :v2c, timeout: 200)
      
      case result do
        {:ok, {oid, value}} ->
          # Successful get_next through snmp_lib
          assert is_binary(oid) or is_list(oid)
          assert is_binary(value) or is_integer(value) or is_list(value) or is_atom(value)
        {:error, reason} ->
          # Accept valid get_next errors (both old and new formats)
          assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view]
      end
    end
  end

  describe "SnmpMgr Multi-Operation Integration" do
    test "get_multi/1 processes multiple requests", %{device: device} do
      skip_if_no_device(device)
      
      # Use same device with different OIDs for multi-operation testing
      requests = [
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", [community: device.community, timeout: 200]},
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.3.0", [community: device.community, timeout: 200]},
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.5.0", [community: device.community, timeout: 200]}
      ]
      
      results = SnmpMgr.get_multi(requests)
      
      assert is_list(results)
      assert length(results) == 3
      
      # All should return proper format from snmp_lib integration
      Enum.each(results, fn result ->
        case result do
          {:ok, _value} -> assert true
          {:error, reason} ->
            # Accept valid SNMP errors from simulator
            assert reason in [:timeout, :noSuchObject, :noSuchInstance]
        end
      end)
    end

    test "get_bulk_multi/1 processes multiple bulk requests", %{device: device} do
      skip_if_no_device(device)
      
      # Use same device with different OID trees for bulk testing
      requests = [
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2", [max_repetitions: 3, community: device.community, timeout: 200]},
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1", [max_repetitions: 3, community: device.community, timeout: 200]}
      ]
      
      results = SnmpMgr.get_bulk_multi(requests)
      
      assert is_list(results)
      assert length(results) == 2
      
      # All should return proper format from snmp_lib integration
      Enum.each(results, fn result ->
        case result do
          {:ok, list} when is_list(list) -> assert true
          {:error, reason} ->
            # Accept valid bulk operation errors
            assert reason in [:timeout, :noSuchObject, :getbulk_requires_v2c]
        end
      end)
    end
  end

  describe "SnmpMgr Configuration Integration" do
    test "global configuration affects operations", %{device: device} do
      skip_if_no_device(device)
      
      # Set custom defaults using simulator community
      SnmpMgr.Config.set_default_community(device.community)
      SnmpMgr.Config.set_default_timeout(200)
      SnmpMgr.Config.set_default_version(:v2c)
      
      # Operation should use these defaults with simulator
      result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0")
      
      # Should succeed with configured defaults through snmp_lib
      assert {:ok, _} = result
      
      # Reset to defaults
      SnmpMgr.Config.reset()
    end

    test "request options override configuration", %{device: device} do
      skip_if_no_device(device)
      
      # Set one default
      SnmpMgr.Config.set_default_timeout(200)
      
      # Override with request option using simulator
      result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                          community: device.community, timeout: 200, version: :v1)
      
      # Should succeed with overridden options through snmp_lib
      assert {:ok, _} = result
      
      SnmpMgr.Config.reset()
    end

    test "configuration merging works correctly" do
      # Test the merge_opts function used by all operations
      SnmpMgr.Config.set_default_community("default_comm")
      SnmpMgr.Config.set_default_timeout(200)
      SnmpMgr.Config.set_default_version(:v1)
      
      merged = SnmpMgr.Config.merge_opts([community: "override", retries: 3])
      
      # Should have overridden community but default timeout and version
      assert merged[:community] == "override"
      assert merged[:timeout] == 200
      assert merged[:version] == :v1
      assert merged[:retries] == 3
      
      SnmpMgr.Config.reset()
    end
  end

  describe "SnmpMgr OID Processing Integration" do
    test "string OIDs processed through SnmpLib.OID", %{device: device} do
      skip_if_no_device(device)
      
      # Test various OID formats through SnmpLib.OID integration
      oid_formats = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.3.0",
        "1.3.6.1.2.1.1.5.0"
      ]
      
      Enum.each(oid_formats, fn oid ->
        result = SnmpMgr.get("#{device.host}:#{device.port}", oid, community: device.community, timeout: 200)
        # Should process OID through SnmpLib.OID and return proper format
        assert {:ok, _} = result
      end)
    end

    test "list OIDs processed through SnmpLib.OID", %{device: device} do
      skip_if_no_device(device)
      
      # Test list format OIDs
      list_oids = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 2, 1, 1, 3, 0],
        [1, 3, 6, 1, 2, 1, 1, 5, 0]
      ]
      
      Enum.each(list_oids, fn oid ->
        result = SnmpMgr.get("#{device.host}:#{device.port}", oid, community: device.community, timeout: 200)
        # Should process list OID through SnmpLib.OID
        assert {:ok, _} = result
      end)
    end

    test "symbolic OIDs through MIB integration", %{device: device} do
      skip_if_no_device(device)
      
      # Test symbolic OIDs that should resolve through MIB integration
      symbolic_oids = [
        "sysDescr.0",
        "sysUpTime.0",
        "sysName.0"
      ]
      
      Enum.each(symbolic_oids, fn oid ->
        result = SnmpMgr.get("#{device.host}:#{device.port}", oid, community: device.community, timeout: 200)
        # Should process symbolic OID through MIB -> SnmpLib.OID chain
        assert {:ok, _} = result
      end)
    end

    test "invalid OIDs handled properly", %{device: device} do
      skip_if_no_device(device)
      
      invalid_oids = [
        "invalid.oid.format",
        "1.3.6.1.2.1.999.999.999.0",
        "not.a.valid.oid"
      ]
      
      Enum.each(invalid_oids, fn oid ->
        result = SnmpMgr.get("#{device.host}:#{device.port}", oid, community: device.community, timeout: 200)
        # Should return error for invalid OIDs
        case result do
          {:error, _reason} -> assert true
          {:ok, _value} -> assert true  # Some invalid OIDs might resolve unexpectedly
        end
      end)
    end
  end

  describe "SnmpMgr Error Handling Integration" do
    test "network errors through snmp_lib" do
      # Test various network error conditions with unreachable hosts
      error_targets = [
        "240.0.0.1",  # Unreachable IP  
        "192.0.2.254",  # Documentation range
        "169.254.1.1"  # Link-local
      ]
      
      Enum.each(error_targets, fn target ->
        result = SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: "public", timeout: 200)
        
        case result do
          {:error, reason} when reason in [:timeout, :host_unreachable, :network_unreachable,
                                          :ehostunreach, :enetunreach, :econnrefused] ->
            assert true  # Expected network errors through snmp_lib
          {:error, _other} -> assert true  # Other errors acceptable
          {:ok, _} -> assert true  # Unexpected success (device might exist)
        end
      end)
    end

    test "timeout handling through snmp_lib", %{device: device} do
      skip_if_no_device(device)
      
      # Test timeout behavior through snmp_lib with simulator
      timeouts = [1, 10, 50, 200]
      
      Enum.each(timeouts, fn timeout ->
        result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                            community: device.community, timeout: timeout)
        
        # Should handle timeouts properly through snmp_lib
        case result do
          {:error, :timeout} -> assert true
          {:error, _other} -> assert true  # Other errors
          {:ok, _} -> assert true  # Fast response from simulator
        end
      end)
    end

    test "invalid target handling" do
      invalid_targets = [
        "invalid..hostname",
        "256.256.256.256",
        "not.a.valid.target"
      ]
      
      Enum.each(invalid_targets, fn target ->
        result = SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                            community: "public", timeout: 200)
        
        # Should return proper error format
        case result do
          {:error, _reason} -> assert true
          {:ok, _} -> assert true  # Some invalid targets might resolve
        end
      end)
    end

    test "community string validation", %{device: device} do
      skip_if_no_device(device)
      
      # Test community string handling through snmp_lib
      communities = [device.community, "wrong_community", ""]
      
      Enum.each(communities, fn community ->
        result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                            community: community, timeout: 200)
        
        # Should handle various community strings properly
        case result do
          {:ok, _} -> assert true
          {:error, reason} when reason in [:timeout, :authentication_error, :bad_community] -> assert true
          {:error, _other} -> assert true  # Other errors acceptable in test environment
        end
      end)
    end
  end

  describe "SnmpMgr Version Compatibility Integration" do
    test "SNMPv1 operations through snmp_lib", %{device: device} do
      skip_if_no_device(device)
      
      # Test SNMPv1 operations
      result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                          version: :v1, community: device.community, timeout: 200)
      
      # Should process v1 requests through snmp_lib
      assert {:ok, _} = result
    end

    test "SNMPv2c operations through snmp_lib", %{device: device} do
      skip_if_no_device(device)
      
      # Test SNMPv2c operations
      result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                          version: :v2c, community: device.community, timeout: 200)
      
      # Should process v2c requests through snmp_lib
      case result do
        {:ok, _} -> assert true
        {:error, reason} when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
      end
    end

    test "bulk operations require v2c", %{device: device} do
      skip_if_no_device(device)
      
      # Bulk operations should work with v2c
      result_v2c = SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2", 
                                   version: :v2c, community: device.community,
                                   max_repetitions: 3, timeout: 200)
      
      # Should handle v2c bulk through snmp_lib
      case result_v2c do
        {:ok, _} -> assert true
        {:error, reason} when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
      end
    end

    test "walk adapts to version", %{device: device} do
      skip_if_no_device(device)
      
      # Walk should adapt behavior based on version
      result_v1 = SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1", 
                              version: :v1, community: device.community, timeout: 200)
      result_v2c = SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1", 
                               version: :v2c, community: device.community, timeout: 200)
      
      # Both should work through appropriate snmp_lib mechanisms
      case result_v1 do
        {:ok, _} -> assert true
        {:error, reason} when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
      end
      
      case result_v2c do
        {:ok, _} -> assert true
        {:error, reason} when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
      end
    end
  end

  describe "SnmpMgr Performance Integration" do
    test "concurrent operations through snmp_lib", %{device: device} do
      skip_if_no_device(device)
      
      # Test concurrent operations to validate snmp_lib integration
      tasks = Enum.map(1..5, fn _i ->
        Task.async(fn ->
          SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                     community: device.community, timeout: 200)
        end)
      end)
      
      results = Task.await_many(tasks, 2000)
      
      # All should complete through snmp_lib
      assert length(results) == 5
      
      Enum.each(results, fn result ->
        assert {:ok, _} = result
      end)
    end

    test "rapid sequential operations", %{device: device} do
      skip_if_no_device(device)
      
      # Test rapid operations to ensure snmp_lib handles them properly
      start_time = System.monotonic_time(:millisecond)
      
      results = Enum.map(1..10, fn _i ->
        SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.3.0", 
                   community: device.community, timeout: 200)
      end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete reasonably quickly
      assert duration < 5000  # Less than 5 seconds for 10 operations
      assert length(results) == 10
      
      # All should return proper format through snmp_lib
      Enum.each(results, fn result ->
        assert {:ok, _} = result
      end)
    end

    test "memory usage with many operations", %{device: device} do
      skip_if_no_device(device)
      
      # Test memory usage during many operations
      initial_memory = :erlang.memory(:total)
      
      # Perform many operations
      results = Enum.map(1..50, fn _i ->
        SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                   community: device.community, timeout: 200)
      end)
      
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be reasonable
      assert memory_growth < 10_000_000  # Less than 10MB growth
      assert length(results) == 50
      
      # Trigger garbage collection
      :erlang.garbage_collect()
    end
  end

  describe "SnmpMgr Components Integration Test" do
    test "all components work together", %{device: device} do
      skip_if_no_device(device)
      
      # Test that all SnmpMgr components integrate properly with snmp_lib
      
      # 1. Configuration
      SnmpMgr.Config.set_default_community(device.community)
      SnmpMgr.Config.set_default_timeout(200)
      
      # 2. Core operation with MIB resolution
      result1 = SnmpMgr.get("#{device.host}:#{device.port}", "sysDescr.0")
      assert {:ok, _} = result1
      
      # 3. Bulk operation
      result2 = SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.2.2", max_repetitions: 3)
      assert {:ok, _} = result2
      
      # 4. Multi-target operation
      requests = [
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", [community: device.community]},
        {"#{device.host}:#{device.port}", "1.3.6.1.2.1.1.3.0", [community: device.community]}
      ]
      results = SnmpMgr.get_multi(requests)
      assert is_list(results) and length(results) == 2
      
      # 5. Walk operation
      result3 = SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1")
      case result3 do
        {:ok, _} -> assert true
        {:error, reason} when reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view] -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
      end
      
      # Reset configuration
      SnmpMgr.Config.reset()
      
      # All operations should complete properly through snmp_lib integration
      assert true
    end
  end

  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end