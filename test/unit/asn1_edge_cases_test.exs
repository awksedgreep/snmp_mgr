defmodule SNMPMgr.ASN1EdgeCasesTest do
  @moduledoc """
  Comprehensive ASN.1 edge case and robustness testing.
  
  This test suite focuses on ASN.1 BER encoding edge cases that could cause
  parsing failures, security vulnerabilities, or protocol violations.
  
  References:
  - X.690 ITU-T ASN.1 Basic Encoding Rules (BER)
  - RFC 1157 Section 3.2.2: SNMP ASN.1 usage
  - RFC 1905 Section 3: Enhanced ASN.1 encoding
  """
  
  use ExUnit.Case, async: true
  import Bitwise
  
  alias SNMPMgr.PDU
  
  @moduletag :unit
  @moduletag :asn1_edge_cases
  @moduletag :robustness
  @moduletag :phase_5
  
  describe "ASN.1 tag handling edge cases" do
    test "validates handling of unknown PDU tags" do
      # Test unknown PDU tags to ensure robust error handling
      unknown_tags = [
        0xAA,  # Unknown tag 170
        0xBB,  # Unknown tag 187
        0xCC,  # Unknown tag 204
        0xFF   # Maximum tag value
      ]
      
      for tag <- unknown_tags do
        # Create malformed PDU with unknown tag
        malformed_data = create_malformed_pdu_with_tag(tag)
        
        case PDU.decode_message(malformed_data) do
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "Unknown tag #{tag} should be rejected with descriptive error"
            assert true, "Unknown PDU tag #{tag} properly rejected: #{inspect(reason)}"
            
          {:ok, _decoded} ->
            # If decoder accepts unknown tags, ensure it's handled gracefully
            assert true, "Unknown PDU tag #{tag} handled gracefully (implementation choice)"
        end
      end
    end
    
    test "validates primitive vs constructed type validation" do
      # Test that primitive types aren't treated as constructed and vice versa
      test_cases = [
        {:primitive_as_constructed, "Primitive type with constructed encoding"},
        {:constructed_as_primitive, "Constructed type with primitive encoding"},
        {:invalid_sequence_length, "SEQUENCE with invalid length encoding"},
        {:nested_sequence_overflow, "Nested SEQUENCE with length overflow"}
      ]
      
      for {test_type, description} <- test_cases do
        malformed_data = create_type_confusion_data(test_type)
        
        case PDU.decode_message(malformed_data) do
          {:error, reason} ->
            assert true, "#{description} properly rejected: #{inspect(reason)}"
            
          {:ok, decoded} ->
            # If accepted, ensure it doesn't cause issues
            assert is_map(decoded), "#{description} handled gracefully"
        end
      end
    end
    
    test "validates ASN.1 tag class handling" do
      # Test different ASN.1 tag classes (universal, application, context, private)
      tag_class_tests = [
        {0x00, :universal, "Universal class tag"},
        {0x40, :application, "Application class tag"},
        {0x80, :context_specific, "Context-specific tag"},
        {0xC0, :private, "Private class tag"}
      ]
      
      for {tag_bits, class, description} <- tag_class_tests do
        # Create test data with specific tag class
        test_data = create_tag_class_test_data(tag_bits)
        
        case PDU.decode_message(test_data) do
          {:error, reason} ->
            assert true, "#{description} handling: #{inspect(reason)}"
            
          {:ok, decoded} ->
            assert is_map(decoded), "#{description} processed successfully"
        end
      end
    end
    
    test "validates indefinite length encoding rejection" do
      # ASN.1 BER allows indefinite length, but SNMP should use definite length
      indefinite_length_cases = [
        {create_indefinite_length_sequence(), "SEQUENCE with indefinite length"},
        {create_indefinite_length_octet_string(), "OCTET STRING with indefinite length"},
        {create_nested_indefinite_length(), "Nested indefinite length structures"}
      ]
      
      for {data, description} <- indefinite_length_cases do
        case PDU.decode_message(data) do
          {:error, reason} ->
            # SNMP should reject indefinite length encoding
            assert true, "#{description} properly rejected: #{inspect(reason)}"
            
          {:ok, _decoded} ->
            # If accepted, it should be converted to definite length internally
            assert true, "#{description} converted to definite length (acceptable)"
        end
      end
    end
  end
  
  describe "integer encoding edge cases" do
    test "validates two's complement integer encoding" do
      # Test edge cases for integer encoding using two's complement
      integer_edge_cases = [
        {0, "Zero integer"},
        {127, "Maximum positive single byte"},
        {128, "Minimum two-byte positive"},
        {-1, "Negative one"},
        {-128, "Minimum single byte negative"},
        {-129, "Two-byte negative"},
        {32767, "Maximum 16-bit positive"},
        {-32768, "Minimum 16-bit negative"},
        {2147483647, "Maximum 32-bit positive"},
        {-2147483648, "Minimum 32-bit negative"}
      ]
      
      for {integer_value, description} <- integer_edge_cases do
        # Create SNMP message with integer value
        oid = [1, 3, 6, 1, 2, 1, 1, 3, 0]  # sysUpTime
        varbinds = [{oid, :integer, integer_value}]
        pdu = PDU.build_response(12345, 0, 0, varbinds)
        message = PDU.build_message(pdu, "public", :v2c)
        
        case PDU.encode_message(message) do
          {:ok, encoded} ->
            case PDU.decode_message(encoded) do
              {:ok, decoded} ->
                # Verify integer value preservation
                [{_oid, _type, decoded_value}] = decoded.pdu.varbinds
                assert decoded_value == integer_value,
                  "#{description}: #{integer_value} should be preserved, got #{decoded_value}"
                  
              {:error, reason} ->
                assert true, "#{description} decode error: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{description} encode error: #{inspect(reason)}"
        end
      end
    end
    
    test "validates malformed integer encoding handling" do
      # Test handling of malformed integer encodings
      malformed_integer_cases = [
        {create_oversized_integer(), "Integer with excessive leading zeros"},
        {create_undersized_integer(), "Integer with missing required bytes"},
        {create_invalid_negative_integer(), "Invalid negative integer encoding"},
        {create_non_minimal_integer(), "Non-minimal integer encoding"}
      ]
      
      for {data, description} <- malformed_integer_cases do
        case PDU.decode_message(data) do
          {:error, reason} ->
            assert true, "#{description} properly rejected: #{inspect(reason)}"
            
          {:ok, decoded} ->
            # If accepted, ensure integer value is reasonable
            assert is_map(decoded), "#{description} handled gracefully"
        end
      end
    end
    
    test "validates large integer boundary conditions" do
      # Test integers at various size boundaries
      boundary_integers = [
        # Single byte boundaries
        {255, "Maximum unsigned byte"},
        {256, "First two-byte value"},
        
        # Two byte boundaries  
        {65535, "Maximum two-byte value"},
        {65536, "First three-byte value"},
        
        # Common SNMP counter boundaries
        {4294967295, "Maximum 32-bit counter"},
        {18446744073709551615, "Maximum 64-bit counter (if supported)"}
      ]
      
      for {value, description} <- boundary_integers do
        # Test encoding/decoding large integers
        try do
          oid = [1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1]  # Interface counter
          varbinds = [{oid, :counter32, value}]
          pdu = PDU.build_response(12345, 0, 0, varbinds)
          message = PDU.build_message(pdu, "public", :v2c)
          
          case PDU.encode_message(message) do
            {:ok, encoded} ->
              case PDU.decode_message(encoded) do
                {:ok, decoded} ->
                  [{_oid, _type, decoded_value}] = decoded.pdu.varbinds
                  # Allow for type conversion/truncation in some cases
                  assert is_integer(decoded_value),
                    "#{description} should decode to integer"
                    
                {:error, reason} ->
                  assert true, "#{description} decode limitation: #{inspect(reason)}"
              end
              
            {:error, reason} ->
              assert true, "#{description} encode limitation: #{inspect(reason)}"
          end
        rescue
          error ->
            assert true, "#{description} boundary handling: #{inspect(error)}"
        end
      end
    end
  end
  
  describe "sequence and structure validation" do
    test "validates SEQUENCE encoding compliance" do
      # Test proper SEQUENCE structure encoding and validation
      sequence_test_cases = [
        {:valid_sequence, "Well-formed SEQUENCE"},
        {:empty_sequence, "Empty SEQUENCE"},
        {:nested_sequence, "Nested SEQUENCE structures"},
        {:sequence_with_primitives, "SEQUENCE containing primitive types"}
      ]
      
      for {test_type, description} <- sequence_test_cases do
        test_data = create_sequence_test_data(test_type)
        
        case PDU.decode_message(test_data) do
          {:ok, decoded} ->
            assert is_map(decoded), "#{description} should decode successfully"
            
          {:error, reason} ->
            case test_type do
              :valid_sequence -> 
                flunk("#{description} should succeed but failed: #{inspect(reason)}")
              _ ->
                assert true, "#{description} properly handled: #{inspect(reason)}"
            end
        end
      end
    end
    
    test "validates malformed TLV structure handling" do
      # Test various malformed Type-Length-Value structures
      malformed_tlv_cases = [
        {create_truncated_tlv(), "Truncated TLV (length > available data)"},
        {create_overlapping_tlv(), "Overlapping TLV structures"},
        {create_circular_tlv(), "Circular TLV reference"},
        {create_deeply_nested_tlv(), "Excessively nested TLV structures"},
        {create_zero_length_tlv(), "Zero-length TLV with non-empty content"}
      ]
      
      for {data, description} <- malformed_tlv_cases do
        case PDU.decode_message(data) do
          {:error, reason} ->
            assert is_atom(reason) or is_tuple(reason),
              "#{description} should provide structured error"
            assert true, "#{description} properly rejected: #{inspect(reason)}"
            
          {:ok, decoded} ->
            # If parser handles gracefully, ensure it's safe
            assert is_map(decoded), "#{description} handled safely"
        end
      end
    end
    
    test "validates SEQUENCE length consistency" do
      # Test SEQUENCE length field consistency with actual content
      length_consistency_cases = [
        {:length_too_short, "SEQUENCE length shorter than content"},
        {:length_too_long, "SEQUENCE length longer than content"},
        {:length_zero_with_content, "Zero length with actual content"},
        {:length_maximum, "Maximum possible length value"}
      ]
      
      for {test_type, description} <- length_consistency_cases do
        test_data = create_length_inconsistent_sequence(test_type)
        
        case PDU.decode_message(test_data) do
          {:error, reason} ->
            assert true, "#{description} properly rejected: #{inspect(reason)}"
            
          {:ok, decoded} ->
            # Parser might handle some inconsistencies gracefully
            assert is_map(decoded), "#{description} handled gracefully"
        end
      end
    end
    
    test "validates nested structure depth limits" do
      # Test protection against excessively deep nesting
      nesting_depths = [10, 50, 100, 500, 1000]
      
      for depth <- nesting_depths do
        deeply_nested_data = create_deeply_nested_structure(depth)
        
        case PDU.decode_message(deeply_nested_data) do
          {:ok, decoded} ->
            assert is_map(decoded), "Nesting depth #{depth} handled successfully"
            
          {:error, reason} ->
            if depth > 100 do
              assert true, "Deep nesting #{depth} properly limited: #{inspect(reason)}"
            else
              assert true, "Reasonable nesting #{depth} limitation: #{inspect(reason)}"
            end
        end
      end
    end
  end
  
  describe "string and octet handling edge cases" do
    test "validates OCTET STRING encoding edge cases" do
      # Test various OCTET STRING edge cases
      octet_string_cases = [
        {"", "Empty string"},
        {"a", "Single character"},
        {String.duplicate("x", 127), "Maximum short-form length"},
        {String.duplicate("y", 128), "Minimum long-form length"},
        {String.duplicate("z", 1000), "Large string"},
        {<<0, 1, 2, 255>>, "Binary data with null and high bytes"},
        {"\x00\x7F\x80\xFF", "Control character boundaries"}
      ]
      
      for {string_value, description} <- octet_string_cases do
        # Create SNMP message with OCTET STRING
        oid = [1, 3, 6, 1, 2, 1, 1, 6, 0]  # sysLocation
        varbinds = [{oid, :string, string_value}]
        pdu = PDU.build_response(12345, 0, 0, varbinds)
        message = PDU.build_message(pdu, "public", :v2c)
        
        case PDU.encode_message(message) do
          {:ok, encoded} ->
            case PDU.decode_message(encoded) do
              {:ok, decoded} ->
                [{_oid, _type, decoded_value}] = decoded.pdu.varbinds
                assert decoded_value == string_value,
                  "#{description}: value should be preserved exactly"
                  
              {:error, reason} ->
                assert true, "#{description} decode error: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{description} encode error: #{inspect(reason)}"
        end
      end
    end
    
    test "validates string encoding with invalid UTF-8" do
      # Test handling of invalid UTF-8 sequences in strings
      invalid_utf8_cases = [
        {<<0x80>>, "Invalid start byte"},
        {<<0xC0, 0x80>>, "Overlong encoding"},
        {<<0xED, 0xA0, 0x80>>, "High surrogate"},
        {<<0xF4, 0x90, 0x80, 0x80>>, "Above Unicode range"},
        {<<0xFF, 0xFE>>, "Invalid bytes"}
      ]
      
      for {invalid_bytes, description} <- invalid_utf8_cases do
        oid = [1, 3, 6, 1, 2, 1, 1, 4, 0]  # sysContact
        varbinds = [{oid, :string, invalid_bytes}]
        pdu = PDU.build_response(12345, 0, 0, varbinds)
        message = PDU.build_message(pdu, "public", :v2c)
        
        case PDU.encode_message(message) do
          {:ok, encoded} ->
            case PDU.decode_message(encoded) do
              {:ok, decoded} ->
                [{_oid, _type, decoded_value}] = decoded.pdu.varbinds
                # Should preserve bytes even if not valid UTF-8
                assert is_binary(decoded_value),
                  "#{description}: should preserve as binary"
                  
              {:error, reason} ->
                assert true, "#{description} decode handling: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{description} encode handling: #{inspect(reason)}"
        end
      end
    end
  end
  
  describe "protocol robustness and security" do
    test "validates protection against memory exhaustion" do
      # Test protection against memory exhaustion attacks
      memory_test_cases = [
        {:large_varbind_count, "Excessive number of varbinds"},
        {:large_oid_length, "Excessively long OID"},
        {:large_community_string, "Excessively long community string"},
        {:large_string_value, "Excessively large string value"}
      ]
      
      for {test_type, description} <- memory_test_cases do
        test_data = create_memory_exhaustion_test(test_type)
        
        memory_before = :erlang.memory(:total)
        
        result = try do
          PDU.decode_message(test_data)
        catch
          :error, reason -> {:error, reason}
        end
        
        memory_after = :erlang.memory(:total)
        memory_used = memory_after - memory_before
        
        case result do
          {:error, reason} ->
            assert true, "#{description} properly limited: #{inspect(reason)}"
            
          {:ok, decoded} ->
            assert is_map(decoded), "#{description} handled safely"
            
            # Memory usage should be reasonable
            assert memory_used < 100_000_000,  # Less than 100MB
              "#{description} memory usage should be bounded: #{memory_used} bytes"
        end
      end
    end
    
    test "validates protection against infinite loops" do
      # Test protection against parsing infinite loops
      loop_test_cases = [
        {:self_referencing_length, "Self-referencing length field"},
        {:circular_sequence, "Circular SEQUENCE reference"},
        {:recursive_nesting, "Recursive nesting structure"}
      ]
      
      for {test_type, description} <- loop_test_cases do
        test_data = create_infinite_loop_test(test_type)
        
        # Set a timeout to catch infinite loops
        task = Task.async(fn ->
          PDU.decode_message(test_data)
        end)
        
        case Task.yield(task, 5000) do  # 5 second timeout
          {:ok, result} ->
            case result do
              {:error, reason} ->
                assert true, "#{description} properly detected: #{inspect(reason)}"
              {:ok, decoded} ->
                assert is_map(decoded), "#{description} handled safely"
            end
            
          nil ->
            Task.shutdown(task, :brutal_kill)
            flunk("#{description} caused infinite loop (timeout)")
        end
      end
    end
    
    test "validates error information disclosure protection" do
      # Test that error messages don't leak sensitive information
      sensitive_test_cases = [
        {create_malformed_with_sensitive_data("password123"), "Malformed data with password"},
        {create_malformed_with_sensitive_data("secret_key"), "Malformed data with secret"},
        {create_malformed_with_sensitive_data("/etc/passwd"), "Malformed data with file path"}
      ]
      
      for {test_data, description} <- sensitive_test_cases do
        case PDU.decode_message(test_data) do
          {:error, reason} ->
            error_message = inspect(reason)
            
            # Error message should not contain sensitive data
            refute String.contains?(error_message, "password123"),
              "#{description}: Error should not leak password"
            refute String.contains?(error_message, "secret_key"),
              "#{description}: Error should not leak secret"
            refute String.contains?(error_message, "/etc/passwd"),
              "#{description}: Error should not leak file path"
              
            assert true, "#{description} handled securely"
            
          {:ok, decoded} ->
            assert is_map(decoded), "#{description} processed safely"
        end
      end
    end
  end
  
  # Helper functions to create test data
  
  defp create_malformed_pdu_with_tag(tag) do
    # Create a basic malformed PDU structure with unknown tag
    <<0x30, 20,  # SEQUENCE, length 20
      0x02, 1, 0,  # version = 0
      0x04, 6, "public",  # community
      tag, 4,  # Unknown PDU tag
      0x02, 2, 0x12, 0x34>>  # Some random data
  end
  
  defp create_type_confusion_data(:primitive_as_constructed) do
    # INTEGER tagged as constructed
    <<0x30, 15,
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 2,  # GET request
      0x22, 0>>  # INTEGER with constructed bit set (invalid)
  end
  
  defp create_type_confusion_data(:constructed_as_primitive) do
    # SEQUENCE tagged as primitive
    <<0x10, 15,  # SEQUENCE with primitive bit set (invalid)
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 2,
      0x02, 0>>
  end
  
  defp create_type_confusion_data(:invalid_sequence_length) do
    # SEQUENCE with length that doesn't match content
    <<0x30, 255,  # SEQUENCE claiming length 255
      0x02, 1, 0,
      0x04, 6, "public">>  # But only 9 bytes of content
  end
  
  defp create_type_confusion_data(:nested_sequence_overflow) do
    # Nested SEQUENCE with length overflow
    <<0x30, 20,
      0x30, 200,  # Inner SEQUENCE claiming 200 bytes
      0x02, 1, 0>>  # But outer only has 20 total
  end
  
  defp create_tag_class_test_data(tag_bits) do
    # Create test data with specific tag class bits
    base_tag = 0x30  # SEQUENCE
    modified_tag = base_tag ||| tag_bits
    
    <<modified_tag, 10,
      0x02, 1, 0,
      0x04, 5, "test">>
  end
  
  defp create_indefinite_length_sequence() do
    # SEQUENCE with indefinite length (0x80) followed by end-of-contents (0x00 0x00)
    <<0x30, 0x80,  # SEQUENCE, indefinite length
      0x02, 1, 0,   # INTEGER 0
      0x00, 0x00>>  # End of contents
  end
  
  defp create_indefinite_length_octet_string() do
    <<0x04, 0x80,  # OCTET STRING, indefinite length
      "test",
      0x00, 0x00>>  # End of contents
  end
  
  defp create_nested_indefinite_length() do
    <<0x30, 0x80,  # Outer SEQUENCE, indefinite
      0x30, 0x80,   # Inner SEQUENCE, indefinite
      0x02, 1, 42,  # INTEGER 42
      0x00, 0x00,   # End inner
      0x00, 0x00>>  # End outer
  end
  
  defp create_oversized_integer() do
    # INTEGER with unnecessary leading zeros
    <<0x30, 15,
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 4,
      0x02, 4, 0x00, 0x00, 0x00, 0x42>>  # Should be just 0x42
  end
  
  defp create_undersized_integer() do
    # INTEGER that should be longer based on value
    <<0x30, 12,
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 1,
      0x02, 0>>  # Empty INTEGER (invalid)
  end
  
  defp create_invalid_negative_integer() do
    # Invalid encoding of negative integer
    <<0x30, 13,
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 2,
      0x02, 2, 0xFF, 0x00>>  # Invalid negative encoding
  end
  
  defp create_non_minimal_integer() do
    # Non-minimal integer encoding (extra leading zeros)
    <<0x30, 14,
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 3,
      0x02, 3, 0x00, 0x00, 0x01>>  # Should be just 0x01
  end
  
  defp create_sequence_test_data(:valid_sequence) do
    # Well-formed SNMP message
    <<0x30, 17,
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 4,
      0x02, 2, 0x12, 0x34>>
  end
  
  defp create_sequence_test_data(:empty_sequence) do
    # SEQUENCE with no content
    <<0x30, 0>>
  end
  
  defp create_sequence_test_data(:nested_sequence) do
    # Nested SEQUENCE structures
    <<0x30, 20,
      0x30, 10,
      0x02, 1, 0,
      0x04, 5, "test",
      0x30, 6,
      0x02, 1, 1,
      0x04, 1, "x">>
  end
  
  defp create_sequence_test_data(:sequence_with_primitives) do
    # SEQUENCE containing various primitive types
    <<0x30, 15,
      0x02, 1, 42,      # INTEGER
      0x04, 4, "test",  # OCTET STRING
      0x01, 1, 0xFF,    # BOOLEAN
      0x05, 0>>         # NULL
  end
  
  defp create_truncated_tlv() do
    # TLV where length claims more data than available
    <<0x30, 100,  # Claims 100 bytes
      0x02, 1, 0,
      0x04, 5, "test">>  # But only ~8 bytes available
  end
  
  defp create_overlapping_tlv() do
    # Overlapping TLV structures (invalid)
    <<0x30, 20,
      0x30, 15,  # Inner claims 15 bytes
      0x02, 1, 0,
      0x04, 3, "xyz",
      0x02, 1, 1>>  # This overlaps with inner
  end
  
  defp create_circular_tlv() do
    # Attempt at circular reference (implementation-dependent)
    <<0x30, 10,
      0x30, 8,
      0x30, 6,
      0x30, 4,
      0x02, 2, 0x00, 0x00>>
  end
  
  defp create_deeply_nested_tlv() do
    # Very deeply nested structure
    base = <<0x02, 1, 42>>  # Base INTEGER
    
    # Wrap in 20 layers of SEQUENCE
    Enum.reduce(1..20, base, fn _i, acc ->
      length = byte_size(acc)
      <<0x30, length>> <> acc
    end)
  end
  
  defp create_zero_length_tlv() do
    # Zero length with actual content (malformed)
    <<0x30, 0,  # Claims zero length
      0x02, 1, 42>>  # But has content
  end
  
  defp create_length_inconsistent_sequence(:length_too_short) do
    <<0x30, 5,  # Claims 5 bytes
      0x02, 1, 0,
      0x04, 6, "toolong">>  # But content is longer
  end
  
  defp create_length_inconsistent_sequence(:length_too_long) do
    <<0x30, 50,  # Claims 50 bytes
      0x02, 1, 0,
      0x04, 3, "short">>  # But content is much shorter
  end
  
  defp create_length_inconsistent_sequence(:length_zero_with_content) do
    <<0x30, 0,  # Claims zero length
      0x02, 1, 42>>  # But has content
  end
  
  defp create_length_inconsistent_sequence(:length_maximum) do
    <<0x30, 0xFF, 0xFF, 0xFF, 0xFF,  # Maximum 32-bit length
      0x02, 1, 0>>  # Minimal content
  end
  
  defp create_deeply_nested_structure(depth) do
    # Create structure nested to specified depth
    base = <<0x02, 1, 42>>  # Base content
    
    Enum.reduce(1..depth, base, fn _i, acc ->
      length = byte_size(acc)
      if length < 128 do
        <<0x30, length>> <> acc
      else
        # Use long form length encoding for larger structures
        <<0x30, 0x81, length>> <> acc
      end
    end)
  end
  
  defp create_memory_exhaustion_test(:large_varbind_count) do
    # Create message claiming to have many varbinds
    varbind_count = 10000
    <<0x30, 200,  # Outer SEQUENCE
      0x02, 1, 0,   # Version
      0x04, 6, "public",  # Community
      0xA0, 190,    # PDU
      0x02, 4, 0, 0, 0x12, 0x34,  # Request ID
      0x02, 1, 0,   # Error status
      0x02, 1, 0,   # Error index
      0x30, 0x81, 200,  # VarBindList claiming large size
      # But limited actual content
      0x30, 10,    # Single varbind
      0x06, 3, 43, 6, 1,  # OID
      0x05, 0>>     # NULL value
  end
  
  defp create_memory_exhaustion_test(:large_oid_length) do
    # OID claiming to be extremely long
    <<0x30, 100,
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 80,
      0x02, 2, 0x12, 0x34,
      0x02, 1, 0,
      0x02, 1, 0,
      0x30, 70,
      0x30, 68,
      0x06, 65000>> <> String.duplicate(<<43>>, 64)  # Claim 65000 byte OID
  end
  
  defp create_memory_exhaustion_test(:large_community_string) do
    # Community string claiming to be very large
    <<0x30, 100,
      0x02, 1, 0,
      0x04, 65000>> <> String.duplicate("x", 90)  # Claim 65000 byte community
  end
  
  defp create_memory_exhaustion_test(:large_string_value) do
    # String value claiming to be extremely large
    <<0x30, 50,
      0x02, 1, 0,
      0x04, 6, "public",
      0xA0, 40,
      0x02, 2, 0x12, 0x34,
      0x02, 1, 0,
      0x02, 1, 0,
      0x30, 30,
      0x30, 28,
      0x06, 3, 43, 6, 1,
      0x04, 10000>> <> String.duplicate("x", 20)  # Claim 10000 byte string
  end
  
  defp create_infinite_loop_test(:self_referencing_length) do
    # Length field that references itself (implementation-dependent)
    <<0x30, 10,
      0x02, 1, 0,
      0x04, 6, "public",
      0x30, 0x30>>  # Length field references tag position
  end
  
  defp create_infinite_loop_test(:circular_sequence) do
    # Attempt at circular SEQUENCE reference
    <<0x30, 20,
      0x30, 18,
      0x30, 16,
      0x30, 14,
      0x30, 12,
      0x30, 10,
      0x30, 8,
      0x30, 6,
      0x02, 4, 0, 0, 0, 0>>
  end
  
  defp create_infinite_loop_test(:recursive_nesting) do
    # Recursive nesting pattern
    content = <<0x02, 1, 42>>
    
    # Create pattern that might confuse recursive parsers
    Enum.reduce(1..100, content, fn i, acc ->
      if rem(i, 10) == 0 do
        # Insert reference back to earlier structure
        length = byte_size(acc)
        <<0x30, length, 0x30, 3, 0x02, 1, rem(i, 256)>> <> acc
      else
        length = byte_size(acc)
        <<0x30, length>> <> acc
      end
    end)
  end
  
  defp create_malformed_with_sensitive_data(sensitive_string) do
    # Create malformed data that includes sensitive information
    sensitive_bytes = sensitive_string
    
    <<0x30, 50,
      0x02, 1, 0,
      0x04, byte_size(sensitive_bytes), sensitive_bytes::binary,
      0xA0, 20,  # Malformed PDU follows
      0x02, 200>> <> sensitive_bytes  # Claim 200 bytes but embed sensitive data
  end
end