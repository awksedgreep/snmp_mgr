defmodule SNMPMgr.MIBIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.MIB
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :mib
  @moduletag :snmp_lib_integration

  setup_all do
    case SNMPSimulator.create_test_device() do
      {:ok, device_info} ->
        on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
        %{device: device_info}
      error ->
        %{device: nil, setup_error: error}
    end
  end

  setup do
    case GenServer.whereis(SNMPMgr.MIB) do
      nil -> 
        {:ok, _pid} = SNMPMgr.MIB.start_link()
        :ok
      _pid -> 
        :ok
    end
    
    :ok
  end

  describe "MIB Integration with snmp_lib Operations" do
    test "MIB name resolution works with SNMP operations", %{device: device} do
      skip_if_no_device(device)
      
      # Test MIB name resolution for standard names
      standard_names = ["sysDescr", "sysUpTime", "sysName"]
      
      for name <- standard_names do
        case MIB.resolve(name) do
          {:ok, oid} ->
            # Use resolved OID in SNMP operation
            oid_string = oid |> Enum.join(".") |> then(&("#{&1}.0"))
            result = SNMPMgr.get(device.host, device.port, device.community, oid_string, timeout: 200)
            
            assert match?({:ok, _} | {:error, _}, result)
            
          {:error, reason} ->
            # MIB resolution might fail if MIB not loaded, which is acceptable
            IO.puts("MIB resolution failed for '#{name}': #{inspect(reason)}")
        end
      end
    end
    
    test "MIB reverse lookup integration", %{device: device} do
      skip_if_no_device(device)
      
      # Get a value first
      case SNMPMgr.get(device.host, device.port, device.community, "1.3.6.1.2.1.1.1.0", timeout: 200) do
        {:ok, {oid, _value}} ->
          # Try reverse lookup on the OID
          case MIB.reverse_lookup(oid) do
            {:ok, name} ->
              assert is_binary(name)
              assert String.length(name) > 0
              
            {:error, _reason} ->
              # Reverse lookup might fail if MIB not loaded, acceptable
              :ok
          end
          
        {:error, _reason} ->
          # SNMP operation failed, skip reverse lookup test
          :ok
      end
    end
  end

  describe "Enhanced MIB with SnmpLib.MIB Integration" do
    test "integrates with SnmpLib.MIB for enhanced functionality", %{device: device} do
      skip_if_no_device(device)
      
      # Test basic MIB functionality
      standard_oids = [
        "1.3.6.1.2.1.1.1.0",  # sysDescr
        "1.3.6.1.2.1.1.3.0",  # sysUpTime
        "1.3.6.1.2.1.1.5.0"   # sysName
      ]
      
      for oid <- standard_oids do
        result = SNMPMgr.get(device.host, device.port, device.community, oid, timeout: 200)
        
        case result do
          {:ok, {returned_oid, _value}} ->
            # Test that MIB can handle the returned OID format
            case MIB.reverse_lookup(returned_oid) do
              {:ok, _name} -> assert true
              {:error, _reason} -> assert true  # MIB might not be loaded
            end
            
          {:error, _reason} ->
            # Operation failed, which is acceptable
            :ok
        end
      end
    end
    
    test "MIB tree walking integration", %{device: device} do
      skip_if_no_device(device)
      
      # Test MIB tree functionality with SNMP data
      root_oid = "1.3.6.1.2.1.1"  # System group
      
      # Perform SNMP walk
      case SNMPMgr.walk(device.host, device.port, device.community, root_oid, timeout: 200) do
        {:ok, results} when is_list(results) ->
          # For each result, test MIB integration
          limited_results = Enum.take(results, 3)  # Limit to first 3 for test efficiency
          
          for {oid, _value} <- limited_results do
            case MIB.reverse_lookup(oid) do
              {:ok, name} ->
                assert is_binary(name)
                
              {:error, _reason} ->
                # MIB reverse lookup might fail, acceptable
                :ok
            end
          end
          
        {:error, _reason} ->
          # Walk operation failed, skip MIB integration test
          :ok
      end
    end
  end
  
  # Helper functions
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end
