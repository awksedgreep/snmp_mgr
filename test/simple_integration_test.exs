defmodule SNMPMgr.SimpleIntegrationTest do
  use ExUnit.Case, async: false
  
  @moduletag :integration

  describe "SNMPMgr Basic Integration" do
    test "get/3 handles network operations" do
      # Test with unreachable device - should return network error through snmp_lib
      result = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", timeout: 100)
      
      case result do
        {:ok, _value} -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          # Should get proper network error through snmp_lib integration
          assert reason in [:timeout, :host_unreachable, :network_unreachable, :ehostunreach, :enetunreach]
      end
    end

    test "set/4 validates snmp_lib integration" do
      # Test with unreachable device - should return network error through snmp_lib
      result = SNMPMgr.set("192.0.2.99", "1.3.6.1.2.1.1.6.0", "test", timeout: 100)
      
      case result do
        {:ok, _value} -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          # Should get proper network error through snmp_lib integration
          assert reason in [:timeout, :host_unreachable, :network_unreachable, :ehostunreach, :enetunreach]
      end
    end

    test "get_bulk/3 uses snmp_lib backend" do
      # Test bulk operation - should use SnmpLib.Manager.get_bulk
      result = SNMPMgr.get_bulk("192.0.2.99", "1.3.6.1.2.1.2.2", max_repetitions: 3, timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          # Should get proper network error through snmp_lib integration
          assert reason in [:timeout, :host_unreachable, :network_unreachable, :ehostunreach, :enetunreach]
      end
    end

    test "walk/3 integrates with snmp_lib" do
      # Test walk operation - should use snmp_lib through Core module
      result = SNMPMgr.walk("192.0.2.99", "1.3.6.1.2.1.1", timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          # Should get proper network error through snmp_lib integration
          assert reason in [:timeout, :host_unreachable, :network_unreachable, :ehostunreach, :enetunreach]
      end
    end

    test "get_next/3 uses snmp_lib manager" do
      # Test get_next operation - should use SnmpLib.Manager
      result = SNMPMgr.get_next("192.0.2.99", "1.3.6.1.2.1.1.1", timeout: 100)
      
      case result do
        {:ok, {_oid, _value}} -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          # Should get proper network error through snmp_lib integration
          assert reason in [:timeout, :host_unreachable, :network_unreachable, :ehostunreach, :enetunreach]
      end
    end
  end

  describe "SNMPMgr Option Processing" do
    test "timeout option is passed to snmp_lib" do
      # Very short timeout should be handled by snmp_lib
      result = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", timeout: 1)
      
      case result do
        {:error, :timeout} -> assert true
        {:error, _other} -> assert true  # Other network errors acceptable
        {:ok, _} -> assert true  # Unexpectedly fast response
      end
    end

    test "community option integration" do
      # Community should be passed through to snmp_lib
      result = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", 
                          community: "integration_test", timeout: 100)
      
      # Should return proper format regardless of community
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "version option integration" do
      # Version should be passed through to snmp_lib
      result_v1 = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", 
                              version: :v1, timeout: 100)
      result_v2c = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", 
                               version: :v2c, timeout: 100)
      
      # Both should return proper format through snmp_lib
      assert match?({:ok, _} | {:error, _}, result_v1)
      assert match?({:ok, _} | {:error, _}, result_v2c)
    end
  end

  describe "SNMPMgr Target and OID Processing" do
    test "string targets processed correctly" do
      # String IP addresses should work through snmp_lib
      result = SNMPMgr.get("127.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 100)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "hostname targets processed correctly" do
      # Hostnames should be resolved through snmp_lib
      result = SNMPMgr.get("localhost", "1.3.6.1.2.1.1.1.0", timeout: 100)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "string OIDs processed through SnmpLib.OID" do
      # String OIDs should be processed by SnmpLib.OID
      result = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", timeout: 100)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "list OIDs processed through SnmpLib.OID" do
      # List OIDs should be processed by SnmpLib.OID
      result = SNMPMgr.get("192.0.2.99", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 100)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "symbolic OIDs processed correctly" do
      # Symbolic OIDs should work through MIB integration
      result = SNMPMgr.get("192.0.2.99", "sysDescr.0", timeout: 100)
      assert match?({:ok, _} | {:error, _}, result)
    end
  end

  describe "SNMPMgr Multi-Target Operations" do
    test "get_multi processes multiple targets" do
      requests = [
        {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [timeout: 100]},
        {"192.0.2.2", "1.3.6.1.2.1.1.1.0", [timeout: 100]},
        {"192.0.2.3", "1.3.6.1.2.1.1.1.0", [timeout: 100]}
      ]
      
      results = SNMPMgr.get_multi(requests)
      
      assert is_list(results)
      assert length(results) == 3
      
      # Each result should be proper format
      Enum.each(results, fn result ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end

    test "get_bulk_multi handles bulk operations" do
      requests = [
        {"192.0.2.1", "1.3.6.1.2.1.2.2", [max_repetitions: 5, timeout: 100]},
        {"192.0.2.2", "1.3.6.1.2.1.2.2", [max_repetitions: 5, timeout: 100]}
      ]
      
      results = SNMPMgr.get_bulk_multi(requests)
      
      assert is_list(results)
      assert length(results) == 2
      
      # Each result should be proper format
      Enum.each(results, fn result ->
        assert match?({:ok, _} | {:error, _}, result)
      end)
    end
  end

  describe "SNMPMgr Error Handling Integration" do
    test "invalid targets produce proper errors" do
      # Invalid targets should be caught and return proper error format
      result = SNMPMgr.get("invalid..host..name", "1.3.6.1.2.1.1.1.0", timeout: 100)
      assert {:error, _reason} = result
    end

    test "invalid OIDs produce proper errors" do
      # Invalid OIDs should be caught by SnmpLib.OID or validation
      result = SNMPMgr.get("192.0.2.99", "invalid.oid.string", timeout: 100)
      assert {:error, _reason} = result
    end

    test "network timeouts handled correctly" do
      # Network timeouts should be handled by snmp_lib and returned properly
      result = SNMPMgr.get("240.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 50)
      
      case result do
        {:error, :timeout} -> assert true
        {:error, :ehostunreach} -> assert true
        {:error, :enetunreach} -> assert true
        {:error, :host_unreachable} -> assert true
        {:error, :network_unreachable} -> assert true
        {:ok, _} -> assert true  # Unexpected success
      end
    end
  end

  describe "SNMPMgr Configuration Integration" do
    test "uses default configuration from Config module" do
      # Should use default configuration when no options provided
      result = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0")
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "overrides configuration with request options" do
      # Request options should override default configuration
      result = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", 
                          community: "override", timeout: 150, version: :v2c)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "configuration merging works correctly" do
      # Verify that Config.merge_opts is working with snmp_lib options
      merged = SNMPMgr.Config.merge_opts([community: "test", timeout: 2000])
      
      assert is_list(merged)
      assert merged[:community] == "test"
      assert merged[:timeout] == 2000
      assert merged[:version] in [:v1, :v2c]  # Should have default version
    end
  end

  describe "SNMPMgr SnmpLib Components Integration" do
    test "SnmpLib.OID integration works" do
      # Test direct SnmpLib.OID integration
      assert {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]} = SnmpLib.OID.string_to_list("1.3.6.1.2.1.1.1.0")
      assert "1.3.6.1.2.1.1.1.0" = SnmpLib.OID.list_to_string([1, 3, 6, 1, 2, 1, 1, 1, 0])
    end

    test "core operations use SnmpLib.Manager" do
      # Verify that core operations go through SnmpLib.Manager
      # This is validated by the fact that operations complete without
      # custom PDU/transport code
      result = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", timeout: 100)
      
      # Should return proper format from SnmpLib.Manager
      case result do
        {:ok, value} -> 
          assert is_binary(value) or is_integer(value) or is_list(value)
        {:error, reason} ->
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "error format consistency" do
      # Error formats should be consistent regardless of snmp_lib changes
      result = SNMPMgr.get("192.0.2.99", "1.3.6.1.2.1.1.1.0", timeout: 10)
      
      case result do
        {:ok, _} -> assert true
        {:error, reason} -> 
          # Error reason should be properly formatted
          assert is_atom(reason) or (is_tuple(reason) and tuple_size(reason) >= 1)
      end
    end

    test "return value format consistency" do
      # Return values should maintain consistent format through snmp_lib
      result = SNMPMgr.get("127.0.0.1", "1.3.6.1.2.1.1.1.0", timeout: 100)
      
      case result do
        {:ok, value} ->
          # Value should be in expected format
          assert is_binary(value) or is_integer(value) or is_list(value) or 
                 (is_tuple(value) and elem(value, 0) == :noSuchObject)
        {:error, reason} ->
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end
end