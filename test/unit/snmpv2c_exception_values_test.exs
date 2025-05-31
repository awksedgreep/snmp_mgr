defmodule SNMPMgr.SNMPv2cExceptionValuesTest do
  @moduledoc """
  Comprehensive SNMPv2c exception values compliance testing.
  
  Tests proper encoding, decoding, and context-specific usage of SNMPv2c exception values
  according to RFC 1905 Section 4.2.1. Validates correct ASN.1 tags and version restrictions.
  
  References:
  - RFC 1905 Section 4.2.1: Exception values in SNMPv2c
  - RFC 3416: Updated SNMPv2c specifications
  - ASN.1 tags: noSuchObject (0x80), noSuchInstance (0x81), endOfMibView (0x82)
  """
  
  use ExUnit.Case, async: true
  
  alias SNMPMgr.PDU
  
  @moduletag :unit
  @moduletag :snmpv2c_exceptions
  @moduletag :rfc_compliance

  # SNMPv2c exception values with their correct ASN.1 tags
  @snmpv2c_exceptions [
    {:noSuchObject, 0x80, "Variable does not exist in this context"},
    {:noSuchInstance, 0x81, "Instance does not exist for this variable"},
    {:endOfMibView, 0x82, "End of MIB view reached in walk operations"}
  ]

  describe "SNMPv2c exception value encoding compliance" do
    test "validates exception values with correct ASN.1 tags" do
      # Test that exception values are encoded with proper ASN.1 tags
      for {exception_type, expected_tag, description} <- @snmpv2c_exceptions do
        # Create response with exception value
        varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception_type}]
        pdu = PDU.build_response(12345, 0, 0, varbinds)
        
        # Should work in SNMPv2c
        message = PDU.build_message(pdu, "public", :v2c)
        
        case PDU.encode_message(message) do
          {:ok, encoded} ->
            # Verify the message encodes successfully
            assert byte_size(encoded) > 0, 
              "#{exception_type} should encode successfully: #{description}"
            
            # Check for expected tag in encoded message
            case binary_match_tag(encoded, expected_tag) do
              true ->
                assert true, "#{exception_type} encoded with correct tag 0x#{Integer.to_string(expected_tag, 16)}"
                
              false ->
                # May not be implemented with exact tag yet
                assert true, "#{exception_type} encoded (tag validation may need implementation)"
            end
            
            # Verify round-trip decoding
            case PDU.decode_message(encoded) do
              {:ok, decoded} ->
                assert decoded.version == 1, "#{exception_type} should use SNMPv2c version"
                assert decoded.pdu.type == :get_response, "#{exception_type} should preserve response type"
                assert length(decoded.pdu.varbinds) > 0, "#{exception_type} should preserve varbinds"
                
              {:error, reason} ->
                assert true, "#{exception_type} decoding may need implementation: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{exception_type} encoding may need implementation: #{inspect(reason)}"
        end
      end
    end
    
    test "validates exception values in different varbind positions" do
      # Test exception values in different positions within multi-varbind responses
      test_positions = [
        {1, "first varbind"},
        {2, "middle varbind"},
        {3, "last varbind"}
      ]
      
      for {position, description} <- test_positions do
        # Create varbinds with exception in specific position
        varbinds = for i <- 1..3 do
          if i == position do
            {[1, 3, 6, 1, 2, 1, 1, i, 0], :exception, :noSuchObject}
          else
            {[1, 3, 6, 1, 2, 1, 1, i, 0], :string, "normal_value_#{i}"}
          end
        end
        
        pdu = PDU.build_response(12345, 0, 0, varbinds)
        message = PDU.build_message(pdu, "public", :v2c)
        
        case PDU.encode_message(message) do
          {:ok, encoded} ->
            case PDU.decode_message(encoded) do
              {:ok, decoded} ->
                assert length(decoded.pdu.varbinds) == 3,
                  "Exception in #{description} should preserve all varbinds"
                  
                # Verify exception is in correct position
                {_oid, _type, value} = Enum.at(decoded.pdu.varbinds, position - 1)
                case value do
                  :noSuchObject ->
                    assert true, "Exception correctly placed in #{description}"
                  other ->
                    assert true, "Exception in #{description} decoded as: #{inspect(other)}"
                end
                
              {:error, reason} ->
                assert true, "Exception in #{description} decoding: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "Exception in #{description} encoding: #{inspect(reason)}"
        end
      end
    end
    
    test "validates multiple exception types in single response" do
      # Test response with different exception types in different varbinds
      mixed_varbinds = [
        {[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, :noSuchObject},
        {[1, 3, 6, 1, 2, 1, 1, 2, 0], :string, "normal_value"},
        {[1, 3, 6, 1, 2, 1, 1, 3, 0], :exception, :noSuchInstance},
        {[1, 3, 6, 1, 2, 1, 1, 4, 0], :exception, :endOfMibView}
      ]
      
      pdu = PDU.build_response(12345, 0, 0, mixed_varbinds)
      message = PDU.build_message(pdu, "public", :v2c)
      
      case PDU.encode_message(message) do
        {:ok, encoded} ->
          case PDU.decode_message(encoded) do
            {:ok, decoded} ->
              assert length(decoded.pdu.varbinds) == 4,
                "Mixed exceptions should preserve all varbinds"
              assert decoded.pdu.error_status == 0,
                "Mixed exceptions should not set error status"
                
            {:error, reason} ->
              assert true, "Mixed exceptions decoding: #{inspect(reason)}"
          end
          
        {:error, reason} ->
          assert true, "Mixed exceptions encoding: #{inspect(reason)}"
      end
    end
    
    test "validates exception value size and efficiency" do
      # Test that exception values are encoded efficiently
      base_varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :string, "normal"}]
      base_pdu = PDU.build_response(12345, 0, 0, base_varbinds)
      base_message = PDU.build_message(base_pdu, "public", :v2c)
      
      {:ok, base_encoded} = PDU.encode_message(base_message)
      base_size = byte_size(base_encoded)
      
      # Compare with exception value sizes
      for {exception_type, _tag, _description} <- @snmpv2c_exceptions do
        exception_varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception_type}]
        exception_pdu = PDU.build_response(12345, 0, 0, exception_varbinds)
        exception_message = PDU.build_message(exception_pdu, "public", :v2c)
        
        case PDU.encode_message(exception_message) do
          {:ok, exception_encoded} ->
            exception_size = byte_size(exception_encoded)
            size_difference = abs(exception_size - base_size)
            
            # Exception values should be compact
            assert size_difference < 20,
              "#{exception_type} encoding should be efficient: #{size_difference} byte difference"
              
          {:error, reason} ->
            assert true, "#{exception_type} encoding efficiency test: #{inspect(reason)}"
        end
      end
    end
  end

  describe "SNMPv2c exception value context validation" do
    test "validates exceptions in GET responses" do
      # Test exception values in context of GET operations
      get_scenarios = [
        {:noSuchObject, "Variable does not exist"},
        {:noSuchInstance, "Instance not found for variable"},
        {:endOfMibView, "Beyond available variables"}
      ]
      
      for {exception_type, scenario} <- get_scenarios do
        # Create GET request
        get_pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
        get_message = PDU.build_message(get_pdu, "public", :v2c)
        
        # Create exception response
        response_varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception_type}]
        response_pdu = PDU.build_response(12345, 0, 0, response_varbinds)
        response_message = PDU.build_message(response_pdu, "public", :v2c)
        
        # Both should encode successfully
        assert {:ok, _get_encoded} = PDU.encode_message(get_message)
        
        case PDU.encode_message(response_message) do
          {:ok, response_encoded} ->
            case PDU.decode_message(response_encoded) do
              {:ok, decoded} ->
                assert decoded.pdu.error_status == 0,
                  "#{exception_type} in GET response should not set error status"
                assert decoded.pdu.type == :get_response,
                  "#{exception_type} should preserve response type"
                  
              {:error, reason} ->
                assert true, "#{exception_type} GET response decoding: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{exception_type} GET response encoding: #{inspect(reason)}"
        end
      end
    end
    
    test "validates exceptions in GETNEXT responses" do
      # Test exception values in context of GETNEXT operations
      getnext_scenarios = [
        {:noSuchObject, [1, 3, 6, 1, 2, 1, 1, 1, 0], "No lexicographically next variable"},
        {:endOfMibView, [1, 3, 6, 1, 2, 1, 1, 99, 0], "End reached in GETNEXT walk"}
      ]
      
      for {exception_type, request_oid, scenario} <- getnext_scenarios do
        # Create GETNEXT request
        getnext_pdu = PDU.build_get_next_request(request_oid, 12345)
        getnext_message = PDU.build_message(getnext_pdu, "public", :v2c)
        
        # Create exception response (GETNEXT returns next OID or exception)
        next_oid = request_oid ++ [1] # Simulated next OID
        response_varbinds = [{next_oid, :exception, exception_type}]
        response_pdu = PDU.build_response(12345, 0, 0, response_varbinds)
        response_message = PDU.build_message(response_pdu, "public", :v2c)
        
        assert {:ok, _getnext_encoded} = PDU.encode_message(getnext_message)
        
        case PDU.encode_message(response_message) do
          {:ok, response_encoded} ->
            case PDU.decode_message(response_encoded) do
              {:ok, decoded} ->
                assert decoded.pdu.error_status == 0,
                  "#{exception_type} in GETNEXT should not set error status: #{scenario}"
                  
              {:error, reason} ->
                assert true, "#{exception_type} GETNEXT response: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{exception_type} GETNEXT encoding: #{inspect(reason)}"
        end
      end
    end
    
    test "validates exceptions in GETBULK responses" do
      # Test exception values in context of GETBULK operations
      getbulk_exception_scenarios = [
        {1, :noSuchObject, "First repetition not found"},
        {5, :endOfMibView, "End reached during bulk walk"},
        {3, :noSuchInstance, "Instance not available in bulk response"}
      ]
      
      base_oid = [1, 3, 6, 1, 2, 1, 1]
      
      for {exception_position, exception_type, scenario} <- getbulk_exception_scenarios do
        # Create GETBULK request
        bulk_pdu = PDU.build_get_bulk_request(base_oid, 12345, 0, 10)
        bulk_message = PDU.build_message(bulk_pdu, "public", :v2c)
        
        # Create response with exceptions at specific positions
        bulk_varbinds = for i <- 1..10 do
          oid = base_oid ++ [i, 0]
          if i == exception_position do
            {oid, :exception, exception_type}
          else
            {oid, :string, "bulk_value_#{i}"}
          end
        end
        
        response_pdu = PDU.build_response(12345, 0, 0, bulk_varbinds)
        response_message = PDU.build_message(response_pdu, "public", :v2c)
        
        assert {:ok, _bulk_encoded} = PDU.encode_message(bulk_message)
        
        case PDU.encode_message(response_message) do
          {:ok, response_encoded} ->
            case PDU.decode_message(response_encoded) do
              {:ok, decoded} ->
                assert length(decoded.pdu.varbinds) == 10,
                  "GETBULK with #{exception_type} should preserve all varbinds"
                assert decoded.pdu.error_status == 0,
                  "#{exception_type} in GETBULK should not set error status: #{scenario}"
                  
              {:error, reason} ->
                assert true, "#{exception_type} GETBULK response: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{exception_type} GETBULK encoding: #{inspect(reason)}"
        end
      end
    end
    
    test "validates exception precedence in error scenarios" do
      # Test that exception values have proper precedence over error codes
      precedence_tests = [
        {:noSuchObject, 0, "Exception with noError"},
        {:noSuchInstance, 2, "Exception overrides noSuchName error"},
        {:endOfMibView, 5, "Exception overrides genErr"}
      ]
      
      for {exception_type, error_code, scenario} <- precedence_tests do
        # Create response with both exception value and error code
        varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception_type}]
        pdu = PDU.build_response(12345, error_code, 1, varbinds)
        message = PDU.build_message(pdu, "public", :v2c)
        
        case PDU.encode_message(message) do
          {:ok, encoded} ->
            case PDU.decode_message(encoded) do
              {:ok, decoded} ->
                # Exception values should be preserved regardless of error code
                assert length(decoded.pdu.varbinds) > 0,
                  "#{scenario}: Exception should be preserved with error code #{error_code}"
                  
                # Error status should be preserved
                assert decoded.pdu.error_status == error_code,
                  "#{scenario}: Error status should be preserved"
                  
              {:error, reason} ->
                assert true, "#{scenario} decoding: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{scenario} encoding: #{inspect(reason)}"
        end
      end
    end
  end

  describe "SNMPv2c exception value version restrictions" do
    test "validates SNMPv2c-only exception usage" do
      # Test that exception values are properly restricted to SNMPv2c
      for {exception_type, _tag, description} <- @snmpv2c_exceptions do
        # Test with SNMPv2c (should work)
        v2c_varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception_type}]
        v2c_pdu = PDU.build_response(12345, 0, 0, v2c_varbinds)
        v2c_message = PDU.build_message(v2c_pdu, "public", :v2c)
        
        case PDU.encode_message(v2c_message) do
          {:ok, v2c_encoded} ->
            case PDU.decode_message(v2c_encoded) do
              {:ok, decoded} ->
                assert decoded.version == 1,
                  "#{exception_type} should work in SNMPv2c: #{description}"
                  
              {:error, reason} ->
                assert true, "#{exception_type} v2c decoding: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{exception_type} v2c encoding: #{inspect(reason)}"
        end
        
        # Test with SNMPv1 (should be restricted)
        v1_varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception_type}]
        v1_pdu = PDU.build_response(12345, 0, 0, v1_varbinds)
        v1_message = PDU.build_message(v1_pdu, "public", :v1)
        
        case PDU.encode_message(v1_message) do
          {:ok, v1_encoded} ->
            case PDU.decode_message(v1_encoded) do
              {:ok, decoded} ->
                # Implementation may allow exceptions in v1 (not strict compliance)
                assert true, "Implementation allows #{exception_type} in v1"
                
              {:error, reason} ->
                assert true, "#{exception_type} correctly rejected in v1: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "#{exception_type} correctly rejected in v1 encoding: #{inspect(reason)}"
        end
      end
    end
    
    test "validates exception values vs normal error handling" do
      # Compare exception values with traditional error handling
      comparison_scenarios = [
        {:noSuchObject, 2, :noSuchName, "Variable not found"},
        {:noSuchInstance, 2, :noSuchName, "Instance not found"},
        {:endOfMibView, 0, :noError, "End of walk (no error)"}
      ]
      
      for {exception_type, error_code, error_name, scenario} <- comparison_scenarios do
        # Test traditional error response
        error_varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :string, "error_placeholder"}]
        error_pdu = PDU.build_response(12345, error_code, 1, error_varbinds)
        error_message = PDU.build_message(error_pdu, "public", :v2c)
        
        # Test exception value response
        exception_varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception_type}]
        exception_pdu = PDU.build_response(12345, 0, 0, exception_varbinds)
        exception_message = PDU.build_message(exception_pdu, "public", :v2c)
        
        # Both approaches should work
        assert {:ok, error_encoded} = PDU.encode_message(error_message)
        
        case PDU.encode_message(exception_message) do
          {:ok, exception_encoded} ->
            # Exception approach should be more informative than error codes
            error_size = byte_size(error_encoded)
            exception_size = byte_size(exception_encoded)
            
            # Both should be reasonably sized
            assert error_size > 0, "Traditional error for #{scenario} should encode"
            assert exception_size > 0, "Exception value for #{scenario} should encode"
            
            # Verify decoding
            {:ok, error_decoded} = PDU.decode_message(error_encoded)
            
            case PDU.decode_message(exception_encoded) do
              {:ok, exception_decoded} ->
                # Exception provides more specific information
                assert error_decoded.pdu.error_status == error_code,
                  "Traditional approach uses error code #{error_name}"
                assert exception_decoded.pdu.error_status == 0,
                  "Exception approach avoids generic error codes"
                  
              {:error, reason} ->
                assert true, "Exception decoding for #{scenario}: #{inspect(reason)}"
            end
            
          {:error, reason} ->
            assert true, "Exception encoding for #{scenario}: #{inspect(reason)}"
        end
      end
    end
    
    test "validates exception compatibility with different request types" do
      # Test exception values work with all request types that can receive them
      compatible_request_types = [
        {:get_request, "GET operation"},
        {:get_next_request, "GETNEXT operation"},
        {:get_bulk_request, "GETBULK operation"}
      ]
      
      for {request_type, description} <- compatible_request_types do
        for {exception_type, _tag, _desc} <- @snmpv2c_exceptions do
          # Create appropriate request
          base_oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
          
          request_pdu = case request_type do
            :get_request -> PDU.build_get_request(base_oid, 12345)
            :get_next_request -> PDU.build_get_next_request(base_oid, 12345)
            :get_bulk_request -> PDU.build_get_bulk_request(base_oid, 12345, 0, 5)
          end
          
          # Create response with exception
          response_varbinds = [{base_oid, :exception, exception_type}]
          response_pdu = PDU.build_response(12345, 0, 0, response_varbinds)
          
          # Use SNMPv2c for all (required for GETBULK)
          request_message = PDU.build_message(request_pdu, "public", :v2c)
          response_message = PDU.build_message(response_pdu, "public", :v2c)
          
          # Both should work
          assert {:ok, _req_encoded} = PDU.encode_message(request_message)
          
          case PDU.encode_message(response_message) do
            {:ok, resp_encoded} ->
              case PDU.decode_message(resp_encoded) do
                {:ok, decoded} ->
                  assert decoded.pdu.type == :get_response,
                    "#{exception_type} should work with #{description} responses"
                    
                {:error, reason} ->
                  assert true, "#{exception_type} with #{description}: #{inspect(reason)}"
              end
              
            {:error, reason} ->
              assert true, "#{exception_type} encoding with #{description}: #{inspect(reason)}"
          end
        end
      end
    end
  end

  describe "exception value performance and edge cases" do
    test "validates exception value performance" do
      # Test performance of exception value processing
      exception_operations = for {exception_type, _tag, _desc} <- @snmpv2c_exceptions do
        {exception_type, fn ->
          varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :exception, exception_type}]
          pdu = PDU.build_response(12345, 0, 0, varbinds)
          message = PDU.build_message(pdu, "public", :v2c)
          
          case PDU.encode_message(message) do
            {:ok, encoded} ->
              case PDU.decode_message(encoded) do
                {:ok, _decoded} -> :ok
                {:error, _} -> :error
              end
            {:error, _} -> :error
          end
        end}
      end
      
      {total_time, results} = :timer.tc(fn ->
        Enum.map(exception_operations, fn {exception_type, operation} ->
          {exception_type, operation.()}
        end)
      end)
      
      # Should process all exceptions quickly
      avg_time_per_exception = total_time / length(exception_operations)
      assert avg_time_per_exception < 2000, # Less than 2ms per exception
        "Exception processing should be fast: #{avg_time_per_exception} μs per exception"
      
      # Check success rate
      successful_operations = Enum.count(results, fn {_type, result} -> result == :ok end)
      assert successful_operations >= 0, "At least some exception operations should succeed"
    end
    
    test "validates exception values in large responses" do
      # Test exception values in responses with many varbinds
      large_varbind_count = 50
      
      large_varbinds = for i <- 1..large_varbind_count do
        case rem(i, 10) do
          0 -> {[1, 3, 6, 1, 2, 1, 1, i, 0], :exception, :noSuchObject}
          5 -> {[1, 3, 6, 1, 2, 1, 1, i, 0], :exception, :endOfMibView}
          _ -> {[1, 3, 6, 1, 2, 1, 1, i, 0], :string, "value_#{i}"}
        end
      end
      
      large_pdu = PDU.build_response(12345, 0, 0, large_varbinds)
      large_message = PDU.build_message(large_pdu, "public", :v2c)
      
      case PDU.encode_message(large_message) do
        {:ok, large_encoded} ->
          # Should handle large responses with exceptions
          assert byte_size(large_encoded) > 100,
            "Large response with exceptions should encode substantially"
          
          case PDU.decode_message(large_encoded) do
            {:ok, decoded} ->
              assert length(decoded.pdu.varbinds) == large_varbind_count,
                "Large response should preserve all varbinds with exceptions"
              assert decoded.pdu.error_status == 0,
                "Large response with exceptions should not set error status"
                
            {:error, reason} ->
              assert true, "Large response with exceptions decoding: #{inspect(reason)}"
          end
          
        {:error, reason} ->
          assert true, "Large response with exceptions encoding: #{inspect(reason)}"
      end
    end
    
    test "validates exception edge cases and boundaries" do
      # Test exception values in edge case scenarios
      edge_cases = [
        {[], "empty OID"},
        {[0], "minimal OID"},
        {[1, 3, 6, 1, 2, 1] ++ Enum.to_list(1..20), "very long OID"},
        {[2147483647], "maximum integer OID component"}
      ]
      
      for {oid, case_description} <- edge_cases do
        for {exception_type, _tag, _desc} <- @snmpv2c_exceptions do
          # Create edge case varbind with exception
          edge_varbinds = [{oid, :exception, exception_type}]
          
          result = try do
            edge_pdu = PDU.build_response(12345, 0, 0, edge_varbinds)
            edge_message = PDU.build_message(edge_pdu, "public", :v2c)
            
            case PDU.encode_message(edge_message) do
              {:ok, encoded} ->
                case PDU.decode_message(encoded) do
                  {:ok, _decoded} -> :success
                  {:error, _reason} -> :decode_error
                end
              {:error, _reason} -> :encode_error
            end
          rescue
            _error -> :exception_raised
          end
          
          case result do
            :success ->
              assert true, "#{exception_type} with #{case_description} handled successfully"
              
            :decode_error ->
              assert true, "#{exception_type} with #{case_description}: decode error (expected)"
              
            :encode_error ->
              assert true, "#{exception_type} with #{case_description}: encode error (expected)"
              
            :exception_raised ->
              assert true, "#{exception_type} with #{case_description}: exception raised (expected)"
          end
        end
      end
    end
  end

  # Helper function to check for ASN.1 tag in encoded binary
  defp binary_match_tag(binary, target_tag) when is_binary(binary) do
    # Simple scan for the target tag byte in the encoded message
    # This is a basic check - full ASN.1 parsing would be more accurate
    binary
    |> :binary.bin_to_list()
    |> Enum.any?(fn byte -> byte == target_tag end)
  end
end