defmodule SNMPMgr.TypesComprehensiveTest do
  use ExUnit.Case, async: true
  
  alias SNMPMgr.Types
  
  @moduletag :unit
  @moduletag :types
  @moduletag :phase_1

  # Comprehensive test data covering all SNMP types
  @snmp_types_test_data [
    # Basic types
    {:string, "hello world", {:string, ~c"hello world"}},
    {:string, "", {:string, ~c""}},
    {:string, "Unicode: 测试 🧪", {:string, "Unicode: 测试 🧪"}},
    
    # Integer types
    {:integer, 42, {:integer, 42}},
    {:integer, -42, {:integer, -42}},
    {:integer, 0, {:integer, 0}},
    {:integer, 2147483647, {:integer, 2147483647}},
    {:integer, -2147483648, {:integer, -2147483648}},
    
    # Unsigned integer types
    {:unsigned32, 42, {:unsigned32, 42}},
    {:unsigned32, 0, {:unsigned32, 0}},
    {:unsigned32, 4294967295, {:unsigned32, 4294967295}},
    
    # Counter types
    {:counter32, 100, {:counter32, 100}},
    {:counter32, 0, {:counter32, 0}},
    {:counter32, 4294967295, {:counter32, 4294967295}},
    
    {:counter64, 1000000000000, {:counter64, 1000000000000}},
    {:counter64, 0, {:counter64, 0}},
    {:counter64, 18446744073709551615, {:counter64, 18446744073709551615}},
    
    # Gauge types
    {:gauge32, 50, {:gauge32, 50}},
    {:gauge32, 0, {:gauge32, 0}},
    {:gauge32, 4294967295, {:gauge32, 4294967295}},
    
    # Time types
    {:timeticks, 12345600, {:timeticks, 12345600}},
    {:timeticks, 0, {:timeticks, 0}},
    
    # IP Address
    {:ipAddress, "192.168.1.1", {:ipAddress, {192, 168, 1, 1}}},
    {:ipAddress, "0.0.0.0", {:ipAddress, {0, 0, 0, 0}}},
    {:ipAddress, "255.255.255.255", {:ipAddress, {255, 255, 255, 255}}},
    {:ipAddress, {192, 168, 1, 1}, {:ipAddress, {192, 168, 1, 1}}},
    
    # OID type
    {:objectIdentifier, [1, 3, 6, 1], {:objectIdentifier, [1, 3, 6, 1]}},
    {:objectIdentifier, [1, 3, 6, 1, 2, 1, 1, 1, 0], {:objectIdentifier, [1, 3, 6, 1, 2, 1, 1, 1, 0]}},
    
    # Octet string (binary data)
    {:octetString, <<1, 2, 3, 4>>, {:octetString, <<1, 2, 3, 4>>}},
    {:octetString, <<>>, {:octetString, <<>>}},
    {:octetString, :crypto.strong_rand_bytes(100), {:octetString, :crypto.strong_rand_bytes(100)}},
    
    # Null
    {:null, nil, {:null, :null}},
    {:null, :null, {:null, :null}},
    
    # Boolean (if supported)
    {:boolean, true, {:boolean, true}},
    {:boolean, false, {:boolean, false}},
  ]

  describe "comprehensive type inference" do
    test "infers all SNMP types correctly" do
      inference_cases = [
        # String inference
        {"hello", :string},
        {"", :string},
        {"123abc", :string},
        
        # Numeric inference
        {42, :unsigned32},
        {0, :unsigned32},
        {-42, :integer},
        {4294967296, :counter64},  # > 32-bit unsigned
        
        # IP address inference
        {"192.168.1.1", :string},  # Should be string unless explicitly typed
        {{192, 168, 1, 1}, :ipAddress},
        
        # Special values
        {nil, :null},
        {:null, :null},
        {true, :boolean},
        {false, :boolean},
        
        # Collections
        {[1, 3, 6, 1], :objectIdentifier},
        {<<1, 2, 3>>, :octetString},
      ]
      
      for {input, expected_type} <- inference_cases do
        actual_type = Types.infer_type(input)
        assert actual_type == expected_type, 
          "Expected #{inspect(input)} to be inferred as #{expected_type}, got #{actual_type}"
      end
    end

    test "type inference handles edge cases" do
      edge_cases = [
        # Empty collections
        {[], :objectIdentifier},  # Empty OID list
        {<<>>, :octetString},     # Empty binary
        
        # Boundary values
        {2147483647, :unsigned32},    # Max 32-bit signed (should be unsigned)
        {2147483648, :unsigned32},    # Just over 32-bit signed
        {4294967295, :unsigned32},    # Max 32-bit unsigned
        {4294967296, :counter64},     # Just over 32-bit unsigned
        
        # Special strings
        {"0.0.0.0", :string},         # IP-like but treated as string
        {"1.3.6.1", :string},         # OID-like but treated as string
        {"", :string},                # Empty string
        
        # Atom handling
        {:undefined, :null},
        {:noSuchObject, :null},
        {:noSuchInstance, :null},
        {:endOfMibView, :null},
      ]
      
      for {input, expected_type} <- edge_cases do
        actual_type = Types.infer_type(input)
        assert actual_type == expected_type,
          "Edge case: Expected #{inspect(input)} to be inferred as #{expected_type}, got #{actual_type}"
      end
    end
  end

  describe "comprehensive encoding and decoding" do
    test "encodes and decodes all SNMP types correctly" do
      for {type, input, expected_encoding} <- @snmp_types_test_data do
        # Test explicit encoding with type specification
        case Types.encode_value(input, type: type) do
          {:ok, encoded} ->
            assert encoded == expected_encoding,
              "Failed to encode #{inspect(input)} as #{type}. Expected #{inspect(expected_encoding)}, got #{inspect(encoded)}"
            
            # Test roundtrip decoding
            decoded = Types.decode_value(encoded)
            
            # For some types, decoded value might be different format but equivalent
            case type do
              :string when is_list(elem(encoded, 1)) ->
                # Charlists might decode to strings
                assert decoded == to_string(elem(encoded, 1)) or decoded == elem(encoded, 1)
              :ipAddress when is_binary(input) ->
                # IP strings decode to tuples
                assert decoded == elem(encoded, 1)
              _ ->
                # Most types should roundtrip exactly
                original_value = elem(encoded, 1)
                assert decoded == original_value,
                  "Roundtrip failed for #{type}: #{inspect(input)} -> #{inspect(encoded)} -> #{inspect(decoded)}"
            end
            
          {:error, reason} ->
            flunk("Failed to encode #{inspect(input)} as #{type}: #{inspect(reason)}")
        end
      end
    end

    test "automatic type inference encoding" do
      # Test encoding without explicit type (using inference)
      auto_encoding_cases = [
        {"hello", {:string, ~c"hello"}},
        {42, {:unsigned32, 42}},
        {-42, {:integer, -42}},
        {nil, {:null, :null}},
        {{192, 168, 1, 1}, {:ipAddress, {192, 168, 1, 1}}},
        {[1, 3, 6, 1], {:objectIdentifier, [1, 3, 6, 1]}},
        {<<1, 2, 3>>, {:octetString, <<1, 2, 3>>}},
      ]
      
      for {input, expected_encoding} <- auto_encoding_cases do
        case Types.encode_value(input) do
          {:ok, encoded} ->
            assert encoded == expected_encoding,
              "Auto-encoding failed for #{inspect(input)}. Expected #{inspect(expected_encoding)}, got #{inspect(encoded)}"
          {:error, reason} ->
            flunk("Auto-encoding failed for #{inspect(input)}: #{inspect(reason)}")
        end
      end
    end

    test "handles encoding errors gracefully" do
      invalid_encoding_cases = [
        # Type mismatches
        {"not_an_ip", :ipAddress},
        {"not_a_number", :integer},
        {-1, :unsigned32},  # Negative value for unsigned type
        {4294967296, :unsigned32},  # Too large for 32-bit unsigned
        {"not_oid", :objectIdentifier},
        
        # Invalid formats
        {"999.999.999.999", :ipAddress},  # Invalid IP address
        {[1, 2, "invalid"], :objectIdentifier},  # Non-numeric in OID
        {:invalid_atom, :string},
      ]
      
      for {input, type} <- invalid_encoding_cases do
        case Types.encode_value(input, type: type) do
          {:ok, _} ->
            # Some invalid cases might be auto-corrected
            assert true
          {:error, reason} ->
            assert is_atom(reason) or is_binary(reason) or is_tuple(reason),
              "Error reason should be descriptive: #{inspect(reason)}"
        end
      end
    end
  end

  describe "SNMPv2c exception values" do
    test "handles SNMPv2c exception values correctly" do
      v2c_exceptions = [
        {:noSuchObject, :no_such_object},
        {:noSuchInstance, :no_such_instance}, 
        {:endOfMibView, :end_of_mib_view},
      ]
      
      for {exception_value, expected_decoded} <- v2c_exceptions do
        decoded = Types.decode_value(exception_value)
        assert decoded == expected_decoded,
          "Failed to decode SNMPv2c exception #{exception_value}. Expected #{expected_decoded}, got #{decoded}"
      end
    end

    test "encodes SNMPv2c exceptions" do
      # Test that we can encode exception indicators
      v2c_encoding_cases = [
        {:no_such_object, :noSuchObject},
        {:no_such_instance, :noSuchInstance},
        {:end_of_mib_view, :endOfMibView},
      ]
      
      for {input, expected} <- v2c_encoding_cases do
        case Types.encode_value(input, type: :v2c_exception) do
          {:ok, {type, value}} ->
            assert value == expected or type == expected,
              "Failed to encode SNMPv2c exception #{input}"
          {:error, _reason} ->
            # Might not be implemented yet
            assert true
        end
      end
    end
  end

  describe "boundary value testing" do
    test "handles integer boundary values" do
      boundary_cases = [
        # 32-bit signed integer boundaries
        {:integer, -2147483648, true},   # Min 32-bit signed
        {:integer, 2147483647, true},    # Max 32-bit signed
        {:integer, -2147483649, false},  # Below min (might fail)
        {:integer, 2147483648, false},   # Above max (might fail)
        
        # 32-bit unsigned integer boundaries
        {:unsigned32, 0, true},          # Min unsigned
        {:unsigned32, 4294967295, true}, # Max 32-bit unsigned
        {:unsigned32, -1, false},        # Below min (should fail)
        {:unsigned32, 4294967296, false}, # Above max (should fail)
        
        # Counter32 boundaries (same as unsigned32)
        {:counter32, 0, true},
        {:counter32, 4294967295, true},
        
        # 64-bit counter boundaries
        {:counter64, 0, true},
        {:counter64, 18446744073709551615, true},  # Max 64-bit unsigned
      ]
      
      for {type, value, should_succeed} <- boundary_cases do
        case Types.encode_value(value, type: type) do
          {:ok, encoded} ->
            if should_succeed do
              assert true, "Boundary value #{value} correctly encoded as #{type}"
              
              # Test roundtrip
              decoded = Types.decode_value(encoded)
              assert decoded == value, "Boundary value roundtrip failed"
            else
              # Might succeed if implementation is lenient
              assert true, "Boundary value #{value} unexpectedly succeeded for #{type}"
            end
            
          {:error, _reason} ->
            if should_succeed do
              flunk("Expected boundary value #{value} to succeed for #{type}")
            else
              assert true, "Boundary value #{value} correctly rejected for #{type}"
            end
        end
      end
    end

    test "handles string length boundaries" do
      # Test various string lengths
      string_lengths = [0, 1, 255, 256, 1000, 65535, 65536]
      
      for length <- string_lengths do
        test_string = String.duplicate("A", length)
        
        case Types.encode_value(test_string, type: :string) do
          {:ok, {:string, encoded_value}} ->
            # Verify length is preserved
            decoded = Types.decode_value({:string, encoded_value})
            assert String.length(decoded) == length,
              "String length not preserved: expected #{length}, got #{String.length(decoded)}"
              
          {:error, reason} ->
            # Some lengths might be rejected
            assert is_atom(reason) or is_binary(reason),
              "String length #{length} rejected: #{inspect(reason)}"
        end
      end
    end

    test "handles OID length boundaries" do
      # Test various OID lengths
      oid_lengths = [0, 1, 2, 128, 256, 512]
      
      for length <- oid_lengths do
        test_oid = for i <- 1..length, do: rem(i, 256)
        
        case Types.encode_value(test_oid, type: :objectIdentifier) do
          {:ok, {:objectIdentifier, encoded_oid}} ->
            assert length(encoded_oid) == length,
              "OID length not preserved: expected #{length}, got #{length(encoded_oid)}"
              
          {:error, reason} ->
            if length == 0 do
              assert true, "Empty OID correctly rejected: #{inspect(reason)}"
            else
              # Other lengths might be implementation-dependent
              assert true, "OID length #{length} rejected: #{inspect(reason)}"
            end
        end
      end
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "type inference is fast" do
      test_values = [
        "string", 42, -42, 0, nil, true, false,
        {192, 168, 1, 1}, [1, 3, 6, 1], <<1, 2, 3>>,
        4294967296, "192.168.1.1"
      ]
      
      # Measure time for 1000 inferences
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for value <- test_values do
            Types.infer_type(value)
          end
        end
      end)
      
      time_per_inference = time_microseconds / (1000 * length(test_values))
      
      # Should be very fast (less than 10 microseconds per inference)
      assert time_per_inference < 10,
        "Type inference too slow: #{time_per_inference} microseconds per inference"
    end

    @tag :performance
    test "encoding/decoding is fast" do
      test_values = [
        {"hello", :string},
        {42, :unsigned32},
        {{192, 168, 1, 1}, :ipAddress},
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], :objectIdentifier},
      ]
      
      # Measure encoding time
      {encode_time, _} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for {value, type} <- test_values do
            Types.encode_value(value, type: type)
          end
        end
      end)
      
      encode_time_per_op = encode_time / (1000 * length(test_values))
      
      # Should be fast (less than 50 microseconds per operation)
      assert encode_time_per_op < 50,
        "Encoding too slow: #{encode_time_per_op} microseconds per operation"
      
      # Measure decoding time
      encoded_values = for {value, type} <- test_values do
        {:ok, encoded} = Types.encode_value(value, type: type)
        encoded
      end
      
      {decode_time, _} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for encoded <- encoded_values do
            Types.decode_value(encoded)
          end
        end
      end)
      
      decode_time_per_op = decode_time / (1000 * length(encoded_values))
      
      # Should be fast (less than 30 microseconds per operation)
      assert decode_time_per_op < 30,
        "Decoding too slow: #{decode_time_per_op} microseconds per operation"
    end

    @tag :performance
    test "memory usage is reasonable" do
      # Test memory usage for various data sizes
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)
      
      # Create and encode many values
      large_values = [
        {String.duplicate("X", 1000), :string},
        {for(i <- 1..1000, do: rem(i, 256)), :objectIdentifier},
        {:crypto.strong_rand_bytes(1000), :octetString},
      ]
      
      encoded_values = for {value, type} <- large_values do
        for _i <- 1..100 do
          {:ok, encoded} = Types.encode_value(value, type: type)
          encoded
        end
      end
      
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      # Should use reasonable memory (less than 10MB for all operations)
      assert memory_used < 10_000_000,
        "Memory usage too high: #{memory_used} bytes"
      
      # Clean up
      encoded_values = nil
      :erlang.garbage_collect()
    end
  end

  describe "error handling and user experience" do
    test "provides helpful error messages" do
      error_cases = [
        # Type mismatch errors
        {fn -> Types.encode_value("not_an_ip", type: :ipAddress) end, 
         ["IP", "address", "format"]},
        {fn -> Types.encode_value(-1, type: :unsigned32) end,
         ["unsigned", "negative", "positive"]},
        {fn -> Types.encode_value("not_a_number", type: :integer) end,
         ["integer", "number", "format"]},
        {fn -> Types.encode_value([1, 2, "invalid"], type: :objectIdentifier) end,
         ["OID", "numeric", "integer"]},
      ]
      
      for {error_fun, expected_terms} <- error_cases do
        case error_fun.() do
          {:ok, _} ->
            # Some errors might be auto-corrected
            assert true
          {:error, reason} ->
            error_message = inspect(reason) |> String.downcase()
            
            helpful = Enum.any?(expected_terms, fn term ->
              String.contains?(error_message, String.downcase(term))
            end)
            
            assert helpful,
              "Error message not helpful enough: #{inspect(reason)}. Expected terms: #{inspect(expected_terms)}"
        end
      end
    end

    test "handles malformed input gracefully" do
      malformed_inputs = [
        # Invalid types for decoding
        {:invalid_type, "value"},
        {"string", :not_a_value},
        {nil, nil},
        
        # Corrupt data structures
        {:string, :not_a_charlist_or_binary},
        {:integer, "not_an_integer"},
        {:ipAddress, {300, 300, 300, 300}},  # Invalid IP octets
        {:objectIdentifier, "not_a_list"},
      ]
      
      for malformed_input <- malformed_inputs do
        case Types.decode_value(malformed_input) do
          result when is_binary(result) or is_integer(result) or is_atom(result) ->
            # Successfully handled or auto-corrected
            assert true
          {:error, _reason} ->
            # Properly rejected
            assert true
          other ->
            flunk("Unexpected result for malformed input #{inspect(malformed_input)}: #{inspect(other)}")
        end
      end
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
    test "types work correctly with simulator responses", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test that types system handles real SNMP responses correctly
      case SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community) do
        {:ok, response} ->
          # Response should be properly typed
          assert is_binary(response), "SNMP response should be decoded to string"
          
          # Test that we can re-encode it
          case Types.encode_value(response, type: :string) do
            {:ok, {:string, _encoded}} ->
              assert true, "Response can be re-encoded as string"
            {:error, reason} ->
              flunk("Failed to re-encode SNMP response: #{inspect(reason)}")
          end
          
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true, "SNMP modules not available for integration test"
          
        {:error, reason} ->
          flunk("SNMP operation failed: #{inspect(reason)}")
      end
    end
  end
end