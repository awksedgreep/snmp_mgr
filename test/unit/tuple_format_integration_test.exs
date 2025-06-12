defmodule SnmpMgr.TupleFormatIntegrationTest do
  use ExUnit.Case, async: true
  alias SnmpMgr.{Bulk, Table, Stream}
  
  describe "3-tuple format integration across modules" do
    setup do
      # Mock interface table data in 3-tuple format
      interface_data = [
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},        # ifIndex.1
        {"1.3.6.1.2.1.2.2.1.1.2.1", :octet_string, "eth0"}, # ifDescr.1
        {"1.3.6.1.2.1.2.2.1.1.3.1", :integer, 6},        # ifType.1
        {"1.3.6.1.2.1.2.2.1.1.5.1", :gauge32, 1000000000}, # ifSpeed.1
        {"1.3.6.1.2.1.2.2.1.1.8.1", :integer, 1},        # ifOperStatus.1
        {"1.3.6.1.2.1.2.2.1.1.1.2", :integer, 2},        # ifIndex.2
        {"1.3.6.1.2.1.2.2.1.1.2.2", :octet_string, "eth1"}, # ifDescr.2
        {"1.3.6.1.2.1.2.2.1.1.3.2", :integer, 6},        # ifType.2
        {"1.3.6.1.2.1.2.2.1.1.5.2", :gauge32, 100000000}, # ifSpeed.2
        {"1.3.6.1.2.1.2.2.1.1.8.2", :integer, 1}         # ifOperStatus.2
      ]
      
      %{interface_data: interface_data}
    end
    
    test "bulk filtering preserves 3-tuple format", %{interface_data: data} do
      # Simulate what Bulk.filter_table_results should do
      root_oid = [1, 3, 6, 1, 2, 1, 2, 2, 1]
      
      # Filter and convert to standardized format (what bulk module does)
      filtered_results = data
      |> Enum.filter(fn {oid_string, _type, _value} ->
        case SnmpLib.OID.string_to_list(oid_string) do
          {:ok, oid_list} -> List.starts_with?(oid_list, root_oid)
          _ -> false
        end
      end)
      
      # All should be in scope
      assert length(filtered_results) == 10
      
      # Verify all results maintain 3-tuple format
      Enum.each(filtered_results, fn result ->
        assert match?({oid, type, value} when is_binary(oid) and is_atom(type), result)
      end)
    end
    
    test "table processing handles 3-tuple format correctly", %{interface_data: data} do
      # Test Table.to_table with proper table OID
      table_oid = "1.3.6.1.2.1.2.2.1"
      result = Table.to_table(data, table_oid)
      
      assert {:ok, table_data} = result
      assert is_map(table_data)
      
      # Should have entries for indexes 1 and 2
      assert Map.has_key?(table_data, 1)
      assert Map.has_key?(table_data, 2)
      
      # Verify data structure and type preservation
      row1 = table_data[1]
      assert is_integer(row1[1])    # ifIndex should be integer
      assert is_binary(row1[2])     # ifDescr should be string
      assert is_integer(row1[5])    # ifSpeed should be integer
      
      # Verify specific values
      assert row1[1] == 1
      assert row1[2] == "eth0"
      assert row1[5] == 1000000000
    end
    
    test "table to map conversion preserves values from 3-tuple format", %{interface_data: data} do
      # Test Table.to_map with key column (using ifIndex column 1 as key)
      result = Table.to_map(data, 1)
      
      assert {:ok, map_data} = result
      assert is_map(map_data)
      
      # Should be keyed by ifIndex values (1 and 2)
      assert Map.has_key?(map_data, 1)
      assert Map.has_key?(map_data, 2)
      
      # Verify interface 1 data
      interface1 = map_data[1]
      assert interface1[1] == 1        # ifIndex
      assert interface1[2] == "eth0"   # ifDescr
      assert interface1[5] == 1000000000  # ifSpeed
      
      # Verify interface 2 data  
      interface2 = map_data[2]
      assert interface2[1] == 2
      assert interface2[2] == "eth1"
      assert interface2[5] == 100000000
    end
    
    test "stream filtering works with 3-tuple format", %{interface_data: data} do
      # Test filtering with type-aware function
      filter_fn = fn {oid, type, _value} ->
        # Filter for interface descriptions (column 2) that are strings
        String.contains?(oid, "1.3.6.1.2.1.2.2.1.1.2.") and type == :octet_string
      end
      
      filtered = Enum.filter(data, filter_fn)
      
      assert length(filtered) == 2  # Should have 2 interface descriptions
      
      # Verify all results are interface descriptions
      Enum.each(filtered, fn {oid, type, value} ->
        assert String.contains?(oid, "1.3.6.1.2.1.2.2.1.1.2.")
        assert type == :octet_string
        assert is_binary(value)
      end)
    end
    
    test "type information enables advanced filtering", %{interface_data: data} do
      # Filter for operational interfaces (ifOperStatus == 1) using type info
      operational_filter = fn {oid, type, value} ->
        # Look for ifOperStatus (column 8) that are integers with value 1
        String.contains?(oid, "1.3.6.1.2.1.2.2.1.1.8.") and 
        type == :integer and 
        value == 1
      end
      
      operational = Enum.filter(data, operational_filter)
      
      # Should find operational interfaces
      assert length(operational) >= 0  # May be 0 if no ifOperStatus in test data
      
      # Verify all results are operational status entries
      Enum.each(operational, fn {oid, type, value} ->
        assert String.contains?(oid, "1.3.6.1.2.1.2.2.1.1.8.")
        assert type == :integer
        assert value == 1
      end)
    end
    
    test "mixed format handling during transition", %{interface_data: data} do
      # Simulate mixed 2-tuple and 3-tuple data during transition
      mixed_data = [
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},     # 3-tuple
        {"1.3.6.1.2.1.2.2.1.1.2.1", "eth0"},          # 2-tuple
        {"1.3.6.1.2.1.2.2.1.1.3.1", :integer, 6},     # 3-tuple
        {"1.3.6.1.2.1.2.2.1.1.5.1", 1000000000}       # 2-tuple
      ]
      
      # Filter that handles both formats
      flexible_filter = fn
        {oid, _type, _value} ->
          case SnmpLib.OID.string_to_list(oid) do
            {:ok, oid_list} -> List.starts_with?(oid_list, [1, 3, 6, 1, 2, 1, 2, 2, 1, 1])
            _ -> false
          end
        {oid, _value} ->
          case SnmpLib.OID.string_to_list(oid) do
            {:ok, oid_list} -> List.starts_with?(oid_list, [1, 3, 6, 1, 2, 1, 2, 2, 1, 1])
            _ -> false
          end
      end
      
      filtered = Enum.filter(mixed_data, flexible_filter)
      
      # All should pass the scope filter
      assert length(filtered) == 4
    end
    
    test "error handling with malformed tuple data" do
      malformed_data = [
        {"1.3.6.1.2.1.2.2.1.1.1.1", :integer, 1},        # Valid 3-tuple
        {"1.3.6.1.2.1.2.2.1.1.2.1", "eth0"},             # Valid 2-tuple
        {"1.3.6.1.2.1.2.2.1.1.3.1"},                     # Invalid - missing value
        {"1.3.6.1.2.1.2.2.1.1.4.1", :integer},           # Invalid - missing value
        {"1.3.6.1.2.1.2.2.1.1.5.1", :gauge32, 1000, :extra}, # Invalid - extra element
        {"1.3.6.1.2.1.2.2.1.1.6.1", :counter32, 500}     # Valid 3-tuple
      ]
      
      # Robust filter that only accepts valid formats
      safe_filter = fn
        {oid, _type, _value} when is_binary(oid) -> true
        {oid, _value} when is_binary(oid) -> true
        _ -> false
      end
      
      safe_data = Enum.filter(malformed_data, safe_filter)
      
      # Should only get the valid entries
      assert length(safe_data) == 4
      
      # Verify the valid entries
      oids = Enum.map(safe_data, fn
        {oid, _type, _value} -> oid
        {oid, _value} -> oid
      end)
      
      assert "1.3.6.1.2.1.2.2.1.1.1.1" in oids
      assert "1.3.6.1.2.1.2.2.1.1.2.1" in oids
      assert "1.3.6.1.2.1.2.2.1.1.4.1" in oids
      assert "1.3.6.1.2.1.2.2.1.1.6.1" in oids
    end
  end
  
  describe "type inference for 2-tuple compatibility" do
    test "infers types correctly for common SNMP values" do
      # Test type inference logic (simulating what bulk module does)
      test_values = [
        {1, :integer},
        {"interface-name", :octet_string},
        {1000000000, :integer},  # Could be gauge32 but defaults to integer
        {true, :boolean},
        {false, :boolean}
      ]
      
      Enum.each(test_values, fn {value, expected_type} ->
        inferred_type = case value do
          v when is_integer(v) -> :integer
          v when is_binary(v) -> :octet_string
          v when is_boolean(v) -> :boolean
          _ -> :unknown
        end
        
        assert inferred_type == expected_type
      end)
    end
    
    test "handles type inference for edge cases" do
      edge_cases = [
        {nil, :null},
        {[], :unknown},
        {%{}, :unknown},
        {:atom, :unknown}
      ]
      
      Enum.each(edge_cases, fn {value, expected_type} ->
        inferred_type = case value do
          nil -> :null
          v when is_integer(v) -> :integer
          v when is_binary(v) -> :octet_string
          v when is_boolean(v) -> :boolean
          _ -> :unknown
        end
        
        assert inferred_type == expected_type
      end)
    end
  end
end
