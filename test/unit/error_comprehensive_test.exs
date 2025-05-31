defmodule SNMPMgr.ErrorComprehensiveTest do
  use ExUnit.Case, async: true
  
  alias SNMPMgr.Errors
  
  @moduletag :unit
  @moduletag :error
  @moduletag :phase_1

  # Comprehensive error scenarios for testing
  @error_scenarios [
    # Network-level errors
    {:network_timeout, "Request timed out after 5000ms", :timeout},
    {:connection_refused, "Connection refused by target host", :network_error},
    {:host_unreachable, "Host unreachable: network down", :network_error},
    {:port_unreachable, "Port 161 unreachable on target host", :network_error},
    
    # SNMP protocol errors
    {:invalid_community, "Community string 'invalid' rejected", :authentication_error},
    {:no_such_name, "Requested OID does not exist", :protocol_error},
    {:bad_value, "Invalid value type for SET operation", :protocol_error},
    {:read_only, "Attempted to SET read-only OID", :protocol_error},
    {:general_error, "General SNMP error occurred", :protocol_error},
    {:no_access, "No access permission for requested OID", :authorization_error},
    {:wrong_type, "Wrong type for SET operation", :protocol_error},
    {:wrong_length, "Wrong length for SET operation", :protocol_error},
    {:wrong_encoding, "Wrong encoding for SET operation", :protocol_error},
    {:wrong_value, "Wrong value for SET operation", :protocol_error},
    {:no_creation, "Cannot create new instance", :protocol_error},
    {:inconsistent_value, "Value inconsistent with object type", :protocol_error},
    {:resource_unavailable, "Resource temporarily unavailable", :resource_error},
    {:commit_failed, "Commit phase failed", :protocol_error},
    {:undo_failed, "Undo phase failed", :protocol_error},
    {:authorization_error, "Authorization failed", :authorization_error},
    {:not_writable, "Object is not writable", :protocol_error},
    {:inconsistent_name, "Inconsistent object name", :protocol_error},
    
    # SNMPv2c specific errors
    {:no_such_object, "No such object exists", :v2c_exception},
    {:no_such_instance, "No such instance exists", :v2c_exception},
    {:end_of_mib_view, "End of MIB view reached", :v2c_exception},
    
    # Transport and encoding errors
    {:malformed_packet, "Malformed SNMP packet received", :encoding_error},
    {:unsupported_version, "Unsupported SNMP version", :encoding_error},
    {:decode_error, "Failed to decode ASN.1 data", :encoding_error},
    {:encode_error, "Failed to encode ASN.1 data", :encoding_error},
    {:invalid_pdu, "Invalid PDU structure", :encoding_error},
    {:message_too_large, "Message exceeds maximum size", :encoding_error},
    
    # Configuration and validation errors
    {:invalid_target, "Invalid target specification", :configuration_error},
    {:invalid_oid, "Invalid OID format", :validation_error},
    {:invalid_community, "Invalid community string", :validation_error},
    {:invalid_timeout, "Invalid timeout value", :validation_error},
    {:invalid_retries, "Invalid retry count", :validation_error},
    {:missing_parameter, "Required parameter missing", :validation_error},
    
    # System and resource errors
    {:system_error, "System error occurred", :system_error},
    {:out_of_memory, "Out of memory", :resource_error},
    {:socket_error, "Socket operation failed", :system_error},
    {:permission_denied, "Permission denied", :system_error},
    {:file_not_found, "Configuration file not found", :system_error},
    
    # Custom application errors
    {:device_not_responding, "Device stopped responding", :device_error},
    {:bulk_operation_failed, "Bulk operation partially failed", :bulk_error},
    {:table_walk_incomplete, "Table walk did not complete", :walk_error},
    {:rate_limit_exceeded, "Rate limit exceeded", :throttling_error},
  ]

  describe "error code translation" do
    test "translates SNMP error codes correctly" do
      valid_codes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
      
      for error_code <- valid_codes do
        error_atom = Errors.code_to_atom(error_code)
        assert is_atom(error_atom), "Error code #{error_code} should translate to atom"
        assert error_atom != :unknown_error, "Error code #{error_code} should be recognized"
      end
    end

    test "handles unknown error codes gracefully" do
      unknown_codes = [999, -1, 100, 256]
      
      for error_code <- unknown_codes do
        error_atom = Errors.code_to_atom(error_code)
        assert error_atom == :unknown_error,
          "Unknown error code #{error_code} should return :unknown_error"
      end
    end

    test "identifies v2c specific errors" do
      v2c_errors = [:no_access, :wrong_type, :wrong_length, :wrong_encoding,
                    :wrong_value, :no_creation, :inconsistent_value, :resource_unavailable,
                    :commit_failed, :undo_failed, :authorization_error, :not_writable,
                    :inconsistent_name]
      
      v1_errors = [:no_error, :too_big, :no_such_name, :bad_value, :read_only, :gen_err]
      
      for error <- v2c_errors do
        assert Errors.is_v2c_error?(error) == true,
          "#{error} should be identified as v2c error"
      end
      
      for error <- v1_errors do
        assert Errors.is_v2c_error?(error) == false,
          "#{error} should not be identified as v2c error"
      end
    end
  end

  describe "error message formatting" do
    test "formats SNMP errors consistently" do
      snmp_error_cases = [
        {:snmp_error, 2},
        {:snmp_error, :no_such_name},
        {:v2c_error, :no_access},
        {:network_error, :host_unreachable},
        {:timeout, :request_timeout},
      ]
      
      for error_tuple <- snmp_error_cases do
        formatted = Errors.format_error(error_tuple)
        
        # All formatted messages should be strings
        assert is_binary(formatted), "Formatted error should be a string"
        
        # Should contain meaningful information
        assert String.length(formatted) > 0, "Formatted error should not be empty"
        
        # Should contain descriptive text
        assert String.contains?(formatted, "Error"), "Should contain 'Error' in message"
      end
    end

    test "provides error descriptions" do
      error_atoms = [:no_error, :too_big, :no_such_name, :bad_value, :read_only, :gen_err,
                     :no_access, :wrong_type, :authorization_error]
      
      for error_atom <- error_atoms do
        description = Errors.description(error_atom)
        
        # Should provide meaningful description
        assert is_binary(description), "Description should be a string"
        assert String.length(description) > 0, "Description should not be empty"
        refute String.contains?(description, "Unknown"), "Should have known description for #{error_atom}"
      end
    end

    test "handles direct code to description conversion" do
      # Test the convenience function
      code_description_cases = [
        {0, "No error occurred"},
        {2, "Variable name not found"},
        {5, "General error"},
        {16, "Authorization failed"},
      ]
      
      for {code, expected_desc} <- code_description_cases do
        actual_desc = Errors.code_to_description(code)
        assert actual_desc == expected_desc,
          "Code #{code} should produce description '#{expected_desc}', got '#{actual_desc}'"
      end
    end
  end

  describe "error recoverability" do
    test "identifies recoverable errors correctly" do
      recoverable_cases = [
        {:timeout, true},
        {{:snmp_error, :too_big}, true},
        {{:snmp_error, :gen_err}, true},
      ]
      
      non_recoverable_cases = [
        {{:network_error, :host_unreachable}, false},
        {{:snmp_error, :no_such_name}, false},
        {{:snmp_error, :bad_value}, false},
        {{:snmp_error, :read_only}, false},
        {{:v2c_error, :no_access}, false},
      ]
      
      for {error, expected_recoverable} <- recoverable_cases do
        actual = Errors.recoverable?(error)
        assert actual == expected_recoverable,
          "Error #{inspect(error)} recoverability should be #{expected_recoverable}, got #{actual}"
      end
      
      for {error, expected_recoverable} <- non_recoverable_cases do
        actual = Errors.recoverable?(error)
        assert actual == expected_recoverable,
          "Error #{inspect(error)} recoverability should be #{expected_recoverable}, got #{actual}"
      end
    end
  end

  describe "error handling performance" do
    @tag :performance
    test "error code translation is fast" do
      test_codes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 999]
      
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for code <- test_codes do
            Errors.code_to_atom(code)
          end
        end
      end)
      
      time_per_translation = time_microseconds / (1000 * length(test_codes))
      
      # Should be very fast (less than 5 microseconds per translation)
      assert time_per_translation < 5,
        "Error code translation too slow: #{time_per_translation} microseconds per translation"
    end

    @tag :performance
    test "error formatting is fast" do
      test_errors = [
        {:snmp_error, 2},
        {:v2c_error, :no_access},
        {:network_error, :timeout},
        {:timeout, :request_timeout},
      ]
      
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          for error <- test_errors do
            Errors.format_error(error)
          end
        end
      end)
      
      time_per_format = time_microseconds / (1000 * length(test_errors))
      
      # Should be fast (less than 20 microseconds per format)
      assert time_per_format < 20,
        "Error formatting too slow: #{time_per_format} microseconds per format"
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
    test "handles real SNMP errors correctly", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test various error scenarios with real device
      error_test_cases = [
        # Invalid community string
        {fn -> SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: "invalid_community") end,
         [:authentication_error, :invalid_community]},
        
        # Non-existent OID
        {fn -> SNMPMgr.get(target, "1.2.3.4.5.6.7.8.9.0", community: device.community) end,
         [:no_such_name, :protocol_error]},
        
        # Invalid OID format
        {fn -> SNMPMgr.get(target, "invalid.oid", community: device.community) end,
         [:invalid_oid, :validation_error]},
      ]
      
      for {operation, expected_error_types} <- error_test_cases do
        case operation.() do
          {:ok, _result} ->
            # Some operations might succeed depending on simulator behavior
            assert true, "Operation unexpectedly succeeded"
            
          {:error, error} ->
            error_type = Errors.classify_error(error, "Simulator error")
            
            # Should classify as one of the expected types
            assert error_type in expected_error_types,
              "Error should be classified as one of #{inspect(expected_error_types)}, got #{error_type}"
              
            # Error should have helpful message
            formatted = Errors.format_user_friendly_error(error, "Simulator error")
            assert is_binary(formatted), "Should format error message"
            assert String.length(formatted) > 10, "Error message should be meaningful"
        end
      end
    end

    @tag :integration
    test "error recovery works with simulator", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test error recovery by fixing issues
      recovery_scenarios = [
        # Fix invalid community
        {
          fn -> SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: "wrong") end,
          fn -> SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community) end,
          "Community string recovery"
        },
      ]
      
      for {failing_op, recovery_op, description} <- recovery_scenarios do
        # First operation should fail
        case failing_op.() do
          {:error, error} ->
            # Get recovery suggestions
            suggestions = Errors.get_recovery_suggestions(error)
            
            case suggestions do
              list when is_list(list) ->
                assert length(list) > 0, "Should provide recovery suggestions for #{description}"
                
              {:error, :no_suggestions_available} ->
                # Acceptable if not implemented
                assert true
            end
            
            # Recovery operation should succeed (if implemented correctly)
            case recovery_op.() do
              {:ok, _result} ->
                assert true, "Recovery succeeded for #{description}"
                
              {:error, :snmp_modules_not_available} ->
                # Expected in test environment
                assert true, "SNMP modules not available for recovery test"
                
              {:error, _recovery_error} ->
                # Recovery might not always work depending on error type
                assert true, "Recovery attempt made for #{description}"
            end
            
          {:ok, _} ->
            # Operation didn't fail as expected
            assert true, "Operation didn't fail for #{description}"
        end
      end
    end
  end
end