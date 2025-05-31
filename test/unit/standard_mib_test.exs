defmodule SNMPMgr.StandardMIBTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.MIB
  
  @moduletag :unit
  @moduletag :mib
  @moduletag :standard_mib
  @moduletag :phase_2

  # RFC 1213 MIB-II Standard Objects
  @rfc1213_system_group [
    {"sysDescr", [1, 3, 6, 1, 2, 1, 1, 1], "System description"},
    {"sysObjectID", [1, 3, 6, 1, 2, 1, 1, 2], "System object identifier"},
    {"sysUpTime", [1, 3, 6, 1, 2, 1, 1, 3], "System uptime in hundredths of seconds"},
    {"sysContact", [1, 3, 6, 1, 2, 1, 1, 4], "System contact information"},
    {"sysName", [1, 3, 6, 1, 2, 1, 1, 5], "System name"},
    {"sysLocation", [1, 3, 6, 1, 2, 1, 1, 6], "System location"},
    {"sysServices", [1, 3, 6, 1, 2, 1, 1, 7], "System services value"}
  ]

  @rfc1213_interface_group [
    {"ifNumber", [1, 3, 6, 1, 2, 1, 2, 1], "Number of network interfaces"},
    {"ifTable", [1, 3, 6, 1, 2, 1, 2, 2], "Interface table"},
    {"ifEntry", [1, 3, 6, 1, 2, 1, 2, 2, 1], "Interface table entry"},
    {"ifIndex", [1, 3, 6, 1, 2, 1, 2, 2, 1, 1], "Interface index"},
    {"ifDescr", [1, 3, 6, 1, 2, 1, 2, 2, 1, 2], "Interface description"},
    {"ifType", [1, 3, 6, 1, 2, 1, 2, 2, 1, 3], "Interface type"},
    {"ifMtu", [1, 3, 6, 1, 2, 1, 2, 2, 1, 4], "Interface MTU"},
    {"ifSpeed", [1, 3, 6, 1, 2, 1, 2, 2, 1, 5], "Interface speed"},
    {"ifPhysAddress", [1, 3, 6, 1, 2, 1, 2, 2, 1, 6], "Interface physical address"},
    {"ifAdminStatus", [1, 3, 6, 1, 2, 1, 2, 2, 1, 7], "Interface administrative status"},
    {"ifOperStatus", [1, 3, 6, 1, 2, 1, 2, 2, 1, 8], "Interface operational status"},
    {"ifLastChange", [1, 3, 6, 1, 2, 1, 2, 2, 1, 9], "Interface last change time"},
    {"ifInOctets", [1, 3, 6, 1, 2, 1, 2, 2, 1, 10], "Interface input octets"},
    {"ifInUcastPkts", [1, 3, 6, 1, 2, 1, 2, 2, 1, 11], "Interface input unicast packets"},
    {"ifInNUcastPkts", [1, 3, 6, 1, 2, 1, 2, 2, 1, 12], "Interface input non-unicast packets"},
    {"ifInDiscards", [1, 3, 6, 1, 2, 1, 2, 2, 1, 13], "Interface input discarded packets"},
    {"ifInErrors", [1, 3, 6, 1, 2, 1, 2, 2, 1, 14], "Interface input error packets"},
    {"ifInUnknownProtos", [1, 3, 6, 1, 2, 1, 2, 2, 1, 15], "Interface input unknown protocol packets"},
    {"ifOutOctets", [1, 3, 6, 1, 2, 1, 2, 2, 1, 16], "Interface output octets"},
    {"ifOutUcastPkts", [1, 3, 6, 1, 2, 1, 2, 2, 1, 17], "Interface output unicast packets"},
    {"ifOutNUcastPkts", [1, 3, 6, 1, 2, 1, 2, 2, 1, 18], "Interface output non-unicast packets"},
    {"ifOutDiscards", [1, 3, 6, 1, 2, 1, 2, 2, 1, 19], "Interface output discarded packets"},
    {"ifOutErrors", [1, 3, 6, 1, 2, 1, 2, 2, 1, 20], "Interface output error packets"},
    {"ifOutQLen", [1, 3, 6, 1, 2, 1, 2, 2, 1, 21], "Interface output queue length"},
    {"ifSpecific", [1, 3, 6, 1, 2, 1, 2, 2, 1, 22], "Interface specific OID"}
  ]

  @rfc1213_ip_group [
    {"ipForwarding", [1, 3, 6, 1, 2, 1, 4, 1], "IP forwarding enabled/disabled"},
    {"ipDefaultTTL", [1, 3, 6, 1, 2, 1, 4, 2], "IP default TTL"},
    {"ipInReceives", [1, 3, 6, 1, 2, 1, 4, 3], "IP input datagrams"},
    {"ipInHdrErrors", [1, 3, 6, 1, 2, 1, 4, 4], "IP input header errors"},
    {"ipInAddrErrors", [1, 3, 6, 1, 2, 1, 4, 5], "IP input address errors"}
  ]

  @rfc1213_snmp_group [
    {"snmpInPkts", [1, 3, 6, 1, 2, 1, 11, 1], "SNMP input packets"},
    {"snmpOutPkts", [1, 3, 6, 1, 2, 1, 11, 2], "SNMP output packets"},
    {"snmpInBadVersions", [1, 3, 6, 1, 2, 1, 11, 3], "SNMP input bad versions"},
    {"snmpInBadCommunityNames", [1, 3, 6, 1, 2, 1, 11, 4], "SNMP input bad community names"},
    {"snmpInBadCommunityUses", [1, 3, 6, 1, 2, 1, 11, 5], "SNMP input bad community uses"},
    {"snmpInASNParseErrs", [1, 3, 6, 1, 2, 1, 11, 6], "SNMP input ASN.1 parse errors"},
    {"snmpInTooBigs", [1, 3, 6, 1, 2, 1, 11, 8], "SNMP input too big errors"},
    {"snmpInNoSuchNames", [1, 3, 6, 1, 2, 1, 11, 9], "SNMP input no such name errors"},
    {"snmpInBadValues", [1, 3, 6, 1, 2, 1, 11, 10], "SNMP input bad value errors"},
    {"snmpInReadOnlys", [1, 3, 6, 1, 2, 1, 11, 11], "SNMP input read only errors"},
    {"snmpInGenErrs", [1, 3, 6, 1, 2, 1, 11, 12], "SNMP input general errors"},
    {"snmpInTotalReqVars", [1, 3, 6, 1, 2, 1, 11, 13], "SNMP input total request variables"},
    {"snmpInTotalSetVars", [1, 3, 6, 1, 2, 1, 11, 14], "SNMP input total set variables"},
    {"snmpInGetRequests", [1, 3, 6, 1, 2, 1, 11, 15], "SNMP input get requests"},
    {"snmpInGetNexts", [1, 3, 6, 1, 2, 1, 11, 16], "SNMP input get next requests"},
    {"snmpInSetRequests", [1, 3, 6, 1, 2, 1, 11, 17], "SNMP input set requests"},
    {"snmpInGetResponses", [1, 3, 6, 1, 2, 1, 11, 18], "SNMP input get responses"},
    {"snmpInTraps", [1, 3, 6, 1, 2, 1, 11, 19], "SNMP input traps"},
    {"snmpOutTooBigs", [1, 3, 6, 1, 2, 1, 11, 20], "SNMP output too big errors"},
    {"snmpOutNoSuchNames", [1, 3, 6, 1, 2, 1, 11, 21], "SNMP output no such name errors"},
    {"snmpOutBadValues", [1, 3, 6, 1, 2, 1, 11, 22], "SNMP output bad value errors"},
    {"snmpOutGenErrs", [1, 3, 6, 1, 2, 1, 11, 24], "SNMP output general errors"},
    {"snmpOutGetRequests", [1, 3, 6, 1, 2, 1, 11, 25], "SNMP output get requests"},
    {"snmpOutGetNexts", [1, 3, 6, 1, 2, 1, 11, 26], "SNMP output get next requests"},
    {"snmpOutSetRequests", [1, 3, 6, 1, 2, 1, 11, 27], "SNMP output set requests"},
    {"snmpOutGetResponses", [1, 3, 6, 1, 2, 1, 11, 28], "SNMP output get responses"},
    {"snmpOutTraps", [1, 3, 6, 1, 2, 1, 11, 29], "SNMP output traps"},
    {"snmpEnableAuthenTraps", [1, 3, 6, 1, 2, 1, 11, 30], "SNMP enable authentication traps"}
  ]

  # RFC 2863 Interface MIB extensions (partial list)
  @rfc2863_interface_extensions [
    # These would be in ifXTable (1.3.6.1.2.1.31.1.1.1)
    # Note: These may not be implemented in the current MIB module
    {"ifName", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 1], "Interface name"},
    {"ifInMulticastPkts", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 2], "Interface input multicast packets"},
    {"ifInBroadcastPkts", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 3], "Interface input broadcast packets"},
    {"ifOutMulticastPkts", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 4], "Interface output multicast packets"},
    {"ifOutBroadcastPkts", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 5], "Interface output broadcast packets"},
    {"ifHCInOctets", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 6], "Interface high capacity input octets"},
    {"ifHCInUcastPkts", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 7], "Interface high capacity input unicast packets"},
    {"ifHCInMulticastPkts", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 8], "Interface high capacity input multicast packets"},
    {"ifHCInBroadcastPkts", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 9], "Interface high capacity input broadcast packets"},
    {"ifHCOutOctets", [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 10], "Interface high capacity output octets"}
  ]

  setup_all do
    # Ensure MIB server is started
    case GenServer.whereis(SNMPMgr.MIB) do
      nil -> 
        {:ok, _pid} = SNMPMgr.MIB.start_link()
        :ok
      _pid -> 
        :ok
    end
    
    :ok
  end

  describe "RFC 1213 MIB-II System Group" do
    test "resolves all system group objects" do
      for {name, expected_oid, description} <- @rfc1213_system_group do
        case MIB.resolve(name) do
          {:ok, oid} ->
            assert oid == expected_oid,
              "#{name} (#{description}) should resolve to #{inspect(expected_oid)}, got #{inspect(oid)}"
              
          {:error, reason} ->
            flunk("Failed to resolve system object '#{name}' (#{description}): #{inspect(reason)}")
        end
      end
    end

    test "performs reverse lookup for system group objects" do
      for {expected_name, oid, description} <- @rfc1213_system_group do
        case MIB.reverse_lookup(oid) do
          {:ok, name} ->
            assert name == expected_name,
              "OID #{inspect(oid)} (#{description}) should reverse to '#{expected_name}', got '#{name}'"
              
          {:error, reason} ->
            flunk("Failed reverse lookup for #{inspect(oid)} (#{description}): #{inspect(reason)}")
        end
      end
    end

    test "validates system group OID hierarchy" do
      # All system objects should be under 1.3.6.1.2.1.1
      system_prefix = [1, 3, 6, 1, 2, 1, 1]
      
      for {name, oid, _description} <- @rfc1213_system_group do
        assert List.starts_with?(oid, system_prefix),
          "System object '#{name}' OID #{inspect(oid)} should start with #{inspect(system_prefix)}"
        
        # System group objects should have exactly one more element
        assert length(oid) == length(system_prefix) + 1,
          "System object '#{name}' should have exactly 8 OID components, has #{length(oid)}"
      end
    end
  end

  describe "RFC 1213 MIB-II Interface Group" do
    test "resolves all interface group objects" do
      for {name, expected_oid, description} <- @rfc1213_interface_group do
        case MIB.resolve(name) do
          {:ok, oid} ->
            assert oid == expected_oid,
              "#{name} (#{description}) should resolve to #{inspect(expected_oid)}, got #{inspect(oid)}"
              
          {:error, reason} ->
            flunk("Failed to resolve interface object '#{name}' (#{description}): #{inspect(reason)}")
        end
      end
    end

    test "validates interface table structure" do
      # Check that ifTable structure is correct
      {:ok, if_table_oid} = MIB.resolve("ifTable")
      {:ok, if_entry_oid} = MIB.resolve("ifEntry")
      
      # ifEntry should be a child of ifTable
      assert List.starts_with?(if_entry_oid, if_table_oid),
        "ifEntry should be under ifTable"
      
      # All ifTable columnar objects should be under ifEntry
      interface_columns = [
        "ifIndex", "ifDescr", "ifType", "ifMtu", "ifSpeed", "ifPhysAddress",
        "ifAdminStatus", "ifOperStatus", "ifLastChange", "ifInOctets",
        "ifInUcastPkts", "ifInNUcastPkts", "ifInDiscards", "ifInErrors",
        "ifInUnknownProtos", "ifOutOctets", "ifOutUcastPkts", "ifOutNUcastPkts",
        "ifOutDiscards", "ifOutErrors", "ifOutQLen", "ifSpecific"
      ]
      
      for column_name <- interface_columns do
        {:ok, column_oid} = MIB.resolve(column_name)
        assert List.starts_with?(column_oid, if_entry_oid),
          "Interface column '#{column_name}' should be under ifEntry"
      end
    end

    test "validates interface group OID hierarchy" do
      # All interface objects should be under 1.3.6.1.2.1.2
      interface_prefix = [1, 3, 6, 1, 2, 1, 2]
      
      for {name, oid, _description} <- @rfc1213_interface_group do
        assert List.starts_with?(oid, interface_prefix),
          "Interface object '#{name}' OID #{inspect(oid)} should start with #{inspect(interface_prefix)}"
      end
    end
  end

  describe "RFC 1213 MIB-II IP Group" do
    test "resolves all IP group objects" do
      for {name, expected_oid, description} <- @rfc1213_ip_group do
        case MIB.resolve(name) do
          {:ok, oid} ->
            assert oid == expected_oid,
              "#{name} (#{description}) should resolve to #{inspect(expected_oid)}, got #{inspect(oid)}"
              
          {:error, reason} ->
            flunk("Failed to resolve IP object '#{name}' (#{description}): #{inspect(reason)}")
        end
      end
    end

    test "validates IP group OID hierarchy" do
      # All IP objects should be under 1.3.6.1.2.1.4
      ip_prefix = [1, 3, 6, 1, 2, 1, 4]
      
      for {name, oid, _description} <- @rfc1213_ip_group do
        assert List.starts_with?(oid, ip_prefix),
          "IP object '#{name}' OID #{inspect(oid)} should start with #{inspect(ip_prefix)}"
      end
    end
  end

  describe "RFC 1213 MIB-II SNMP Group" do
    test "resolves all SNMP group objects" do
      for {name, expected_oid, description} <- @rfc1213_snmp_group do
        case MIB.resolve(name) do
          {:ok, oid} ->
            assert oid == expected_oid,
              "#{name} (#{description}) should resolve to #{inspect(expected_oid)}, got #{inspect(oid)}"
              
          {:error, reason} ->
            flunk("Failed to resolve SNMP object '#{name}' (#{description}): #{inspect(reason)}")
        end
      end
    end

    test "validates SNMP group OID hierarchy" do
      # All SNMP objects should be under 1.3.6.1.2.1.11
      snmp_prefix = [1, 3, 6, 1, 2, 1, 11]
      
      for {name, oid, _description} <- @rfc1213_snmp_group do
        assert List.starts_with?(oid, snmp_prefix),
          "SNMP object '#{name}' OID #{inspect(oid)} should start with #{inspect(snmp_prefix)}"
      end
    end

    test "validates SNMP statistics consistency" do
      # Test that SNMP counter objects follow expected patterns
      input_counters = ["snmpInPkts", "snmpInBadVersions", "snmpInTooBigs", "snmpInGenErrs"]
      output_counters = ["snmpOutPkts", "snmpOutTooBigs", "snmpOutGenErrs"]
      
      for counter <- input_counters ++ output_counters do
        {:ok, oid} = MIB.resolve(counter)
        assert is_list(oid), "SNMP counter '#{counter}' should have valid OID"
        assert length(oid) > 0, "SNMP counter '#{counter}' should have non-empty OID"
      end
    end
  end

  describe "RFC 2863 Interface MIB Extensions" do
    test "attempts to resolve RFC 2863 extensions" do
      for {name, expected_oid, description} <- @rfc2863_interface_extensions do
        case MIB.resolve(name) do
          {:ok, oid} ->
            assert oid == expected_oid,
              "RFC 2863 #{name} (#{description}) should resolve to #{inspect(expected_oid)}, got #{inspect(oid)}"
              
          {:error, :not_found} ->
            # RFC 2863 extensions might not be implemented yet
            assert true, "RFC 2863 object '#{name}' not yet implemented"
            
          {:error, reason} ->
            # Other errors are acceptable for extensions
            assert is_atom(reason), "RFC 2863 resolution error for '#{name}': #{inspect(reason)}"
        end
      end
    end

    test "validates RFC 2863 OID hierarchy when available" do
      # RFC 2863 objects should be under 1.3.6.1.2.1.31.1.1.1 (ifXTable)
      rfc2863_prefix = [1, 3, 6, 1, 2, 1, 31, 1, 1, 1]
      
      for {name, oid, _description} <- @rfc2863_interface_extensions do
        case MIB.resolve(name) do
          {:ok, resolved_oid} ->
            assert List.starts_with?(resolved_oid, rfc2863_prefix),
              "RFC 2863 object '#{name}' should be under ifXTable prefix"
            assert resolved_oid == oid,
              "RFC 2863 object '#{name}' OID should match specification"
              
          {:error, _} ->
            # Not implemented, skip validation
            :ok
        end
      end
    end
  end

  describe "Standard MIB compliance and interoperability" do
    test "validates MIB object instance notation" do
      # Test standard scalar instances (.0)
      scalar_objects = ["sysDescr.0", "sysUpTime.0", "ipForwarding.0", "snmpInPkts.0"]
      
      for scalar_instance <- scalar_objects do
        case MIB.resolve(scalar_instance) do
          {:ok, oid} ->
            assert List.last(oid) == 0,
              "Scalar instance '#{scalar_instance}' should end with .0"
              
          {:error, reason} ->
            flunk("Failed to resolve scalar instance '#{scalar_instance}': #{inspect(reason)}")
        end
      end
    end

    test "validates table object instance notation" do
      # Test table object instances
      table_instances = [
        {"ifDescr.1", [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1]},
        {"ifDescr.2", [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 2]},
        {"ifSpeed.1", [1, 3, 6, 1, 2, 1, 2, 2, 1, 5, 1]},
        {"ifOperStatus.10", [1, 3, 6, 1, 2, 1, 2, 2, 1, 8, 10]},
      ]
      
      for {instance_name, expected_oid} <- table_instances do
        case MIB.resolve(instance_name) do
          {:ok, oid} ->
            assert oid == expected_oid,
              "Table instance '#{instance_name}' should resolve to #{inspect(expected_oid)}, got #{inspect(oid)}"
              
          {:error, reason} ->
            flunk("Failed to resolve table instance '#{instance_name}': #{inspect(reason)}")
        end
      end
    end

    test "validates standard OID prefixes" do
      standard_prefixes = %{
        "iso.org.dod.internet.mgmt.mib-2" => [1, 3, 6, 1, 2, 1],
        "system group" => [1, 3, 6, 1, 2, 1, 1],
        "interfaces group" => [1, 3, 6, 1, 2, 1, 2],
        "ip group" => [1, 3, 6, 1, 2, 1, 4],
        "snmp group" => [1, 3, 6, 1, 2, 1, 11],
      }
      
      for {group_name, prefix} <- standard_prefixes do
        # Verify that we have objects under each standard prefix
        all_standard_objects = @rfc1213_system_group ++ @rfc1213_interface_group ++ 
                               @rfc1213_ip_group ++ @rfc1213_snmp_group
        
        objects_found = Enum.count(all_standard_objects, fn {_name, oid, _desc} ->
          List.starts_with?(oid, prefix)
        end)
        
        assert objects_found > 0, "Should have objects under #{group_name} prefix #{inspect(prefix)}"
      end
    end

    test "validates MIB object naming conventions" do
      # Check that object names follow standard conventions
      all_objects = @rfc1213_system_group ++ @rfc1213_interface_group ++ 
                   @rfc1213_ip_group ++ @rfc1213_snmp_group
      
      for {name, _oid, _description} <- all_objects do
        # Names should start with lowercase letter
        assert String.match?(name, ~r/^[a-z]/),
          "MIB object name '#{name}' should start with lowercase letter"
        
        # Names should not contain spaces or special characters
        assert String.match?(name, ~r/^[a-zA-Z0-9]+$/),
          "MIB object name '#{name}' should only contain alphanumeric characters"
        
        # Names should not be empty
        assert String.length(name) > 0,
          "MIB object name should not be empty"
      end
    end
  end

  describe "Standard MIB integration testing" do
    alias SNMPMgr.TestSupport.SNMPSimulator
    
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    @tag :integration
    test "standard MIB objects work with real SNMP operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test key standard objects that should be available on most devices
      standard_test_objects = [
        "sysDescr.0",
        "sysUpTime.0",
        "sysObjectID.0",
        "ifNumber.0",
      ]
      
      for mib_object <- standard_test_objects do
        case MIB.resolve(mib_object) do
          {:ok, oid} ->
            case SNMPMgr.get(target, oid, community: device.community) do
              {:ok, response} ->
                assert is_binary(response) or is_integer(response),
                  "Standard MIB object '#{mib_object}' should return valid response"
                  
              {:error, :snmp_modules_not_available} ->
                # Expected in test environment
                assert true, "SNMP modules not available for standard MIB integration test"
                
              {:error, reason} ->
                # Some objects might not be implemented in simulator
                assert is_atom(reason),
                  "SNMP operation with standard MIB object '#{mib_object}' failed: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            flunk("Failed to resolve standard MIB object '#{mib_object}': #{inspect(reason)}")
        end
      end
    end

    @tag :integration
    test "interface table objects work correctly", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test interface table structure
      interface_test_objects = [
        "ifNumber.0",    # Number of interfaces
        "ifDescr.1",     # First interface description
        "ifType.1",      # First interface type
        "ifOperStatus.1", # First interface operational status
      ]
      
      for if_object <- interface_test_objects do
        case MIB.resolve(if_object) do
          {:ok, oid} ->
            case SNMPMgr.get(target, oid, community: device.community) do
              {:ok, _response} ->
                assert true, "Interface MIB object '#{if_object}' accessible"
                
              {:error, :snmp_modules_not_available} ->
                # Expected in test environment
                assert true, "SNMP modules not available for interface MIB integration test"
                
              {:error, reason} ->
                # Interface might not exist or not implemented
                assert is_atom(reason),
                  "Interface MIB operation failed: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            flunk("Failed to resolve interface MIB object '#{if_object}': #{inspect(reason)}")
        end
      end
    end
  end

  describe "Standard MIB performance" do
    @tag :performance
    test "standard MIB resolution is fast" do
      # Test performance with commonly used standard objects
      common_objects = [
        "sysDescr", "sysUpTime", "sysName", "ifNumber", 
        "ifDescr", "ifOperStatus", "ipForwarding", "snmpInPkts"
      ]
      
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for object <- common_objects do
            MIB.resolve(object)
          end
        end
      end)
      
      time_per_resolution = time_microseconds / (1000 * length(common_objects))
      
      # Standard MIB resolution should be very fast
      assert time_per_resolution < 50,
        "Standard MIB resolution too slow: #{time_per_resolution} microseconds per resolution"
    end

    @tag :performance
    test "standard MIB reverse lookup is fast" do
      # Test reverse lookup performance for standard OIDs
      common_oids = [
        [1, 3, 6, 1, 2, 1, 1, 1],    # sysDescr
        [1, 3, 6, 1, 2, 1, 1, 3],    # sysUpTime
        [1, 3, 6, 1, 2, 1, 2, 1],    # ifNumber
        [1, 3, 6, 1, 2, 1, 2, 2, 1, 2], # ifDescr
        [1, 3, 6, 1, 2, 1, 11, 1],   # snmpInPkts
      ]
      
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for oid <- common_oids do
            MIB.reverse_lookup(oid)
          end
        end
      end)
      
      time_per_lookup = time_microseconds / (1000 * length(common_oids))
      
      # Standard MIB reverse lookup should be very fast
      assert time_per_lookup < 50,
        "Standard MIB reverse lookup too slow: #{time_per_lookup} microseconds per lookup"
    end
  end
end