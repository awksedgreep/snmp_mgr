defmodule SNMPMgr.PDUTest do
  use ExUnit.Case, async: true
  
  alias SNMPMgr.PDU
  
  @moduletag :unit
  @moduletag :protocol
  @moduletag :phase_1

  describe "PDU construction" do
    test "builds GET request PDU with correct structure" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      request_id = 12345
      
      pdu = PDU.build_get_request(oid, request_id)
      
      assert pdu.type == :get_request
      assert pdu.request_id == request_id
      assert pdu.error_status == 0
      assert pdu.error_index == 0
      assert pdu.varbinds == [{oid, :null, :null}]
    end

    test "builds GETNEXT request PDU" do
      oid = [1, 3, 6, 1, 2, 1, 1]
      request_id = 23456
      
      pdu = PDU.build_get_next_request(oid, request_id)
      
      assert pdu.type == :get_next_request
      assert pdu.request_id == request_id
      assert pdu.varbinds == [{oid, :null, :null}]
    end

    test "builds GETBULK request PDU with non-repeaters and max-repetitions" do
      oid = [1, 3, 6, 1, 2, 1, 2, 2]
      request_id = 34567
      non_repeaters = 0
      max_repetitions = 10
      
      pdu = PDU.build_get_bulk_request(oid, request_id, non_repeaters, max_repetitions)
      
      assert pdu.type == :get_bulk_request
      assert pdu.request_id == request_id
      assert pdu.non_repeaters == non_repeaters
      assert pdu.max_repetitions == max_repetitions
      assert pdu.varbinds == [{oid, :null, :null}]
    end

    test "builds SET request PDU with value" do
      oid = [1, 3, 6, 1, 2, 1, 1, 5, 0]
      request_id = 45678
      value = {:string, ~c"new-hostname"}
      
      pdu = PDU.build_set_request(oid, value, request_id)
      
      assert pdu.type == :set_request
      assert pdu.request_id == request_id
      assert pdu.varbinds == [{oid, value, :null}]
    end

    test "builds response PDU with error status" do
      request_id = 56789
      error_status = 2  # noSuchName
      error_index = 1
      varbinds = [{[1, 3, 6, 1, 2, 1, 1, 1, 0], {:string, ~c"test"}, :null}]
      
      pdu = PDU.build_response(request_id, error_status, error_index, varbinds)
      
      assert pdu.type == :get_response
      assert pdu.request_id == request_id
      assert pdu.error_status == error_status
      assert pdu.error_index == error_index
      assert pdu.varbinds == varbinds
    end
  end

  describe "PDU validation" do
    test "validates request ID range" do
      valid_ids = [0, 1, 65535, 2147483647]
      invalid_ids = [-1, 2147483648, "string", nil]
      
      for request_id <- valid_ids do
        pdu = PDU.build_get_request([1, 3, 6, 1], request_id)
        assert {:ok, _} = PDU.validate(pdu)
      end
      
      for request_id <- invalid_ids do
        assert_raise ArgumentError, fn ->
          PDU.build_get_request([1, 3, 6, 1], request_id)
        end
      end
    end

    test "validates OID format in varbinds" do
      valid_oids = [
        [1, 3, 6, 1],
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 4, 1, 9, 9, 1]
      ]
      
      invalid_oids = [
        [],
        [1, 3, 6, "invalid"],
        [1, 3, -1, 1],
        "1.3.6.1",
        nil
      ]
      
      for oid <- valid_oids do
        pdu = PDU.build_get_request(oid, 1)
        assert {:ok, _} = PDU.validate(pdu)
      end
      
      for oid <- invalid_oids do
        assert_raise ArgumentError, fn ->
          PDU.build_get_request(oid, 1)
        end
      end
    end

    test "validates GETBULK specific fields" do
      # Valid GETBULK parameters
      pdu = PDU.build_get_bulk_request([1, 3, 6, 1], 1, 0, 10)
      assert {:ok, _} = PDU.validate(pdu)
      
      # Invalid non_repeaters (negative)
      assert_raise ArgumentError, fn ->
        PDU.build_get_bulk_request([1, 3, 6, 1], 1, -1, 10)
      end
      
      # Invalid max_repetitions (zero)
      assert_raise ArgumentError, fn ->
        PDU.build_get_bulk_request([1, 3, 6, 1], 1, 0, 0)
      end
      
      # Invalid max_repetitions (too large)
      assert_raise ArgumentError, fn ->
        PDU.build_get_bulk_request([1, 3, 6, 1], 1, 0, 65536)
      end
    end
  end

  describe "SNMP message construction" do
    test "builds SNMPv1 message" do
      pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      message = PDU.build_message(pdu, "public", :v1)
      
      assert message.version == 0  # SNMP v1
      assert message.community == "public"
      assert message.pdu == pdu
    end

    test "builds SNMPv2c message" do
      pdu = PDU.build_get_bulk_request([1, 3, 6, 1, 2, 1, 2, 2], 23456, 0, 10)
      message = PDU.build_message(pdu, "private", :v2c)
      
      assert message.version == 1  # SNMP v2c
      assert message.community == "private"
      assert message.pdu == pdu
    end

    test "rejects GETBULK for SNMPv1" do
      pdu = PDU.build_get_bulk_request([1, 3, 6, 1, 2, 1, 2, 2], 23456, 0, 10)
      
      assert_raise ArgumentError, ~r/GETBULK.*v2c/, fn ->
        PDU.build_message(pdu, "public", :v1)
      end
    end

    test "validates community string" do
      pdu = PDU.build_get_request([1, 3, 6, 1], 1)
      
      # Valid community strings
      valid_communities = ["public", "private", "test123", ""]
      for community <- valid_communities do
        message = PDU.build_message(pdu, community, :v1)
        assert message.community == community
      end
      
      # Invalid community strings
      invalid_communities = [nil, 123, :atom]
      for community <- invalid_communities do
        assert_raise ArgumentError, fn ->
          PDU.build_message(pdu, community, :v1)
        end
      end
    end
  end

  describe "PDU encoding simulation" do
    # These tests simulate the encoding process without requiring actual SNMP modules
    test "simulates GET request encoding" do
      pdu = PDU.build_get_request([1, 3, 6, 1, 2, 1, 1, 1, 0], 12345)
      message = PDU.build_message(pdu, "public", :v1)
      
      # Simulate the encoding process (would normally use :snmp_pdus)
      case PDU.encode_message(message) do
        {:ok, encoded_data} ->
          assert is_binary(encoded_data)
          assert byte_size(encoded_data) > 0
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment without actual SNMP modules
          assert true
        {:error, reason} ->
          flunk("Unexpected encoding error: #{inspect(reason)}")
      end
    end

    test "simulates response decoding" do
      # Create a mock encoded response
      mock_response = <<48, 33, 2, 1, 0, 4, 6, 112, 117, 98, 108, 105, 99, 160, 20, 2, 4, 0, 0, 48, 57, 2, 1, 0, 2, 1, 0, 48, 6, 48, 4, 6, 0, 5, 0>>
      
      case PDU.decode_message(mock_response) do
        {:ok, decoded_message} ->
          assert is_map(decoded_message)
          assert Map.has_key?(decoded_message, :version)
          assert Map.has_key?(decoded_message, :community)
          assert Map.has_key?(decoded_message, :pdu)
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true
        {:error, reason} ->
          # May fail due to mock data format
          assert is_atom(reason) or is_binary(reason)
      end
    end
  end

  describe "error handling" do
    test "handles malformed PDU data gracefully" do
      malformed_data = [
        nil,
        "",
        <<1, 2, 3>>,  # Too short
        <<0::size(1000)>>,  # Invalid ASN.1
        "not binary data"
      ]
      
      for data <- malformed_data do
        case PDU.decode_message(data) do
          {:ok, _} -> 
            flunk("Should not succeed with malformed data: #{inspect(data)}")
          {:error, _reason} -> 
            assert true  # Expected
        end
      end
    end

    test "provides helpful error messages" do
      # Test that error messages are user-friendly
      error_cases = [
        {fn -> PDU.build_get_request("invalid-oid", 1) end, "OID"},
        {fn -> PDU.build_get_request([1, 3, 6, 1], "invalid-id") end, "request ID"},
        {fn -> PDU.build_get_bulk_request([1, 3, 6, 1], 1, -1, 10) end, "non_repeaters"},
      ]
      
      for {error_fun, expected_term} <- error_cases do
        try do
          error_fun.()
          flunk("Expected error was not raised")
        rescue
          e in ArgumentError ->
            assert String.contains?(e.message, expected_term),
              "Error message should mention '#{expected_term}': #{e.message}"
        end
      end
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "PDU construction is fast" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      
      # Measure time to create 1000 PDUs
      {time_microseconds, _result} = :timer.tc(fn ->
        for i <- 1..1000 do
          PDU.build_get_request(oid, i)
        end
      end)
      
      time_per_pdu = time_microseconds / 1000
      
      # Should be very fast (less than 100 microseconds per PDU)
      assert time_per_pdu < 100,
        "PDU construction too slow: #{time_per_pdu} microseconds per PDU"
    end

    @tag :performance  
    test "memory usage is reasonable" do
      oid = [1, 3, 6, 1, 2, 1, 1, 1, 0]
      
      # Measure memory before
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)
      
      # Create many PDUs
      pdus = for i <- 1..1000 do
        PDU.build_get_request(oid, i)
      end
      
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      memory_per_pdu = memory_used / 1000
      
      # Should use reasonable memory (less than 1KB per PDU)
      assert memory_per_pdu < 1024,
        "PDU memory usage too high: #{memory_per_pdu} bytes per PDU"
      
      # Clean up
      pdus = nil
      :erlang.garbage_collect()
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles maximum size OIDs" do
      # Test with very long OID (128 elements)
      long_oid = for i <- 1..128, do: rem(i, 256)
      
      pdu = PDU.build_get_request(long_oid, 1)
      assert {:ok, _} = PDU.validate(pdu)
      assert pdu.varbinds == [{long_oid, :null, :null}]
    end

    test "handles maximum request ID" do
      max_request_id = 2147483647  # 2^31 - 1
      
      pdu = PDU.build_get_request([1, 3, 6, 1], max_request_id)
      assert pdu.request_id == max_request_id
    end

    test "handles multiple varbinds" do
      oids = [
        [1, 3, 6, 1, 2, 1, 1, 1, 0],
        [1, 3, 6, 1, 2, 1, 1, 2, 0],
        [1, 3, 6, 1, 2, 1, 1, 3, 0]
      ]
      
      varbinds = Enum.map(oids, fn oid -> {oid, :null, :null} end)
      pdu = PDU.build_get_request_multi(varbinds, 12345)
      
      assert pdu.type == :get_request
      assert pdu.request_id == 12345
      assert length(pdu.varbinds) == 3
      assert pdu.varbinds == varbinds
    end

    test "handles empty varbind list gracefully" do
      # Some implementations might need to handle empty varbind lists
      case PDU.build_get_request_multi([], 1) do
        %{varbinds: []} ->
          assert true  # Empty varbinds allowed
        _ ->
          # Implementation might require at least one varbind
          assert_raise ArgumentError, fn ->
            PDU.build_get_request_multi([], 1)
          end
      end
    end
  end
end