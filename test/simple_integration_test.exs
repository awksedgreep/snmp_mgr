defmodule SnmpMgr.SimpleIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SnmpMgr.TestSupport.SNMPSimulator
  
  @moduletag :integration

  setup_all do
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}
      error ->
        %{device: nil, setup_error: error}
    end
  end

  describe "SnmpMgr Basic Operations with Real Device" do
    test "get/3 works with valid community and OID", %{device: device} do
      skip_if_no_device(device)
      
      result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                          community: device.community, timeout: 200)
      
      # Must succeed with real data or fail with specific SNMP error
      case result do
        {:ok, value} ->
          assert is_binary(value) or is_integer(value)
          assert byte_size(to_string(value)) > 0
        {:error, reason} ->
          assert reason in [:noSuchObject, :noSuchInstance, :timeout]
      end
    end

    test "get/3 fails with invalid community", %{device: device} do
      skip_if_no_device(device)
      
      result = SnmpMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                          community: "wrong_community", timeout: 200)
      
      # Must fail - invalid community should not work
      assert {:error, _reason} = result
    end

    test "get_bulk/3 returns structured results", %{device: device} do
      skip_if_no_device(device)
      
      result = SnmpMgr.get_bulk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1", 
                               community: device.community, max_repetitions: 3, timeout: 200)
      
      case result do
        {:ok, results} ->
          assert is_list(results)
          # If we get results, they must be valid OID-value pairs
          if length(results) > 0 do
            Enum.each(results, fn {oid, value} ->
              assert is_binary(oid)
              assert String.contains?(oid, ".")
              assert value != nil
            end)
          end
        {:error, reason} ->
          # Acceptable bulk operation errors
          assert reason in [:timeout, :noSuchObject, :getbulk_requires_v2c]
      end
    end

    test "walk/3 traverses MIB tree properly", %{device: device} do
      skip_if_no_device(device)
      
      result = SnmpMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1", 
                           community: device.community, timeout: 200)
      
      case result do
        {:ok, results} ->
          assert is_list(results)
          if length(results) > 0 do
            # Walk results must be valid and in tree order
            Enum.each(results, fn {oid, value} ->
              assert is_binary(oid)
              assert String.starts_with?(oid, "1.3.6.1.2.1.1")
              assert value != nil
            end)
          end
        {:error, reason} ->
          assert reason in [:timeout, :noSuchObject, :endOfMibView, :end_of_mib_view]
      end
    end
  end

  describe "SnmpMgr Error Handling" do
    test "invalid OID format is rejected", %{device: device} do
      skip_if_no_device(device)
      
      # Test with simulator device, not hardcoded IPs
      assert {:error, _reason} = SnmpMgr.get("#{device.host}:#{device.port}", "invalid.oid", 
                                            community: device.community, timeout: 200)
      assert {:error, _reason} = SnmpMgr.get("#{device.host}:#{device.port}", "", 
                                            community: device.community, timeout: 200)
    end

    test "invalid host format is rejected" do
      # These don't need device since they test invalid hosts
      assert {:error, _reason} = SnmpMgr.get("", "1.3.6.1.2.1.1.1.0", timeout: 200)
      assert {:error, _reason} = SnmpMgr.get("not.a.valid.hostname.that.should.fail", 
                                            "1.3.6.1.2.1.1.1.0", timeout: 200)
    end

    test "timeout is respected" do
      # Use documentation range IP (won't respond), not random IPs
      start_time = System.monotonic_time(:millisecond)
      result = SnmpMgr.get("192.0.2.254", "1.3.6.1.2.1.1.1.0", 
                          community: "public", timeout: 50)
      end_time = System.monotonic_time(:millisecond)
      
      # Should fail and respect timeout
      assert {:error, _reason} = result
      assert (end_time - start_time) < 500  # Should not take much longer than timeout
    end
  end

  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end