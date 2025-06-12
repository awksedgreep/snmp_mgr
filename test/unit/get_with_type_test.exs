defmodule SnmpMgr.GetWithTypeTest do
  use ExUnit.Case, async: true
  doctest SnmpMgr

  describe "get_with_type/3" do
    test "returns error for invalid target" do
      result = SnmpMgr.get_with_type("invalid_host", "1.3.6.1.2.1.1.1.0")
      assert {:error, _reason} = result
    end

    test "returns error for timeout" do
      # Use a non-responsive IP to trigger timeout
      result = SnmpMgr.get_with_type("192.0.2.1", "1.3.6.1.2.1.1.1.0", timeout: 100)
      assert {:error, :timeout} = result
    end

    test "accepts valid parameters without error" do
      # This test just ensures the function accepts the right parameters
      # and doesn't crash on compilation
      assert is_function(&SnmpMgr.get_with_type/3, 3)
    end
  end
end
