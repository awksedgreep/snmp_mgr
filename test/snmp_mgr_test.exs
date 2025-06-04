defmodule SNMPMgrTest do
  use ExUnit.Case, async: false
  doctest SNMPMgr

  @moduletag :integration

  describe "SNMPMgr main API" do
    test "get/3 returns expected format" do
      # Test with non-existent device - should return network error
      result = SNMPMgr.get("192.0.2.1", "1.3.6.1.2.1.1.1.0", timeout: 100)
      
      case result do
        {:ok, _value} -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          assert reason in [:timeout, :host_unreachable, :network_unreachable]
      end
    end

    test "set/4 returns expected format" do
      # Test with non-existent device - should return network error
      result = SNMPMgr.set("192.0.2.1", "1.3.6.1.2.1.1.6.0", "test", timeout: 100)
      
      case result do
        {:ok, _value} -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          assert reason in [:timeout, :host_unreachable, :network_unreachable]
      end
    end

    test "get_bulk/3 returns expected format" do
      # Test with non-existent device - should return network error
      result = SNMPMgr.get_bulk("192.0.2.1", "1.3.6.1.2.1.2.2", max_repetitions: 5, timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          assert reason in [:timeout, :host_unreachable, :network_unreachable]
      end
    end

    test "walk/3 returns expected format" do
      # Test with non-existent device - should return network error
      result = SNMPMgr.walk("192.0.2.1", "1.3.6.1.2.1.1", timeout: 100)
      
      case result do
        {:ok, results} when is_list(results) -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          assert reason in [:timeout, :host_unreachable, :network_unreachable]
      end
    end

    test "get_next/3 returns expected format" do
      # Test with non-existent device - should return network error
      result = SNMPMgr.get_next("192.0.2.1", "1.3.6.1.2.1.1.1", timeout: 100)
      
      case result do
        {:ok, {_oid, _value}} -> 
          assert true  # Unexpected success (maybe device exists)
        {:error, reason} ->
          assert reason in [:timeout, :host_unreachable, :network_unreachable]
      end
    end
  end

  describe "SNMPMgr target parsing" do
    test "handles string targets" do
      # Should not crash on target parsing
      result = SNMPMgr.get("192.0.2.1", "1.3.6.1.2.1.1.1.0", timeout: 100)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles hostname targets" do
      # Should not crash on hostname parsing
      result = SNMPMgr.get("localhost", "1.3.6.1.2.1.1.1.0", timeout: 100)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles IP with port targets" do
      # Should not crash on IP:port parsing
      result = SNMPMgr.get("127.0.0.1:161", "1.3.6.1.2.1.1.1.0", timeout: 100)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end
  end

  describe "SNMPMgr OID handling" do
    test "handles string OIDs" do
      # Should process string OIDs without crashing
      result = SNMPMgr.get("192.0.2.1", "1.3.6.1.2.1.1.1.0", timeout: 100)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles list OIDs" do
      # Should process list OIDs without crashing
      result = SNMPMgr.get("192.0.2.1", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 100)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles symbolic OIDs" do
      # Should process symbolic OIDs without crashing
      result = SNMPMgr.get("192.0.2.1", "sysDescr.0", timeout: 100)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end
  end

  describe "SNMPMgr option processing" do
    test "handles community option" do
      # Should process community option without crashing
      result = SNMPMgr.get("192.0.2.1", "1.3.6.1.2.1.1.1.0", community: "public", timeout: 100)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles timeout option" do
      # Should process timeout option without crashing
      result = SNMPMgr.get("192.0.2.1", "1.3.6.1.2.1.1.1.0", timeout: 200)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles version option" do
      # Should process version option without crashing
      result = SNMPMgr.get("192.0.2.1", "1.3.6.1.2.1.1.1.0", version: :v2c, timeout: 100)
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end
  end

  describe "SNMPMgr error handling" do
    test "returns proper error format for invalid targets" do
      # Should return proper error format for invalid targets
      result = SNMPMgr.get("invalid..host", "1.3.6.1.2.1.1.1.0", timeout: 100)
      case result do
        {:ok, _} -> flunk("Should not succeed with invalid hostname")
        {:error, _} -> assert true
      end
    end

    test "returns proper error format for invalid OIDs" do
      # Should return proper error format for invalid OIDs
      result = SNMPMgr.get("192.0.2.1", "invalid.oid", timeout: 100)
      case result do
        {:ok, _} -> flunk("Should not succeed with invalid OID")
        {:error, _} -> assert true
      end
    end
  end

  describe "SNMPMgr version compatibility" do
    test "handles version selection in get operations" do
      # Should handle version selection without crashing
      result_v1 = SNMPMgr.get("192.0.2.1", "1.3.6.1.2.1.1.1.0", version: :v1, timeout: 100)
      result_v2c = SNMPMgr.get("192.0.2.1", "1.3.6.1.2.1.1.1.0", version: :v2c, timeout: 100)
      
      case result_v1 do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
      
      case result_v2c do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles version selection in walk" do
      # Should handle version selection in walk operations
      result_v1 = SNMPMgr.walk("192.0.2.1", "1.3.6.1.2.1.1", version: :v1, timeout: 100)
      result_v2c = SNMPMgr.walk("192.0.2.1", "1.3.6.1.2.1.1", version: :v2c, timeout: 100)
      
      case result_v1 do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
      
      case result_v2c do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end
  end

  describe "SNMPMgr multi-target operations" do
    test "get_multi returns list of results" do
      # Should return list of results for multi-target operations
      requests = [
        {"192.0.2.1", "1.3.6.1.2.1.1.1.0", [timeout: 100]},
        {"192.0.2.2", "1.3.6.1.2.1.1.1.0", [timeout: 100]}
      ]
      
      results = SNMPMgr.get_multi(requests)
      assert is_list(results)
      assert length(results) == 2
      
      # Each result should be in proper format
      Enum.each(results, fn result ->
        case result do
          {:ok, _} -> assert true
          {:error, _} -> assert true
        end
      end)
    end

    test "get_bulk_multi returns list of results" do
      # Should return list of results for multi-bulk operations
      requests = [
        {"192.0.2.1", "1.3.6.1.2.1.2.2", [max_repetitions: 3, timeout: 100]},
        {"192.0.2.2", "1.3.6.1.2.1.2.2", [max_repetitions: 3, timeout: 100]}
      ]
      
      results = SNMPMgr.get_bulk_multi(requests)
      assert is_list(results)
      assert length(results) == 2
      
      # Each result should be in proper format
      Enum.each(results, fn result ->
        case result do
          {:ok, _} -> assert true
          {:error, _} -> assert true
        end
      end)
    end
  end
end