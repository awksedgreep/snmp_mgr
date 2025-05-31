defmodule SNMPMgr.SimpleIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :integration
  
  setup_all do
    # Start the simulator application if needed
    case Application.ensure_all_started(:snmp_sim_ex) do
      {:ok, _} -> :ok
      {:error, _} -> 
        # SNMPSimEx might not be available in all environments
        ExUnit.configure(exclude: [:integration])
    end
    
    :ok
  end

  describe "Basic Device Creation" do
    test "can create a test device" do
      {:ok, device_info} = SNMPSimulator.create_test_device()
      assert device_info.host == "127.0.0.1"
      assert is_integer(device_info.port)
      assert device_info.community == "public"
      assert device_info.device_type == :test_device
      assert is_pid(device_info.device)
      
      # Clean up
      SNMPSimulator.stop_device(device_info)
    end
    
    test "can create a switch device" do
      {:ok, device_info} = SNMPSimulator.create_switch_device(interface_count: 12)
      assert device_info.host == "127.0.0.1"
      assert is_integer(device_info.port)
      assert device_info.community == "public"
      assert device_info.device_type == :switch
      assert device_info.interface_count == 12
      assert is_pid(device_info.device)
      
      # Clean up
      SNMPSimulator.stop_device(device_info)
    end
    
    test "can create a router device" do
      {:ok, device_info} = SNMPSimulator.create_router_device(route_count: 50)
      assert device_info.host == "127.0.0.1"
      assert is_integer(device_info.port)
      assert device_info.community == "public"
      assert device_info.device_type == :router
      assert device_info.route_count == 50
      assert is_pid(device_info.device)
      
      # Clean up
      SNMPSimulator.stop_device(device_info)
    end
    
    test "devices can be configured with custom settings" do
      {:ok, device_info} = SNMPSimulator.create_test_device(
        port: 30500,
        community: "private",
        device_type: :custom_test
      )
      
      assert device_info.port == 30500
      assert device_info.community == "private"
      assert device_info.device_type == :custom_test
      
      # Clean up
      SNMPSimulator.stop_device(device_info)
    end
    
    test "device target generation works" do
      {:ok, device_info} = SNMPSimulator.create_test_device()
      target = SNMPSimulator.device_target(device_info)
      
      assert target == "#{device_info.host}:#{device_info.port}"
      
      # Clean up
      SNMPSimulator.stop_device(device_info)
    end
  end
  
  describe "Device Fleet Creation" do
    test "can create multiple devices" do
      {:ok, devices} = SNMPSimulator.create_device_fleet(count: 3, device_type: :test_device)
      
      assert length(devices) == 3
      
      # All devices should have different ports
      ports = Enum.map(devices, & &1.port)
      assert length(Enum.uniq(ports)) == 3
      
      # All devices should be running
      Enum.each(devices, fn device ->
        assert is_pid(device.device)
        assert device.device_type == :test_device
      end)
      
      # Clean up
      SNMPSimulator.stop_devices(devices)
    end
    
    test "fleet with mixed device types" do
      # Create some devices manually to test mixed types
      {:ok, device1} = SNMPSimulator.create_test_device()
      {:ok, device2} = SNMPSimulator.create_switch_device()
      {:ok, device3} = SNMPSimulator.create_router_device()
      
      devices = [device1, device2, device3]
      
      device_types = Enum.map(devices, & &1.device_type)
      assert :test_device in device_types
      assert :switch in device_types
      assert :router in device_types
      
      # Clean up
      SNMPSimulator.stop_devices(devices)
    end
  end
  
  describe "Device Information" do
    test "device info contains required fields" do
      {:ok, device_info} = SNMPSimulator.create_test_device()
      
      # Required fields should be present
      required_fields = [:device, :host, :port, :community, :device_type]
      Enum.each(required_fields, fn field ->
        assert Map.has_key?(device_info, field), "Missing field: #{field}"
      end)
      
      # Values should be correct types
      assert is_pid(device_info.device)
      assert is_binary(device_info.host)
      assert is_integer(device_info.port)
      assert is_binary(device_info.community)
      assert is_atom(device_info.device_type)
      
      # Clean up
      SNMPSimulator.stop_device(device_info)
    end
  end
end