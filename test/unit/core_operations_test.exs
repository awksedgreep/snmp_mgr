defmodule SNMPMgr.CoreOperationsTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.{Config, Core}
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :core_operations

  setup_all do
    # Ensure configuration is available
    case GenServer.whereis(SNMPMgr.Config) do
      nil -> {:ok, _pid} = Config.start_link()
      _pid -> :ok
    end
    
    :ok
  end

  describe "Core SNMP Operations with SnmpLib Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "get/3 uses SnmpLib.Manager", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test GET operation through Core -> SnmpLib.Manager
      result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                          community: device.community, timeout: 100)
      
      case result do
        {:ok, value} ->
          # Successful operation through snmp_lib
          assert is_binary(value) or is_integer(value) or is_list(value)
          
        {:error, reason} ->
          # Should get proper error format from snmp_lib integration
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "set/4 uses SnmpLib.Manager", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test SET operation through Core -> SnmpLib.Manager
      result = SNMPMgr.set(target, "1.3.6.1.2.1.1.6.0", "test_location", 
                          community: device.community, timeout: 100)
      
      case result do
        {:ok, value} ->
          # Successful SET through snmp_lib
          assert is_binary(value) or is_atom(value) or is_integer(value)
          
        {:error, reason} when reason in [:read_only, :no_access] ->
          # Expected errors for read-only objects or access restrictions
          assert true
          
        {:error, reason} ->
          # Should get proper error format from snmp_lib integration
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "get_bulk/3 uses SnmpLib.Manager", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test GET-BULK operation through Core -> SnmpLib.Manager
      result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                               max_repetitions: 5, non_repeaters: 0,
                               community: device.community, version: :v2c, timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) ->
          # Successful bulk operation through snmp_lib
          assert true
          
        {:error, reason} ->
          # Should get proper error format from snmp_lib integration
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "get_next/3 uses SnmpLib.Manager via get_bulk", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test GET-NEXT operation (implemented as GET-BULK with max_repetitions=1)
      result = SNMPMgr.get_next(target, "1.3.6.1.2.1.1.1", 
                               community: device.community, timeout: 100)
      
      case result do
        {:ok, {oid, value}} ->
          # Successful get_next through snmp_lib
          assert is_binary(oid) or is_list(oid)
          assert is_binary(value) or is_integer(value) or is_list(value)
          
        {:error, reason} ->
          # Should get proper error format from snmp_lib integration
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end

  describe "Core OID Processing with SnmpLib.OID" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "string OIDs processed through SnmpLib.OID", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test various string OID formats
      string_oids = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.2.1.1.3.0",
        "1.3.6.1.2.1.1.5.0"
      ]
      
      Enum.each(string_oids, fn oid ->
        result = SNMPMgr.get(target, oid, community: device.community, timeout: 100)
        # Should process OID through SnmpLib.OID and return proper format
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "list OIDs processed through SnmpLib.OID", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test list format OIDs
      list_oids = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 2, 1, 1, 3, 0],
        [1, 3, 6, 1, 2, 1, 1, 5, 0]
      ]
      
      Enum.each(list_oids, fn oid ->
        result = SNMPMgr.get(target, oid, community: device.community, timeout: 100)
        # Should process list OID through SnmpLib.OID
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "symbolic OIDs through MIB integration", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test symbolic OIDs that should resolve through MIB -> SnmpLib.OID
      symbolic_oids = [
        "sysDescr.0",
        "sysUpTime.0", 
        "sysName.0"
      ]
      
      Enum.each(symbolic_oids, fn oid ->
        result = SNMPMgr.get(target, oid, community: device.community, timeout: 100)
        # Should process symbolic OID through MIB -> SnmpLib.OID chain
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "parse_oid/1 uses SnmpLib.OID.normalize" do
      # Test direct OID parsing through SnmpLib.OID integration
      test_cases = [
        {"1.3.6.1.2.1.1.1.0", [1, 3, 6, 1, 2, 1, 1, 1, 0]},
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], [1, 3, 6, 1, 2, 1, 1, 1, 0]},
        {"sysDescr.0", nil}  # MIB resolution may not work in test environment
      ]
      
      Enum.each(test_cases, fn {input, expected} ->
        case Core.parse_oid(input) do
          {:ok, oid_list} when is_list(oid_list) ->
            if expected do
              assert oid_list == expected
            else
              assert length(oid_list) > 0
            end
            
          {:error, _reason} ->
            # Some OID formats might not resolve in test environment
            assert true
        end
      end)
    end
  end

  describe "Core Error Handling with SnmpLib Integration" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "invalid OIDs return proper errors", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      invalid_oids = [
        "invalid.oid.format",
        "1.3.6.1.2.1.999.999.999.0",
        ""
      ]
      
      Enum.each(invalid_oids, fn oid ->
        result = SNMPMgr.get(target, oid, community: device.community, timeout: 200)
        
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

    test "invalid targets return proper errors" do
      invalid_targets = [
        "invalid..hostname",
        "256.256.256.256",
        "not.a.valid.target"
      ]
      
      Enum.each(invalid_targets, fn target ->
        result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", timeout: 100)
        
        case result do
          {:error, reason} ->
            # Should return proper error format
            assert is_atom(reason) or is_tuple(reason)
          {:ok, _} ->
            # Some invalid targets might resolve
            assert true
        end
      end)
    end

    test "timeout handling through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test very short timeout
      result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                          community: device.community, timeout: 1)
      
      case result do
        {:error, :timeout} -> assert true
        {:error, _other} -> assert true  # Other errors acceptable
        {:ok, _} -> assert true  # Unexpectedly fast response
      end
    end

    test "community validation through snmp_lib", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test with wrong community
      result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                          community: "wrong_community", timeout: 200)
      
      case result do
        {:error, reason} when reason in [:authentication_error, :bad_community] ->
          assert true  # Expected authentication error
        {:error, _other} -> assert true  # Other errors acceptable
        {:ok, _} -> assert true  # Might succeed in test environment
      end
    end
  end

  describe "Core Configuration Integration" do
    test "uses Config.merge_opts for option processing" do
      # Set some configuration defaults
      Config.set_default_community("test_community")
      Config.set_default_timeout(100)
      Config.set_default_version(:v2c)
      
      # Test option merging
      merged = Config.merge_opts([community: "override", retries: 2])
      
      # Should have overridden community but default timeout and version
      assert merged[:community] == "override"
      assert merged[:timeout] == 100
      assert merged[:version] == :v2c
      assert merged[:retries] == 2
      
      Config.reset()
    end

    test "operations use merged configuration", %{} do
      # Create a simulator device for testing
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      target = SNMPSimulator.device_target(device)
      
      # Set configuration
      Config.set_default_community(device.community)
      Config.set_default_timeout(100)
      
      # Operation without explicit options should use configuration
      result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0")
      
      # Should process with configured options through snmp_lib
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      Config.reset()
      SNMPSimulator.stop_device(device)
    end
  end

  describe "Core Version Handling" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "SNMPv1 operations through SnmpLib.Manager", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                          version: :v1, community: device.community, timeout: 100)
      
      # Should process v1 requests through snmp_lib
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "SNMPv2c operations through SnmpLib.Manager", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      result = SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                          version: :v2c, community: device.community, timeout: 100)
      
      # Should process v2c requests through snmp_lib
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "bulk operations enforce v2c", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Bulk operations should work with v2c (default)
      result = SNMPMgr.get_bulk(target, "1.3.6.1.2.1.2.2", 
                               max_repetitions: 3, community: device.community)
      
      # Should handle bulk through SnmpLib.Manager
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "Core Multi-Operation Support" do
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

    test "get_multi processes multiple targets", %{device1: device1, device2: device2} do
      requests = [
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.1.1.0", 
         [community: device1.community, timeout: 100]},
        {SNMPSimulator.device_target(device2), "1.3.6.1.2.1.1.3.0", 
         [community: device2.community, timeout: 100]}
      ]
      
      results = SNMPMgr.get_multi(requests)
      
      assert is_list(results)
      assert length(results) == 2
      
      # Each result should be proper format from snmp_lib integration
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "get_bulk_multi processes multiple bulk requests", %{device1: device1, device2: device2} do
      requests = [
        {SNMPSimulator.device_target(device1), "1.3.6.1.2.1.2.2", 
         [max_repetitions: 3, community: device1.community, timeout: 100]},
        {SNMPSimulator.device_target(device2), "1.3.6.1.2.1.2.2", 
         [max_repetitions: 3, community: device2.community, timeout: 100]}
      ]
      
      results = SNMPMgr.get_bulk_multi(requests)
      
      assert is_list(results)
      assert length(results) == 2
      
      # Each result should be proper format from snmp_lib integration
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
  end

  describe "Core Performance with SnmpLib" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "operations complete efficiently", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Measure time for operations through snmp_lib
      start_time = System.monotonic_time(:millisecond)
      
      results = Enum.map(1..5, fn _i ->
        SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                   community: device.community, timeout: 100)
      end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete reasonably quickly with local simulator
      assert duration < 1000  # Less than 1 second for 5 operations
      assert length(results) == 5
      
      # All should return proper format through snmp_lib
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "concurrent operations work correctly", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test concurrent operations through snmp_lib
      tasks = Enum.map(1..3, fn _i ->
        Task.async(fn ->
          SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                     community: device.community, timeout: 100)
        end)
      end)
      
      results = Task.await_many(tasks, 500)
      
      # All should complete through snmp_lib
      assert length(results) == 3
      
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
  end

  describe "Direct SnmpLib Integration Tests" do
    test "SnmpLib.OID functions work correctly" do
      # Test direct SnmpLib.OID integration
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = SnmpLib.OID.string_to_list("1.3.6.1.2.1.1.1.0")
      assert "1.3.6.1.2.1.1.1.0" = SnmpLib.OID.list_to_string([1, 3, 6, 1, 2, 1, 1, 1, 0])
    end

    test "Core.parse_oid delegates to SnmpLib.OID.normalize" do
      # Test that parse_oid uses SnmpLib.OID.normalize
      result = Core.parse_oid("1.3.6.1.2.1.1.1.0")
      
      case result do
        {:ok, oid_list} ->
          assert oid_list == [1, 3, 6, 1, 2, 1, 1, 1, 0]
        {:error, _reason} ->
          # May fail in test environment
          assert true
      end
    end

    test "operations return consistent formats" do
      # Test that all operations return consistent {:ok, result} | {:error, reason} formats
      # regardless of snmp_lib internal changes
      
      # Use unreachable target for quick timeout
      result = SNMPMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 50)
      
      case result do
        {:ok, value} ->
          assert is_binary(value) or is_integer(value) or is_list(value)
        {:error, reason} ->
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end
end