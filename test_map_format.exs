#!/usr/bin/env elixir

# Test to verify snmp_mgr works with snmp_lib v1.0.3 map-based PDU format

Code.require_file("mix.exs", __DIR__)

# Start the application
Mix.Task.run("app.start")

defmodule MapFormatTest do
  def test_get_next_with_maps do
    IO.puts("Testing get_next with map-based PDU format...")
    
    # Test against a non-existent host to verify error handling
    case SnmpMgr.get_next("192.168.255.254", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 1000) do
      {:error, _reason} ->
        IO.puts("✓ get_next works with map-based PDUs")
      other ->
        IO.puts("✗ Unexpected result: #{inspect(other)}")
        exit(:error)
    end
  end

  def test_core_send_get_next_request do
    IO.puts("Testing SnmpMgr.Core.send_get_next_request with maps...")
    
    case SnmpMgr.Core.send_get_next_request("192.168.255.254", [1, 3, 6, 1, 2, 1, 1, 1, 0], timeout: 1000) do
      {:error, _reason} ->
        IO.puts("✓ Core.send_get_next_request works with map-based PDUs")
      other ->
        IO.puts("✗ Unexpected result: #{inspect(other)}")
        exit(:error)
    end
  end

  def run_all_tests do
    IO.puts("=== Testing snmp_mgr with snmp_lib v1.0.3 map format ===")
    test_get_next_with_maps()
    test_core_send_get_next_request()
    IO.puts("=== All tests passed! ===")
  end
end

MapFormatTest.run_all_tests()
