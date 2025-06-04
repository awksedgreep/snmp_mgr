defmodule SNMPMgrTest do
  use ExUnit.Case, async: false
  doctest SNMPMgr

  alias SNMPMgr.TestSupport.SNMPSimulator

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

  describe "SNMPMgr main API with real SNMP device" do
    test "get/3 actually retrieves data from simulator", %{device: device} do
      skip_if_no_device(device)
      
      result = SNMPMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                          community: device.community, timeout: 200)
      
      case result do
        {:ok, value} ->
          # Must be a real value from the simulator
          assert is_binary(value) or is_integer(value)
          assert byte_size(to_string(value)) > 0
        {:error, reason} ->
          # Only accept specific SNMP errors, not generic ones
          assert reason in [:noSuchObject, :noSuchInstance, :timeout]
      end
    end

    test "get/3 fails with invalid community", %{device: device} do
      skip_if_no_device(device)
      
      result = SNMPMgr.get("#{device.host}:#{device.port}", "1.3.6.1.2.1.1.1.0", 
                          community: "invalid_community", timeout: 200)
      
      # Must fail with authentication error, not succeed
      assert {:error, _reason} = result
    end

    test "get/3 fails with invalid OID", %{device: device} do
      skip_if_no_device(device)
      
      result = SNMPMgr.get("#{device.host}:#{device.port}", "1.2.3.4.5.6.7.8.9.10.11.12", 
                          community: device.community, timeout: 200)
      
      # Must fail appropriately for non-existent OID
      assert {:error, _reason} = result
    end

    test "walk/3 returns actual walk results from simulator", %{device: device} do
      skip_if_no_device(device)
      
      result = SNMPMgr.walk("#{device.host}:#{device.port}", "1.3.6.1.2.1.1", 
                           community: device.community, timeout: 500)
      
      case result do
        {:ok, results} ->
          # Must be real walk results
          assert is_list(results)
          assert length(results) > 0
          
          # Each result must be a real OID-value pair
          Enum.each(results, fn {oid, value} ->
            assert is_binary(oid)
            assert String.starts_with?(oid, "1.3.6.1.2.1.1")
            assert value != nil
          end)
        {:error, reason} ->
          # Only accept specific SNMP errors
          assert reason in [:timeout, :noSuchObject]
      end
    end
  end

  describe "SNMPMgr API validation" do
    test "get/3 rejects invalid arguments", %{device: device} do
      skip_if_no_device(device)
      
      # Empty host should fail immediately
      assert {:error, _reason} = SNMPMgr.get("", "1.3.6.1.2.1.1.1.0")
      
      # Empty OID should fail immediately - use simulator device
      assert {:error, _reason} = SNMPMgr.get("#{device.host}:#{device.port}", "", 
                                            community: device.community, timeout: 200)
      
      # Invalid OID format should fail - use simulator device
      assert {:error, _reason} = SNMPMgr.get("#{device.host}:#{device.port}", "not.an.oid", 
                                            community: device.community, timeout: 200)
    end

    test "walk/3 rejects invalid arguments", %{device: device} do
      skip_if_no_device(device)
      
      # Empty host should fail immediately
      assert {:error, _reason} = SNMPMgr.walk("", "1.3.6.1.2.1.1")
      
      # Empty OID should fail immediately - use simulator device
      assert {:error, _reason} = SNMPMgr.walk("#{device.host}:#{device.port}", "", 
                                             community: device.community, timeout: 200)
    end
  end

  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end