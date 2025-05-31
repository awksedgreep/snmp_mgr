defmodule SNMPMgr.PDUComprehensiveTest do
  use ExUnit.Case
  alias SNMPMgr.PDU

  describe "ASN.1 BER encoding edge cases" do
    test "encodes large OID sub-identifiers correctly" do
      # Test multi-byte sub-identifier encoding
      large_oids = [
        [1, 3, 6, 1, 128],         # 2-byte encoding (128 = 0x81, 0x00)
        [1, 3, 6, 1, 16384],       # 3-byte encoding  
        [1, 3, 6, 1, 2097152],     # 4-byte encoding
        [1, 3, 6, 1, 268435455]    # Large but valid 32-bit value
      ]
      
      for oid <- large_oids do
        pdu = PDU.build_get_request(oid, 12345)
        message = PDU.build_message(pdu, "public", :v1)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
        assert byte_size(encoded) > 0
        
        # Verify we can decode it back
        assert {:ok, decoded} = PDU.decode_message(encoded)
        assert decoded.pdu.type == :get_request
        assert decoded.pdu.request_id == 12345
      end
    end

    test "handles integer boundary values in ASN.1" do
      boundary_values = [
        0,            # Zero
        127,          # Single byte max
        128,          # Multi-byte minimum  
        255,          # Common boundary
        256,          # Byte boundary
        32767,        # 16-bit signed max
        32768,        # 16-bit signed overflow
        65535,        # 16-bit unsigned max
        65536,        # 16-bit unsigned overflow
        2147483647,   # 32-bit signed max
        4294967295    # 32-bit unsigned max
      ]
      
      for value <- boundary_values do
        # Test as request ID (common integer usage)
        pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], value)
        message = PDU.build_message(pdu, "public", :v1)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
        
        # Verify encoding/decoding round trip
        assert {:ok, decoded} = PDU.decode_message(encoded)
        assert decoded.pdu.request_id == value
      end
    end

    test "handles malformed ASN.1 structures gracefully" do
      malformed_cases = [
        <<0x30, 0x05, 0x02, 0x01>>,           # Truncated INTEGER
        <<0x30, 0xFF>>,                       # Invalid long length without data
        <<0x30, 0x82, 0x00>>,                 # Incomplete long form length
        <<0xFF, 0x01, 0x00>>,                 # Invalid tag
        <<0x30, 0x00>>,                       # Empty SEQUENCE
        <<>>,                                 # Empty binary
        <<0x30>>                              # Incomplete tag
      ]
      
      for malformed <- malformed_cases do
        # Should handle gracefully without crashing
        result = PDU.decode_message(malformed)
        assert {:error, _reason} = result
      end
    end
  end

  describe "SNMP value type edge cases" do
    test "handles Counter32 overflow scenarios" do
      counter_values = [
        0,            # Minimum
        2147483647,   # Large value
        4294967295    # Maximum 32-bit unsigned (Counter32 max)
      ]
      
      for value <- counter_values do
        # Create SET request with Counter32 value
        pdu = PDU.build_set_request([1, 3, 6, 1, 2, 1, 1, 1, 0], {:counter32, value}, 12345)
        message = PDU.build_message(pdu, "public", :v2c)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
      end
    end

    test "handles Counter64 values" do
      counter64_values = [
        0,                      # Minimum
        4294967296,            # Just over 32-bit
        18446744073709551615   # Maximum 64-bit unsigned
      ]
      
      for value <- counter64_values do
        # Create SET request with Counter64 value
        pdu = PDU.build_set_request([1, 3, 6, 1, 2, 1, 1, 1, 0], {:counter64, value}, 12345)
        message = PDU.build_message(pdu, "public", :v2c)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
      end
    end

    test "handles binary OCTET STRING data" do
      binary_cases = [
        <<>>,                          # Empty binary
        <<0x00>>,                      # Null byte
        <<0xFF, 0xFE, 0xFD>>,         # High bytes
        <<0x01, 0x02, 0x03, 0x04>>,   # Regular binary
        :crypto.strong_rand_bytes(100), # Random binary data
        "Hello\x00World",              # Mixed text and null
        "unicode: café élève"          # Unicode characters
      ]
      
      for binary_data <- binary_cases do
        # Create SET request with OCTET STRING value  
        pdu = PDU.build_set_request([1, 3, 6, 1, 2, 1, 1, 1, 0], {:string, binary_data}, 12345)
        message = PDU.build_message(pdu, "public", :v1)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
      end
    end

    test "handles SNMPv2c exception values in responses" do
      exception_values = [
        :noSuchObject,
        :noSuchInstance,  
        :endOfMibView
      ]
      
      for exception <- exception_values do
        # Create response PDU with exception value
        varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception}]
        pdu = PDU.build_response(12345, 0, 0, varbinds)
        message = PDU.build_message(pdu, "public", :v2c)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
      end
    end

    test "handles IpAddress values" do
      ip_cases = [
        {0, 0, 0, 0},           # Minimum
        {127, 0, 0, 1},         # Localhost
        {192, 168, 1, 1},       # Private network
        {255, 255, 255, 255}    # Maximum
      ]
      
      for ip <- ip_cases do
        # Create SET request with IpAddress value
        pdu = PDU.build_set_request([1, 3, 6, 1, 2, 1, 1, 1, 0], {:ipAddress, ip}, 12345)
        message = PDU.build_message(pdu, "public", :v1)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
      end
    end
  end

  describe "message size and protocol limits" do
    test "handles large PDU messages" do
      # Create PDU with many varbinds approaching size limits
      large_varbinds = for i <- 1..100 do
        {[1, 3, 6, 1, 4, 1, 1, i], :null, :null}
      end
      
      {:ok, pdu} = PDU.build_get_request_multi(large_varbinds, 12345)
      message = PDU.build_message(pdu, "public", :v1)
      
      assert {:ok, encoded} = PDU.encode_message(message)
      assert is_binary(encoded)
      assert byte_size(encoded) > 1000  # Should be substantial size
      
      # Verify we can decode it
      assert {:ok, decoded} = PDU.decode_message(encoded)
      assert length(decoded.pdu.varbinds) == 100
    end

    test "validates community string edge cases" do
      edge_cases = [
        "",                              # Empty community
        "x",                             # Single character
        String.duplicate("a", 100),      # Long community
        "community with spaces",         # Spaces
        "community\x00null",             # Embedded null
        <<0x01, 0x02, 0xFF, 0xFE>>      # Binary community data
      ]
      
      pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      
      for community <- edge_cases do
        case PDU.build_message(pdu, community, :v1) do
          {:error, _reason} ->
            # Some edge cases may be rejected - that's okay
            :ok
          message ->
            # If accepted, should encode properly
            assert {:ok, encoded} = PDU.encode_message(message)
            assert is_binary(encoded)
        end
      end
    end

    test "handles maximum OID lengths" do
      # Create very long but valid OID
      long_oid = [1, 3, 6, 1, 4, 1, 1] ++ Enum.to_list(1..50)
      
      pdu = PDU.build_get_request(long_oid, 12345)
      message = PDU.build_message(pdu, "public", :v1)
      
      assert {:ok, encoded} = PDU.encode_message(message)
      assert is_binary(encoded)
      
      # Verify decoding
      assert {:ok, decoded} = PDU.decode_message(encoded)
      assert decoded.pdu.request_id == 12345
    end
  end

  describe "protocol version compliance" do
    test "enforces SNMPv1 vs SNMPv2c restrictions" do
      # GETBULK should be rejected for SNMPv1
      pdu = PDU.build_get_bulk_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345, 0, 10)
      
      # SNMPv1 should reject GETBULK
      assert_raise ArgumentError, ~r/GETBULK requests require SNMPv2c/, fn ->
        PDU.build_message(pdu, "public", :v1)
      end
      
      # SNMPv2c should accept GETBULK
      message = PDU.build_message(pdu, "public", :v2c)
      assert {:ok, encoded} = PDU.encode_message(message)
      assert is_binary(encoded)
    end

    test "validates GETBULK parameter ranges" do
      base_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      
      edge_cases = [
        {0, 0},           # Minimum values
        {0, 1},           # Non-repeaters 0, max_reps 1
        {1, 0},           # Non-repeaters 1, max_reps 0
        {10, 100},        # Normal values
        {127, 127}        # Large but reasonable values
      ]
      
      for {non_rep, max_rep} <- edge_cases do
        pdu = PDU.build_get_bulk_request(base_oid, 12345, non_rep, max_rep)
        message = PDU.build_message(pdu, "public", :v2c)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
        
        # Verify parameters are preserved
        assert {:ok, decoded} = PDU.decode_message(encoded)
        assert decoded.pdu.non_repeaters == non_rep
        assert decoded.pdu.max_repetitions == max_rep
      end
    end
  end

  describe "error handling robustness" do
    test "handles all SNMP error types correctly" do
      snmp_errors = [
        {0, :noError},
        {1, :tooBig}, 
        {2, :noSuchName},
        {3, :badValue},
        {4, :readOnly},
        {5, :genErr}
      ]
      
      for {error_code, _error_name} <- snmp_errors do
        varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null}]
        pdu = PDU.build_response(12345, error_code, 1, varbinds)
        message = PDU.build_message(pdu, "public", :v1)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
        
        # Verify error code is preserved
        assert {:ok, decoded} = PDU.decode_message(encoded)
        assert decoded.pdu.error_status == error_code
        assert decoded.pdu.error_index == 1
      end
    end

    test "validates error index consistency" do
      # Error index should point to valid varbind position
      varbinds = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null},
        {[1, 3, 6, 1, 2, 1, 1, 2, 0], :null, :null},
        {[1, 3, 6, 1, 2, 1, 1, 3, 0], :null, :null}
      ]
      
      # Test error index for each varbind position
      for error_index <- [0, 1, 2, 3] do
        pdu = PDU.build_response(12345, 3, error_index, varbinds) # badValue error
        message = PDU.build_message(pdu, "public", :v1)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
        
        # Verify error index is preserved
        assert {:ok, decoded} = PDU.decode_message(encoded)
        assert decoded.pdu.error_index == error_index
      end
    end
  end

  describe "performance edge cases" do
    test "handles memory pressure with large datasets" do
      # Create multiple large PDUs to test memory efficiency
      large_datasets = for _i <- 1..10 do
        varbinds = for j <- 1..50 do
          {[1, 3, 6, 1, 4, 1, 1, j], :string, String.duplicate("data", 20)}
        end
        {:ok, pdu} = PDU.build_get_request_multi(varbinds, 12345)
        message = PDU.build_message(pdu, "public", :v1)
        assert {:ok, encoded} = PDU.encode_message(message)
        encoded
      end
      
      # All should be successfully encoded
      assert length(large_datasets) == 10
      Enum.each(large_datasets, fn encoded ->
        assert is_binary(encoded)
        assert byte_size(encoded) > 100
      end)
    end

    test "encoding performance with complex structures" do
      # Test encoding performance with complex nested structures
      complex_varbinds = for i <- 1..20 do
        long_oid = [1, 3, 6, 1, 4, 1, 1] ++ Enum.to_list(1..10) ++ [i]
        {long_oid, :string, "Complex data #{i} with more content"}
      end
      
      {:ok, pdu} = PDU.build_get_request_multi(complex_varbinds, 12345)
      message = PDU.build_message(pdu, "public", :v2c)
      
      # Should complete within reasonable time
      {time, {:ok, encoded}} = :timer.tc(fn ->
        PDU.encode_message(message)
      end)
      
      assert is_binary(encoded)
      assert time < 10_000  # Less than 10ms
    end
  end

  describe "real-world scenario edge cases" do
    test "handles device-specific OID patterns" do
      # Common device OID patterns that might cause issues
      device_oids = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],                    # sysDescr
        [1, 3, 6, 1, 2, 1, 2, 2, 1, 1, 1],             # ifDescr.1
        [1, 3, 6, 1, 4, 1, 9, 2, 1, 1, 0],             # Cisco enterprise
        [1, 3, 6, 1, 4, 1, 2636, 3, 1, 13, 1, 5, 9, 1, 0] # Long Juniper OID
      ]
      
      for oid <- device_oids do
        pdu = PDU.build_get_request(oid, 12345)
        message = PDU.build_message(pdu, "public", :v1)
        
        assert {:ok, encoded} = PDU.encode_message(message)
        assert is_binary(encoded)
        
        # Verify round-trip
        assert {:ok, decoded} = PDU.decode_message(encoded)
        assert decoded.pdu.type == :get_request
      end
    end

    test "handles concurrent encoding operations" do
      # Test thread safety of encoding operations
      tasks = for i <- 1..10 do
        Task.async(fn ->
          pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, i], 12345 + i)
          message = PDU.build_message(pdu, "public", :v1)
          PDU.encode_message(message)
        end)
      end
      
      results = Task.await_many(tasks, 5000)
      
      # All should succeed
      Enum.each(results, fn {:ok, encoded} ->
        assert is_binary(encoded)
        assert byte_size(encoded) > 0
      end)
    end
  end
end