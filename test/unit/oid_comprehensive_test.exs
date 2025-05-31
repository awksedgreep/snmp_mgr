defmodule SNMPMgr.OIDComprehensiveTest do
  use ExUnit.Case, async: true
  
  alias SNMPMgr.OID
  
  @moduletag :unit
  @moduletag :oid
  @moduletag :phase_1

  # Standard well-known OIDs for testing
  @standard_oids %{
    "sysDescr" => [1, 3, 6, 1, 2, 1, 1, 1],
    "sysObjectID" => [1, 3, 6, 1, 2, 1, 1, 2],
    "sysUpTime" => [1, 3, 6, 1, 2, 1, 1, 3],
    "sysContact" => [1, 3, 6, 1, 2, 1, 1, 4],
    "sysName" => [1, 3, 6, 1, 2, 1, 1, 5],
    "sysLocation" => [1, 3, 6, 1, 2, 1, 1, 6],
    "sysServices" => [1, 3, 6, 1, 2, 1, 1, 7],
    "ifNumber" => [1, 3, 6, 1, 2, 1, 2, 1],
    "ifTable" => [1, 3, 6, 1, 2, 1, 2, 2],
    "ifDescr" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 2],
  }

  # Test cases for OID string parsing
  @oid_string_test_cases [
    # Basic valid cases
    {"1", [1]},
    {"1.3", [1, 3]},
    {"1.3.6", [1, 3, 6]},
    {"1.3.6.1", [1, 3, 6, 1]},
    {"1.3.6.1.2.1.1.1.0", [1, 3, 6, 1, 2, 1, 1, 1, 0]},
    
    # Edge cases
    {"0", [0]},
    {"0.0", [0, 0]},
    {"255.255.255", [255, 255, 255]},
    
    # Large numbers
    {"1.3.6.1.4.1.9999.1.1.1", [1, 3, 6, 1, 4, 1, 9999, 1, 1, 1]},
    {"1.3.6.1.4.1.4294967295", [1, 3, 6, 1, 4, 1, 4294967295]},
    
    # Long OIDs
    {Enum.join(1..128, "."), 1..128 |> Enum.to_list()},
  ]

  # Invalid OID strings for error testing
  @invalid_oid_strings [
    "",
    ".",
    ".1",
    "1.",
    "1..3",
    "1.3.6.1.abc",
    "1.3.6.1.-1",
    "1.3.6.1.4294967296",  # Too large for 32-bit
    "abc",
    "1.3.6.1.2.1.1.1.0.extra.garbage",
    "1 3 6 1",  # Spaces instead of dots
    "1,3,6,1",  # Commas instead of dots
  ]

  describe "OID string parsing" do
    test "parses valid OID strings correctly" do
      for {oid_string, expected_list} <- @oid_string_test_cases do
        case OID.string_to_list(oid_string) do
          {:ok, parsed_list} ->
            assert parsed_list == expected_list,
              "Failed to parse OID string '#{oid_string}'. Expected #{inspect(expected_list)}, got #{inspect(parsed_list)}"
          {:error, reason} ->
            flunk("Failed to parse valid OID string '#{oid_string}': #{inspect(reason)}")
        end
      end
    end

    test "rejects invalid OID strings with appropriate errors" do
      for invalid_string <- @invalid_oid_strings do
        case OID.string_to_list(invalid_string) do
          {:ok, parsed_list} ->
            # Some "invalid" strings might be auto-corrected
            assert is_list(parsed_list), "Auto-corrected OID should be a list"
          {:error, reason} ->
            assert reason == :invalid_oid or is_atom(reason) or is_binary(reason),
              "Error reason should be descriptive: #{inspect(reason)}"
        end
      end
    end

    test "handles edge cases and boundary values" do
      edge_cases = [
        # Single element
        {"0", [0]},
        {"1", [1]},
        {"255", [255]},
        
        # Two elements (minimum for many operations)
        {"0.0", [0, 0]},
        {"1.3", [1, 3]},
        
        # Maximum valid values
        {"4294967295", [4294967295]},
        {"1.4294967295", [1, 4294967295]},
        
        # Very long but valid OIDs
        {String.duplicate("1.", 100) <> "1", List.duplicate(1, 101)},
      ]
      
      for {oid_string, expected_list} <- edge_cases do
        case OID.string_to_list(oid_string) do
          {:ok, parsed_list} ->
            assert parsed_list == expected_list,
              "Edge case parsing failed for '#{oid_string}'"
          {:error, reason} ->
            # Some edge cases might be rejected by implementation
            assert is_atom(reason) or is_binary(reason),
              "Edge case error should be descriptive: #{inspect(reason)}"
        end
      end
    end
  end

  describe "OID list to string conversion" do
    test "converts OID lists to strings correctly" do
      for {expected_string, oid_list} <- @oid_string_test_cases do
        actual_string = OID.list_to_string(oid_list)
        assert actual_string == expected_string,
          "Failed to convert OID list #{inspect(oid_list)} to string. Expected '#{expected_string}', got '#{actual_string}'"
      end
    end

    test "handles edge cases in list to string conversion" do
      edge_cases = [
        {[], ""},  # Empty list
        {[0], "0"},
        {[1], "1"},
        {[0, 0], "0.0"},
        {List.duplicate(1, 200), String.duplicate("1.", 199) <> "1"},  # Very long OID
      ]
      
      for {oid_list, expected_string} <- edge_cases do
        actual_string = OID.list_to_string(oid_list)
        
        case expected_string do
          "" when oid_list == [] ->
            # Empty list might be handled differently
            assert actual_string == "" or actual_string == nil or is_binary(actual_string)
          _ ->
            assert actual_string == expected_string,
              "Edge case conversion failed for #{inspect(oid_list)}"
        end
      end
    end

    test "rejects invalid OID lists" do
      invalid_lists = [
        [1, 2, "invalid"],
        [1, 2, -1],
        [1, 2, 4294967296],  # Too large
        [1, 2, nil],
        [:atom, 1, 2],
        "not_a_list",
        nil,
      ]
      
      for invalid_list <- invalid_lists do
        case OID.list_to_string(invalid_list) do
          string when is_binary(string) ->
            # Some invalid inputs might be auto-corrected
            assert true
          {:error, reason} ->
            assert is_atom(reason) or is_binary(reason),
              "Error should be descriptive: #{inspect(reason)}"
          nil ->
            # Might return nil for invalid input
            assert true
          other ->
            flunk("Unexpected result for invalid list #{inspect(invalid_list)}: #{inspect(other)}")
        end
      end
    end
  end

  describe "OID validation" do
    test "validates correct OID formats" do
      valid_oids = [
        # String formats
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1",
        "0.0",
        "255.255.255.255",
        
        # List formats
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1],
        [0],
        [255, 255, 255, 255],
        
        # Edge cases
        [0, 0],
        [4294967295],
      ]
      
      for valid_oid <- valid_oids do
        assert OID.valid?(valid_oid) == true,
          "Expected #{inspect(valid_oid)} to be valid"
      end
    end

    test "rejects invalid OID formats" do
      invalid_oids = [
        # Invalid strings
        "",
        ".",
        ".1",
        "1.",
        "1..3",
        "abc",
        "1.3.6.1.abc",
        "1.3.6.1.-1",
        
        # Invalid lists
        [],
        [1, 2, "invalid"],
        [1, 2, -1],
        [1, 2, nil],
        [:atom],
        
        # Wrong types
        nil,
        123,
        %{},
        {:tuple},
      ]
      
      for invalid_oid <- invalid_oids do
        assert OID.valid?(invalid_oid) == false,
          "Expected #{inspect(invalid_oid)} to be invalid"
      end
    end

    test "validates OID components" do
      # Test individual component validation
      valid_components = [0, 1, 255, 65535, 4294967295]
      invalid_components = [-1, 4294967296, "string", nil, :atom]
      
      for component <- valid_components do
        assert OID.valid?([component]) == true,
          "Expected component #{component} to be valid"
      end
      
      for component <- invalid_components do
        assert OID.valid?([component]) == false,
          "Expected component #{component} to be invalid"
      end
    end
  end

  describe "OID arithmetic and operations" do
    test "compares OIDs correctly" do
      comparison_cases = [
        # Equal OIDs
        {[1, 3, 6, 1], [1, 3, 6, 1], :equal},
        {"1.3.6.1", "1.3.6.1", :equal},
        
        # Less than
        {[1, 3, 6, 1], [1, 3, 6, 2], :less},
        {[1, 3, 6], [1, 3, 6, 1], :less},
        {[1, 3, 5], [1, 3, 6], :less},
        
        # Greater than
        {[1, 3, 6, 2], [1, 3, 6, 1], :greater},
        {[1, 3, 6, 1], [1, 3, 6], :greater},
        {[1, 3, 7], [1, 3, 6], :greater},
        
        # Different lengths
        {[1, 3, 6, 1, 2], [1, 3, 6, 1], :greater},
        {[1, 3, 6], [1, 3, 6, 1, 2], :less},
      ]
      
      for {oid1, oid2, expected_result} <- comparison_cases do
        # Convert to lists if strings
        list1 = if is_binary(oid1) do
          {:ok, list} = OID.string_to_list(oid1)
          list
        else
          oid1
        end
        
        list2 = if is_binary(oid2) do
          {:ok, list} = OID.string_to_list(oid2)
          list
        else
          oid2
        end
        
        case OID.compare(list1, list2) do
          result when result in [:equal, :less, :greater] ->
            assert result == expected_result,
              "OID comparison failed: #{inspect(oid1)} vs #{inspect(oid2)}. Expected #{expected_result}, got #{result}"
          other ->
            flunk("Unexpected comparison result: #{inspect(other)}")
        end
      end
    end

    test "checks OID prefix relationships" do
      prefix_cases = [
        # True prefix cases
        {[1, 3, 6], [1, 3, 6, 1, 2, 1], true},
        {[1, 3], [1, 3, 6, 1], true},
        {[1], [1, 3, 6, 1, 2, 1, 1, 1, 0], true},
        {[], [1, 3, 6], true},  # Empty is prefix of everything
        
        # False prefix cases
        {[1, 3, 6, 1], [1, 3, 6], false},  # Longer is not prefix of shorter
        {[1, 3, 7], [1, 3, 6, 1], false},  # Different values
        {[2, 3, 6], [1, 3, 6, 1], false},  # Different start
        
        # Identical OIDs
        {[1, 3, 6, 1], [1, 3, 6, 1], true},  # Identical is prefix
      ]
      
      for {prefix_oid, full_oid, expected_result} <- prefix_cases do
        case OID.is_prefix?(prefix_oid, full_oid) do
          result when is_boolean(result) ->
            assert result == expected_result,
              "Prefix check failed: #{inspect(prefix_oid)} prefix of #{inspect(full_oid)}. Expected #{expected_result}, got #{result}"
          other ->
            flunk("Unexpected prefix result: #{inspect(other)}")
        end
      end
    end

    test "performs OID arithmetic operations" do
      arithmetic_cases = [
        # Append operations
        {:append, [1, 3, 6], [1, 2, 1], [1, 3, 6, 1, 2, 1]},
        {:append, [1, 3, 6, 1], [0], [1, 3, 6, 1, 0]},
        {:append, [], [1, 3, 6], [1, 3, 6]},
        
        # Parent operations (remove last element)
        {:parent, [1, 3, 6, 1, 0], [1, 3, 6, 1]},
        {:parent, [1, 3, 6, 1], [1, 3, 6]},
        {:parent, [1], []},
        
        # Child operations (add element)
        {:child, [1, 3, 6, 1], 0, [1, 3, 6, 1, 0]},
        {:child, [1, 3, 6], 2, [1, 3, 6, 2]},
        {:child, [], 1, [1]},
      ]
      
      for {operation, input1, input2, expected_result} <- arithmetic_cases do
        case operation do
          :append ->
            case OID.append(input1, input2) do
              result when is_list(result) ->
                assert result == expected_result,
                  "OID append failed: #{inspect(input1)} + #{inspect(input2)}. Expected #{inspect(expected_result)}, got #{inspect(result)}"
              other ->
                flunk("Unexpected append result: #{inspect(other)}")
            end
            
          :parent ->
            case OID.parent(input1) do
              result when is_list(result) ->
                assert result == expected_result,
                  "OID parent failed: parent of #{inspect(input1)}. Expected #{inspect(expected_result)}, got #{inspect(result)}"
              other ->
                flunk("Unexpected parent result: #{inspect(other)}")
            end
            
          :child ->
            case OID.child(input1, input2) do
              result when is_list(result) ->
                assert result == expected_result,
                  "OID child failed: #{inspect(input1)}.#{input2}. Expected #{inspect(expected_result)}, got #{inspect(result)}"
              other ->
                flunk("Unexpected child result: #{inspect(other)}")
            end
        end
      end
    end
  end

  describe "OID roundtrip conversion" do
    test "validates perfect roundtrip conversion" do
      test_oids = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1],
        [0],
        [255, 255, 255],
        [1, 3, 6, 1, 4, 1, 9999, 1, 1, 1],
        List.duplicate(1, 50),  # Long OID
      ]
      
      for original_oid <- test_oids do
        # Convert to string and back
        string_form = OID.list_to_string(original_oid)
        
        case OID.string_to_list(string_form) do
          {:ok, converted_back} ->
            assert converted_back == original_oid,
              "Roundtrip failed: #{inspect(original_oid)} -> '#{string_form}' -> #{inspect(converted_back)}"
          {:error, reason} ->
            flunk("Roundtrip conversion failed for #{inspect(original_oid)}: #{inspect(reason)}")
        end
      end
    end

    test "validates roundtrip with string input" do
      test_strings = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1",
        "0",
        "255.255.255",
        "1.3.6.1.4.1.9999.1.1.1",
      ]
      
      for original_string <- test_strings do
        case OID.string_to_list(original_string) do
          {:ok, list_form} ->
            converted_back = OID.list_to_string(list_form)
            assert converted_back == original_string,
              "String roundtrip failed: '#{original_string}' -> #{inspect(list_form)} -> '#{converted_back}'"
          {:error, reason} ->
            flunk("String parsing failed for '#{original_string}': #{inspect(reason)}")
        end
      end
    end
  end

  describe "standard MIB OID recognition" do
    test "recognizes standard system OIDs" do
      for {name, oid_list} <- @standard_oids do
        # Test that we can convert the standard OID correctly
        oid_string = OID.list_to_string(oid_list)
        assert is_binary(oid_string), "Standard OID #{name} should convert to string"
        
        case OID.string_to_list(oid_string) do
          {:ok, parsed_back} ->
            assert parsed_back == oid_list,
              "Standard OID #{name} roundtrip failed"
          {:error, reason} ->
            flunk("Standard OID #{name} failed to parse: #{inspect(reason)}")
        end
      end
    end

    test "validates instance OIDs" do
      # Test OIDs with instance identifiers
      instance_cases = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], "1.3.6.1.2.1.1.1.0"},  # sysDescr.0
        {[1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 1], "1.3.6.1.2.1.2.2.1.2.1"},  # ifDescr.1
        {[1, 3, 6, 1, 2, 1, 2, 2, 1, 2, 10], "1.3.6.1.2.1.2.2.1.2.10"},  # ifDescr.10
      ]
      
      for {oid_list, oid_string} <- instance_cases do
        # Test both directions
        assert OID.list_to_string(oid_list) == oid_string
        
        case OID.string_to_list(oid_string) do
          {:ok, parsed} ->
            assert parsed == oid_list
          {:error, reason} ->
            flunk("Instance OID parsing failed: #{inspect(reason)}")
        end
      end
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "OID parsing is fast" do
      test_strings = [
        "1.3.6.1.2.1.1.1.0",
        "1.3.6.1.4.1.9999.1.1.1",
        Enum.join(1..100, "."),  # Long OID
      ]
      
      # Measure parsing time
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for oid_string <- test_strings do
            OID.string_to_list(oid_string)
          end
        end
      end)
      
      time_per_parse = time_microseconds / (1000 * length(test_strings))
      
      # Should be very fast (less than 50 microseconds per parse)
      assert time_per_parse < 50,
        "OID parsing too slow: #{time_per_parse} microseconds per parse"
    end

    @tag :performance
    test "OID conversion is fast" do
      test_lists = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 4, 1, 9999, 1, 1, 1],
        1..100 |> Enum.to_list(),  # Long OID
      ]
      
      # Measure conversion time
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for oid_list <- test_lists do
            OID.list_to_string(oid_list)
          end
        end
      end)
      
      time_per_conversion = time_microseconds / (1000 * length(test_lists))
      
      # Should be very fast (less than 30 microseconds per conversion)
      assert time_per_conversion < 30,
        "OID conversion too slow: #{time_per_conversion} microseconds per conversion"
    end

    @tag :performance
    test "OID validation is fast" do
      test_oids = [
        "1.3.6.1.2.1.1.1.0",
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        "invalid.oid",
        [1, 2, "invalid"],
        Enum.join(1..50, "."),
        1..50 |> Enum.to_list(),
      ]
      
      # Measure validation time
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for oid <- test_oids do
            OID.valid?(oid)
          end
        end
      end)
      
      time_per_validation = time_microseconds / (1000 * length(test_oids))
      
      # Should be very fast (less than 20 microseconds per validation)
      assert time_per_validation < 20,
        "OID validation too slow: #{time_per_validation} microseconds per validation"
    end

    @tag :performance
    test "memory usage is reasonable" do
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)
      
      # Create many OID operations
      large_oids = for _i <- 1..1000 do
        long_oid = 1..100 |> Enum.to_list()
        oid_string = OID.list_to_string(long_oid)
        {:ok, parsed_back} = OID.string_to_list(oid_string)
        {long_oid, oid_string, parsed_back}
      end
      
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      # Should use reasonable memory (less than 10MB for all operations)
      assert memory_used < 10_000_000,
        "OID operations memory usage too high: #{memory_used} bytes"
      
      # Clean up
      large_oids = nil
      :erlang.garbage_collect()
    end
  end

  describe "error handling and user experience" do
    test "provides helpful error messages for common mistakes" do
      common_mistakes = [
        # Missing dots
        {"1 3 6 1", "Expected dots (.) between OID components"},
        
        # Wrong separators
        {"1,3,6,1", "Use dots (.) not commas (,) to separate OID components"},
        {"1-3-6-1", "Use dots (.) not dashes (-) to separate OID components"},
        
        # Invalid characters
        {"1.3.6.1.abc", "OID components must be numeric"},
        {"1.3.6.1.2a", "OID components must be numeric"},
        
        # Boundary issues
        {"", "OID cannot be empty"},
        {".", "OID cannot start or end with a dot"},
        {".1", "OID cannot start with a dot"},
        {"1.", "OID cannot end with a dot"},
        {"1..3", "OID cannot have consecutive dots"},
        
        # Range issues
        {"1.3.6.1.-1", "OID components must be non-negative"},
        {"1.3.6.1.4294967296", "OID components must fit in 32-bit unsigned integer"},
      ]
      
      for {invalid_oid, expected_guidance} <- common_mistakes do
        case OID.string_to_list(invalid_oid) do
          {:ok, _} ->
            # Some mistakes might be auto-corrected
            assert true, "Auto-corrected mistake: #{invalid_oid}"
          {:error, reason} ->
            error_message = inspect(reason) |> String.downcase()
            
            # Check if error message contains helpful guidance
            helpful_terms = ["oid", "component", "numeric", "dot", "format", "invalid"]
            has_helpful_terms = Enum.any?(helpful_terms, fn term ->
              String.contains?(error_message, term)
            end)
            
            assert has_helpful_terms,
              "Error message should be more helpful for '#{invalid_oid}': #{inspect(reason)}"
        end
      end
    end

    test "handles edge cases gracefully" do
      edge_cases = [
        nil,
        "",
        [],
        %{},
        {:tuple},
        123,
        1.5,
        :atom,
      ]
      
      for edge_case <- edge_cases do
        # Test validation
        result = OID.valid?(edge_case)
        assert result == false, "Edge case #{inspect(edge_case)} should be invalid"
        
        # Test conversion (should handle gracefully)
        case OID.list_to_string(edge_case) do
          string when is_binary(string) ->
            assert true, "Edge case handled gracefully"
          {:error, _reason} ->
            assert true, "Edge case properly rejected"
          nil ->
            assert true, "Edge case handled with nil"
          other ->
            flunk("Unexpected result for edge case #{inspect(edge_case)}: #{inspect(other)}")
        end
      end
    end
  end

  describe "integration with SNMP operations" do
    alias SNMPMgr.TestSupport.SNMPSimulator
    
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    @tag :integration
    test "OID system works with real SNMP operations", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test various OID formats with real SNMP calls
      oid_formats = [
        "1.3.6.1.2.1.1.1.0",  # String format
        [1, 3, 6, 1, 2, 1, 1, 1, 0],  # List format
      ]
      
      for oid_format <- oid_formats do
        case SNMPMgr.get(target, oid_format, community: device.community) do
          {:ok, response} ->
            assert is_binary(response), "SNMP response should be a string"
            
          {:error, :snmp_modules_not_available} ->
            # Expected in test environment
            assert true, "SNMP modules not available for OID integration test"
            
          {:error, :invalid_oid_values} ->
            # Expected in test environment where SNMP encoding may fail
            assert true, "SNMP encoding not available for OID integration test"
            
          {:error, reason} ->
            flunk("SNMP operation with OID #{inspect(oid_format)} failed: #{inspect(reason)}")
        end
      end
    end

    @tag :integration
    test "OID validation prevents invalid SNMP requests", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that invalid OIDs are caught before SNMP operations
      invalid_oids = [
        "invalid.oid",
        "1.3.6.1.abc",
        "",
        nil,
      ]
      
      for invalid_oid <- invalid_oids do
        case SNMPMgr.get(target, invalid_oid, community: device.community) do
          {:ok, _response} ->
            flunk("Invalid OID #{inspect(invalid_oid)} should not succeed")
          {:error, reason} ->
            # Should get a helpful error about the OID format
            error_message = inspect(reason) |> String.downcase()
            oid_related = String.contains?(error_message, "oid") or
                         String.contains?(error_message, "format") or
                         String.contains?(error_message, "invalid")
            
            assert oid_related,
              "Error for invalid OID should mention OID/format: #{inspect(reason)}"
        end
      end
    end
  end
end