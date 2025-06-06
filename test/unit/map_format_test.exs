defmodule SnmpMgr.MapFormatTest do
  use ExUnit.Case
  alias SnmpMgr.Core

  describe "Map Format Support" do
    test "send_get_next_request handles timeout errors with map format" do
      # Test against a non-existent host to verify error handling with maps
      result = Core.send_get_next_request("192.168.255.254", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 1000)
      
      assert {:error, _reason} = result
    end

    test "send_get_bulk_request handles timeout errors with map format" do
      # Test against a non-existent host to verify error handling with maps
      result = Core.send_get_bulk_request("192.168.255.254", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 1000)
      
      assert {:error, _reason} = result
    end

    test "send_get_request handles timeout errors with map format" do
      # Test against a non-existent host to verify error handling with maps
      result = Core.send_get_request("192.168.255.254", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 1000)
      
      assert {:error, _reason} = result
    end
  end
end
