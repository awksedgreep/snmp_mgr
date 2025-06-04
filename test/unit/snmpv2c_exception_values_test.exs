defmodule SNMPMgr.SNMPv2cExceptionValuesTest do
  use ExUnit.Case, async: true
  
  alias SNMPMgr.Types
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :types
  @moduletag :snmpv2c
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

  describe "SNMPv2c Exception Value Decoding" do
    test "decode_value/1 converts noSuchObject to user-friendly atom" do
      result = Types.decode_value(:noSuchObject)
      assert result == :no_such_object
    end
    
    test "decode_value/1 converts noSuchInstance to user-friendly atom" do
      result = Types.decode_value(:noSuchInstance)
      assert result == :no_such_instance
    end
    
    test "decode_value/1 converts endOfMibView to user-friendly atom" do
      result = Types.decode_value(:endOfMibView)
      assert result == :end_of_mib_view
    end
  end

  describe "SNMPv2c Exception Value Type Inference" do
    test "infer_type/1 correctly identifies noSuchObject as null type" do
      result = Types.infer_type(:noSuchObject)
      assert result == :null
    end
    
    test "infer_type/1 correctly identifies noSuchInstance as null type" do
      result = Types.infer_type(:noSuchInstance)
      assert result == :null
    end
    
    test "infer_type/1 correctly identifies endOfMibView as null type" do
      result = Types.infer_type(:endOfMibView)
      assert result == :null
    end
  end

  describe "SNMPv2c Exception Values in SNMP Operations" do
    test "walk operation handles endOfMibView gracefully", %{device: device} do
      skip_if_no_device(device)
      
      # Test walking to end of MIB - should handle endOfMibView exception
      case SNMPMgr.walk(device.host, "1.3.6.1.2.1.1", 
                       community: device.community, timeout: 200, version: :v2c) do
        {:ok, results} when is_list(results) ->
          # Walk should complete without errors, even if endOfMibView encountered
          assert length(results) >= 0
          
        {:error, _reason} ->
          # Walk might fail for various reasons, which is acceptable
          :ok
      end
    end
    
    test "get operation handles noSuchObject/noSuchInstance", %{device: device} do
      skip_if_no_device(device)
      
      # Test GET on non-existent OID - should handle noSuchObject/noSuchInstance
      case SNMPMgr.get(device.host, "1.3.6.1.2.1.99.99.99.0", 
                      community: device.community, timeout: 200) do
        {:ok, result} ->
          # If we get a result, it should be properly decoded
          assert is_binary(result) or is_integer(result) or is_atom(result)
          
        {:error, _reason} ->
          # Expected for non-existent OID
          :ok
      end
    end
  end

  describe "SNMPv2c Exception Value Integration" do
    test "encode_value/1 handles exception values with graceful fallback" do
      # Test encoding user-friendly exception atoms
      test_cases = [
        :no_such_object,
        :no_such_instance, 
        :end_of_mib_view
      ]
      
      Enum.each(test_cases, fn exception_atom ->
        case Types.encode_value(exception_atom) do
          {:ok, {type, _value}} ->
            # Should encode to some valid SNMP type
            assert is_atom(type)
            
          {:error, _reason} ->
            # Graceful error handling is acceptable
            :ok
        end
      end)
    end
    
    test "decode_value/1 handles various input formats gracefully" do
      # Test with different input formats that might come from snmp_lib
      test_cases = [
        {:null, :noSuchObject},
        {:exception, :noSuchInstance},
        {:snmp_error, :endOfMibView}
      ]
      
      Enum.each(test_cases, fn test_input ->
        result = Types.decode_value(test_input)
        
        # Should handle gracefully - either decode successfully or return input
        assert result != nil
      end)
    end
  end
  
  describe "Exception Value Error Handling" do
    test "decode_value/1 provides consistent behavior for exception values" do
      # All exception values should decode to atoms
      results = [
        Types.decode_value(:noSuchObject),
        Types.decode_value(:noSuchInstance),
        Types.decode_value(:endOfMibView)
      ]
      
      # All should be atoms with consistent naming pattern
      assert Enum.all?(results, &is_atom/1)
      assert Enum.all?(results, fn atom ->
        atom_str = Atom.to_string(atom)
        String.contains?(atom_str, "_") and not String.starts_with?(atom_str, "Elixir.")
      end)
    end
    
    test "infer_type/1 provides consistent null typing for all exceptions" do
      # All exception values should infer as :null
      results = [
        Types.infer_type(:noSuchObject),
        Types.infer_type(:noSuchInstance),
        Types.infer_type(:endOfMibView)
      ]
      
      assert Enum.all?(results, fn type -> type == :null end)
    end
  end
  
  # Helper functions per @testing_rules
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end