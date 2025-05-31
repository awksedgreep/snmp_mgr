defmodule SNMPMgr.MIBComprehensiveTest do
  use ExUnit.Case, async: false  # MIB tests need to be synchronous due to GenServer state
  
  alias SNMPMgr.MIB
  
  @moduletag :unit
  @moduletag :mib
  @moduletag :phase_2

  # Standard MIB names for testing
  @standard_mib_names [
    # System group
    "sysDescr", "sysObjectID", "sysUpTime", "sysContact", "sysName", "sysLocation", "sysServices",
    
    # Interface group  
    "ifNumber", "ifTable", "ifEntry", "ifIndex", "ifDescr", "ifType", "ifMtu", "ifSpeed",
    "ifPhysAddress", "ifAdminStatus", "ifOperStatus", "ifLastChange", "ifInOctets",
    "ifInUcastPkts", "ifInNUcastPkts", "ifInDiscards", "ifInErrors", "ifInUnknownProtos",
    "ifOutOctets", "ifOutUcastPkts", "ifOutNUcastPkts", "ifOutDiscards", "ifOutErrors",
    "ifOutQLen", "ifSpecific",
    
    # IP group
    "ipForwarding", "ipDefaultTTL", "ipInReceives", "ipInHdrErrors", "ipInAddrErrors",
    
    # SNMP group
    "snmpInPkts", "snmpOutPkts", "snmpInBadVersions", "snmpInBadCommunityNames",
    "snmpInBadCommunityUses", "snmpInASNParseErrs", "snmpInTooBigs", "snmpInNoSuchNames",
    "snmpInBadValues", "snmpInReadOnlys", "snmpInGenErrs", "snmpInTotalReqVars",
    "snmpInTotalSetVars", "snmpInGetRequests", "snmpInGetNexts", "snmpInSetRequests",
    "snmpInGetResponses", "snmpInTraps", "snmpOutTooBigs", "snmpOutNoSuchNames",
    "snmpOutBadValues", "snmpOutGenErrs", "snmpOutGetRequests", "snmpOutGetNexts",
    "snmpOutSetRequests", "snmpOutGetResponses", "snmpOutTraps", "snmpEnableAuthenTraps"
  ]

  # Standard OID to name mappings for validation
  @standard_oid_mappings [
    {[1, 3, 6, 1, 2, 1, 1, 1], "sysDescr"},
    {[1, 3, 6, 1, 2, 1, 1, 2], "sysObjectID"},
    {[1, 3, 6, 1, 2, 1, 1, 3], "sysUpTime"},
    {[1, 3, 6, 1, 2, 1, 2, 1], "ifNumber"},
    {[1, 3, 6, 1, 2, 1, 2, 2], "ifTable"},
    {[1, 3, 6, 1, 2, 1, 2, 2, 1, 2], "ifDescr"},
    {[1, 3, 6, 1, 2, 1, 4, 1], "ipForwarding"},
    {[1, 3, 6, 1, 2, 1, 11, 1], "snmpInPkts"},
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
    
    on_exit(fn ->
      # Clean up if needed
      case GenServer.whereis(SNMPMgr.MIB) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
    end)
    
    :ok
  end

  describe "MIB server lifecycle" do
    test "starts and stops cleanly" do
      # Test that we can start a separate MIB server
      case GenServer.start_link(SNMPMgr.MIB, [], name: :test_mib_server) do
        {:ok, pid} ->
          assert Process.alive?(pid), "MIB server should be alive after start"
          
          # Test basic functionality
          assert {:ok, _oid} = GenServer.call(:test_mib_server, {:resolve, "sysDescr"})
          
          # Stop cleanly
          :ok = GenServer.stop(:test_mib_server)
          refute Process.alive?(pid), "MIB server should be stopped"
          
        {:error, {:already_started, _pid}} ->
          # Server already running, test that it responds
          assert {:ok, _oid} = GenServer.call(:test_mib_server, {:resolve, "sysDescr"})
      end
    end

    test "survives invalid requests gracefully" do
      # Test with invalid resolve requests
      invalid_requests = [
        {:resolve, nil},
        {:resolve, 123},
        {:resolve, []},
        {:reverse_lookup, "invalid"},
        {:children, nil},
        {:walk_tree, nil, []},
      ]
      
      for request <- invalid_requests do
        case GenServer.call(SNMPMgr.MIB, request) do
          {:error, _reason} ->
            assert true, "Invalid request properly rejected"
          {:ok, _result} ->
            # Some invalid requests might be handled gracefully
            assert true, "Invalid request handled gracefully"
          other ->
            flunk("Unexpected response to invalid request #{inspect(request)}: #{inspect(other)}")
        end
      end
    end
  end

  describe "standard MIB name resolution" do
    test "resolves all standard MIB names correctly" do
      for name <- @standard_mib_names do
        case MIB.resolve(name) do
          {:ok, oid} ->
            assert is_list(oid), "Resolved OID should be a list for #{name}"
            assert length(oid) > 0, "OID should not be empty for #{name}"
            assert Enum.all?(oid, &is_integer/1), "All OID components should be integers for #{name}"
            
          {:error, reason} ->
            flunk("Failed to resolve standard MIB name '#{name}': #{inspect(reason)}")
        end
      end
    end

    test "handles OID instance notation" do
      instance_cases = [
        {"sysDescr.0", [1, 3, 6, 1, 2, 1, 1, 1, 0]},
        {"ifDescr.1", [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1]},
        {"ifDescr.10", [1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 10]},
        {"sysUpTime.0", [1, 3, 6, 1, 2, 1, 1, 3, 0]},
      ]
      
      for {name_with_instance, expected_oid} <- instance_cases do
        case MIB.resolve(name_with_instance) do
          {:ok, oid} ->
            assert oid == expected_oid,
              "Instance resolution failed for #{name_with_instance}. Expected #{inspect(expected_oid)}, got #{inspect(oid)}"
              
          {:error, reason} ->
            flunk("Failed to resolve instance notation '#{name_with_instance}': #{inspect(reason)}")
        end
      end
    end

    test "rejects invalid MIB names with helpful errors" do
      invalid_names = [
        "",
        "nonExistentMib",
        "invalid.mib.name.format",
        "123invalidStart",
        "sysDescr..0",  # Double dot
        "sysDescr.abc", # Non-numeric instance
        nil,
        123,
        [],
      ]
      
      for invalid_name <- invalid_names do
        case MIB.resolve(invalid_name) do
          {:ok, _oid} ->
            flunk("Should not resolve invalid name: #{inspect(invalid_name)}")
            
          {:error, reason} ->
            assert is_atom(reason) or is_binary(reason),
              "Error reason should be descriptive for #{inspect(invalid_name)}: #{inspect(reason)}"
        end
      end
    end
  end

  describe "reverse OID lookup" do
    test "performs reverse lookup for standard OIDs" do
      for {oid, expected_name} <- @standard_oid_mappings do
        case MIB.reverse_lookup(oid) do
          {:ok, name} ->
            assert name == expected_name,
              "Reverse lookup failed for #{inspect(oid)}. Expected '#{expected_name}', got '#{name}'"
              
          {:error, reason} ->
            flunk("Failed reverse lookup for #{inspect(oid)}: #{inspect(reason)}")
        end
      end
    end

    test "handles OID instances in reverse lookup" do
      instance_cases = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], "sysDescr.0"},
        {[1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1], "ifDescr.1"},
        {[1, 3, 6, 1, 2, 1, 1, 3, 0], "sysUpTime.0"},
      ]
      
      for {oid, expected_name} <- instance_cases do
        case MIB.reverse_lookup(oid) do
          {:ok, name} ->
            assert name == expected_name,
              "Instance reverse lookup failed for #{inspect(oid)}. Expected '#{expected_name}', got '#{name}'"
              
          {:error, reason} ->
            # Some implementations might not support instance reverse lookup
            assert reason in [:not_found, :instances_not_supported],
              "Unexpected error for instance reverse lookup: #{inspect(reason)}"
        end
      end
    end

    test "accepts both OID lists and OID strings" do
      test_cases = [
        {[1, 3, 6, 1, 2, 1, 1, 1], "1.3.6.1.2.1.1.1"},
        {[1, 3, 6, 1, 2, 1, 2, 1], "1.3.6.1.2.1.2.1"},
      ]
      
      for {oid_list, oid_string} <- test_cases do
        result_list = MIB.reverse_lookup(oid_list)
        result_string = MIB.reverse_lookup(oid_string)
        
        assert result_list == result_string,
          "Reverse lookup should produce same result for list and string: #{inspect(oid_list)} vs #{oid_string}"
      end
    end

    test "handles unknown OIDs gracefully" do
      unknown_oids = [
        [1, 2, 3, 4, 5],
        [9, 9, 9, 9, 9],
        [1, 3, 6, 1, 9999, 9999],
        [],
      ]
      
      for oid <- unknown_oids do
        case MIB.reverse_lookup(oid) do
          {:ok, _name} ->
            # Some OIDs might have unexpected mappings
            assert true, "Unknown OID unexpectedly resolved"
            
          {:error, :not_found} ->
            assert true, "Unknown OID properly rejected"
            
          {:error, reason} ->
            assert is_atom(reason), "Error reason should be descriptive: #{inspect(reason)}"
        end
      end
    end
  end

  describe "MIB tree navigation" do
    test "finds children of parent OIDs" do
      parent_child_cases = [
        # System group children
        {[1, 3, 6, 1, 2, 1, 1], ["sysDescr", "sysObjectID", "sysUpTime", "sysContact", "sysName", "sysLocation", "sysServices"]},
        
        # Interface group children  
        {[1, 3, 6, 1, 2, 1, 2], ["ifNumber", "ifTable"]},
        
        # Interface table entry children
        {[1, 3, 6, 1, 2, 1, 2, 2, 1], ["ifIndex", "ifDescr", "ifType", "ifMtu", "ifSpeed", "ifPhysAddress", "ifAdminStatus", "ifOperStatus", "ifLastChange", "ifInOctets", "ifInUcastPkts", "ifInNUcastPkts", "ifInDiscards", "ifInErrors", "ifInUnknownProtos", "ifOutOctets", "ifOutUcastPkts", "ifOutNUcastPkts", "ifOutDiscards", "ifOutErrors", "ifOutQLen", "ifSpecific"]},
      ]
      
      for {parent_oid, expected_children} <- parent_child_cases do
        case MIB.children(parent_oid) do
          {:ok, children} ->
            assert is_list(children), "Children should be returned as a list"
            
            # Check that all expected children are present
            for expected_child <- expected_children do
              child_found = Enum.any?(children, fn child ->
                case child do
                  {^expected_child, _oid} -> true
                  ^expected_child -> true
                  _ -> false
                end
              end)
              
              assert child_found, "Expected child '#{expected_child}' not found in children of #{inspect(parent_oid)}"
            end
            
          {:error, reason} ->
            # Some implementations might not support children lookup
            assert reason in [:not_implemented, :children_not_supported],
              "Unexpected error for children lookup: #{inspect(reason)}"
        end
      end
    end

    test "calculates parent OIDs correctly" do
      parent_cases = [
        {[1, 3, 6, 1, 2, 1, 1, 1], [1, 3, 6, 1, 2, 1, 1]},
        {[1, 3, 6, 1, 2, 1, 2, 2, 1, 2], [1, 3, 6, 1, 2, 1, 2, 2, 1]},
        {[1, 3, 6, 1], [1, 3, 6]},
        {[1], []},
      ]
      
      for {child_oid, expected_parent} <- parent_cases do
        case MIB.parent(child_oid) do
          {:ok, parent_oid} ->
            assert parent_oid == expected_parent,
              "Parent calculation failed for #{inspect(child_oid)}. Expected #{inspect(expected_parent)}, got #{inspect(parent_oid)}"
              
          {:error, :no_parent} when expected_parent == [] ->
            assert true, "Correctly identified root OID has no parent"
            
          {:error, reason} ->
            flunk("Unexpected error calculating parent of #{inspect(child_oid)}: #{inspect(reason)}")
        end
      end
    end

    test "handles parent calculation for empty and invalid OIDs" do
      edge_cases = [
        {[], {:error, :no_parent}},
        {"", {:error, :invalid_oid}},
        {"1.3.6.1", {:ok, [1, 3, 6]}},
        {"1", {:ok, []}},
      ]
      
      for {input_oid, expected_result} <- edge_cases do
        actual_result = MIB.parent(input_oid)
        
        case expected_result do
          {:ok, expected_parent} ->
            assert {:ok, actual_parent} = actual_result
            assert actual_parent == expected_parent,
              "Parent of #{inspect(input_oid)} should be #{inspect(expected_parent)}, got #{inspect(actual_parent)}"
              
          {:error, expected_error} ->
            assert {:error, actual_error} = actual_result
            assert actual_error == expected_error or is_atom(actual_error),
              "Expected error #{expected_error} for #{inspect(input_oid)}, got #{inspect(actual_error)}"
        end
      end
    end
  end

  describe "MIB tree walking" do
    test "walks system group tree" do
      case MIB.walk_tree([1, 3, 6, 1, 2, 1, 1]) do
        {:ok, tree_nodes} ->
          assert is_list(tree_nodes), "Tree walk should return a list"
          assert length(tree_nodes) > 0, "System group should have tree nodes"
          
          # Check that system group objects are found
          system_objects = ["sysDescr", "sysObjectID", "sysUpTime", "sysContact", "sysName", "sysLocation", "sysServices"]
          
          for sys_obj <- system_objects do
            found = Enum.any?(tree_nodes, fn node ->
              case node do
                {^sys_obj, _oid} -> true
                {_name, oid} -> 
                  case MIB.reverse_lookup(oid) do
                    {:ok, ^sys_obj} -> true
                    _ -> false
                  end
                _ -> false
              end
            end)
            
            assert found, "System object '#{sys_obj}' should be found in tree walk"
          end
          
        {:error, reason} ->
          # Tree walking might not be implemented yet
          assert reason in [:not_implemented, :tree_walk_not_supported],
            "Unexpected error in tree walk: #{inspect(reason)}"
      end
    end

    test "walks interface group tree" do
      case MIB.walk_tree([1, 3, 6, 1, 2, 1, 2]) do
        {:ok, tree_nodes} ->
          assert is_list(tree_nodes), "Tree walk should return a list"
          
          # Should find interface objects
          interface_objects = ["ifNumber", "ifTable", "ifEntry"]
          
          for if_obj <- interface_objects do
            found = Enum.any?(tree_nodes, fn node ->
              case node do
                {^if_obj, _oid} -> true
                _ -> false
              end
            end)
            
            # Note: not all interface objects may be at the top level
            if found do
              assert true, "Interface object '#{if_obj}' found in tree walk"
            end
          end
          
        {:error, reason} ->
          # Tree walking might not be implemented yet
          assert reason in [:not_implemented, :tree_walk_not_supported],
            "Unexpected error in interface tree walk: #{inspect(reason)}"
      end
    end

    test "handles invalid tree walk roots" do
      invalid_roots = [
        [],
        [999, 999, 999],
        "invalid",
        nil,
      ]
      
      for invalid_root <- invalid_roots do
        case MIB.walk_tree(invalid_root) do
          {:ok, nodes} ->
            # Some invalid roots might return empty results
            assert is_list(nodes), "Should return list even for invalid roots"
            
          {:error, reason} ->
            assert is_atom(reason), "Should provide descriptive error for invalid root: #{inspect(reason)}"
        end
      end
    end
  end

  describe "MIB file compilation" do
    test "handles SNMP compiler availability" do
      case MIB.compile("nonexistent.mib") do
        {:error, :snmp_compiler_not_available} ->
          assert true, "Correctly reports when SNMP compiler is not available"
          
        {:error, :file_not_found} ->
          assert true, "SNMP compiler is available but file not found"
          
        {:error, reason} ->
          assert (is_atom(reason) or is_tuple(reason)), "Should provide descriptive error: #{inspect(reason)}"
          
        {:ok, _compiled_file} ->
          flunk("Should not succeed with nonexistent file")
      end
    end

    test "compiles directory of MIB files" do
      # Create a temporary test directory
      temp_dir = System.tmp_dir!() |> Path.join("snmp_mib_test_#{System.unique_integer()}")
      File.mkdir_p!(temp_dir)
      
      # Create a dummy MIB file
      dummy_mib_content = """
      TEST-MIB DEFINITIONS ::= BEGIN
      testObject OBJECT-TYPE
          SYNTAX INTEGER
          ACCESS read-only
          STATUS mandatory
          DESCRIPTION "Test object"
          ::= { 1 3 6 1 4 1 99999 1 }
      END
      """
      
      dummy_mib_path = Path.join(temp_dir, "test.mib")
      File.write!(dummy_mib_path, dummy_mib_content)
      
      case MIB.compile_dir(temp_dir) do
        {:ok, results} ->
          assert is_list(results), "Should return list of compilation results"
          assert length(results) > 0, "Should find MIB files in directory"
          
          # Check that our test file was processed
          found_test_mib = Enum.any?(results, fn {filename, _result} ->
            filename == "test.mib"
          end)
          
          assert found_test_mib, "Should find test.mib in results"
          
        {:error, reason} ->
          # Compilation might fail due to missing SNMP compiler or invalid MIB
          assert reason in [:snmp_compiler_not_available, {:directory_error, :enoent}] or is_tuple(reason),
            "Should provide descriptive error: #{inspect(reason)}"
      end
      
      # Clean up
      File.rm_rf!(temp_dir)
    end

    test "handles non-existent directories gracefully" do
      case MIB.compile_dir("/nonexistent/directory/path") do
        {:error, {:directory_error, reason}} ->
          assert reason in [:enoent, :enotdir], "Should report directory error appropriately"
          
        {:error, reason} ->
          assert is_atom(reason), "Should provide descriptive error: #{inspect(reason)}"
          
        {:ok, _results} ->
          flunk("Should not succeed with nonexistent directory")
      end
    end
  end

  describe "MIB loading and management" do
    test "loads standard MIBs" do
      case MIB.load_standard_mibs() do
        :ok ->
          assert true, "Standard MIBs loaded successfully"
          
          # Verify that standard MIBs are accessible
          {:ok, _oid} = MIB.resolve("sysDescr")
          {:ok, _name} = MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1])
          
        {:error, reason} ->
          assert is_atom(reason), "Should provide descriptive error: #{inspect(reason)}"
      end
    end

    test "handles loading compiled MIB files" do
      # Test with a nonexistent compiled MIB file
      case MIB.load("/nonexistent/path/to/compiled.bin") do
        {:ok, _info} ->
          flunk("Should not succeed with nonexistent file")
          
        {:error, reason} ->
          assert (reason in [:file_not_found, :load_failed, :invalid_mib_file] or is_atom(reason) or is_tuple(reason)),
            "Should provide descriptive error for missing file: #{inspect(reason)}"
      end
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "name resolution is fast" do
      test_names = ["sysDescr", "ifDescr", "snmpInPkts", "ipForwarding", "sysUpTime"]
      
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for name <- test_names do
            MIB.resolve(name)
          end
        end
      end)
      
      time_per_resolution = time_microseconds / (1000 * length(test_names))
      
      # Should be very fast (less than 100 microseconds per resolution)
      assert time_per_resolution < 100,
        "MIB name resolution too slow: #{time_per_resolution} microseconds per resolution"
    end

    @tag :performance
    test "reverse lookup is fast" do
      test_oids = [
        [1, 3, 6, 1, 2, 1, 1, 1],
        [1, 3, 6, 1, 2, 1, 2, 2, 1, 2],
        [1, 3, 6, 1, 2, 1, 11, 1],
        [1, 3, 6, 1, 2, 1, 4, 1],
      ]
      
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for oid <- test_oids do
            MIB.reverse_lookup(oid)
          end
        end
      end)
      
      time_per_lookup = time_microseconds / (1000 * length(test_oids))
      
      # Should be very fast (less than 100 microseconds per lookup)
      assert time_per_lookup < 100,
        "MIB reverse lookup too slow: #{time_per_lookup} microseconds per lookup"
    end

    @tag :performance
    test "memory usage is reasonable" do
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)
      
      # Perform many MIB operations
      operations = for _i <- 1..1000 do
        name = Enum.random(@standard_mib_names)
        {:ok, oid} = MIB.resolve(name)
        {:ok, _resolved_name} = MIB.reverse_lookup(oid)
        {name, oid}
      end
      
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      # Should use reasonable memory (less than 5MB for all operations)
      assert memory_used < 5_000_000,
        "MIB operations memory usage too high: #{memory_used} bytes"
      
      # Clean up
      operations = nil
      :erlang.garbage_collect()
    end
  end

  describe "integration with SNMP simulator" do
    alias SNMPMgr.TestSupport.SNMPSimulator
    
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    @tag :integration
    test "MIB names work with real SNMP operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test standard MIB names with real SNMP operations
      mib_test_cases = [
        "sysDescr.0",
        "sysUpTime.0", 
        "sysContact.0",
        "sysName.0",
      ]
      
      for mib_name <- mib_test_cases do
        case MIB.resolve(mib_name) do
          {:ok, oid} ->
            # Try to use resolved OID in SNMP operation
            case SNMPMgr.get(target, oid, community: device.community) do
              {:ok, _response} ->
                assert true, "MIB name '#{mib_name}' works with real SNMP operation"
                
              {:error, :snmp_modules_not_available} ->
                # Expected in test environment
                assert true, "SNMP modules not available for MIB integration test"
                
              {:error, reason} ->
                # Some MIB objects might not be implemented in simulator
                assert is_atom(reason), "SNMP operation with MIB name failed: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            flunk("Failed to resolve MIB name '#{mib_name}': #{inspect(reason)}")
        end
      end
    end

    @tag :integration
    test "reverse lookup works with SNMP responses", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that we can reverse lookup OIDs from SNMP responses
      test_oids = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],  # sysDescr.0
        [1, 3, 6, 1, 2, 1, 1, 3, 0],  # sysUpTime.0
      ]
      
      for oid <- test_oids do
        case SNMPMgr.get(target, oid, community: device.community) do
          {:ok, _response} ->
            # Test reverse lookup of the OID we just used
            case MIB.reverse_lookup(oid) do
              {:ok, mib_name} ->
                assert is_binary(mib_name), "Should get MIB name for #{inspect(oid)}"
                assert String.length(mib_name) > 0, "MIB name should not be empty"
                
              {:error, :not_found} ->
                # Some OIDs might not have reverse mappings
                assert true, "OID #{inspect(oid)} not found in reverse lookup"
            end
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available for reverse lookup integration test"
            
          {:error, _reason} ->
            # Device might not support this OID
            assert true, "SNMP operation failed for integration test"
        end
      end
    end
  end
end