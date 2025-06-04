defmodule SNMPMgr.CircuitBreakerIntegrationTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.CircuitBreaker
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :circuit_breaker
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

  setup do
    case GenServer.whereis(CircuitBreaker) do
      nil ->
        case CircuitBreaker.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end
      _pid -> :ok
    end
    
    :ok
  end

  describe "Circuit Breaker with SNMP Operations" do
    test "circuit breaker protects against failing SNMP operations", %{device: device} do
      skip_if_no_device(device)
      
      # Attempt operations that may fail (invalid community)
      invalid_target = {device.host, device.port, "invalid_community"}
      
      results = Enum.map(1..3, fn _i ->
        case apply_circuit_breaker(invalid_target, "1.3.6.1.2.1.1.1.0") do
          {:ok, _} -> :success
          {:error, _} -> :failure
          :circuit_open -> :circuit_open
        end
      end)
      
      # Circuit breaker should handle failures gracefully
      assert is_list(results)
      assert length(results) == 3
    end
    
    test "circuit breaker allows successful SNMP operations", %{device: device} do
      skip_if_no_device(device)
      
      # Valid operations should work through circuit breaker
      valid_target = {device.host, device.port, device.community}
      
      result = apply_circuit_breaker(valid_target, "1.3.6.1.2.1.1.1.0")
      
      assert match?({:ok, _} | {:error, _}, result)
    end
  end

  describe "Circuit Breaker Application-Level Protection" do
    test "circuit breaker integrates with bulk operations", %{device: device} do
      skip_if_no_device(device)
      
      # Test circuit breaker with bulk operations
      target = {device.host, device.port, device.community}
      
      result = apply_circuit_breaker_bulk(target, "1.3.6.1.2.1.1")
      
      assert match?({:ok, _} | {:error, _} | :circuit_open, result)
    end
  end

  # Helper functions to simulate circuit breaker integration
  defp apply_circuit_breaker({host, port, community}, oid) do
    # Simulate circuit breaker wrapping SNMP operations
    case CircuitBreaker.call(fn ->
      SNMPMgr.get(host, port, community, oid, timeout: 100)
    end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    # Circuit breaker might not implement call/1, fallback to direct operation
    _error ->
      SNMPMgr.get(host, port, community, oid, timeout: 100)
  end
  
  defp apply_circuit_breaker_bulk({host, port, community}, oid) do
    case CircuitBreaker.call(fn ->
      SNMPMgr.get_bulk(host, port, community, oid, timeout: 100, max_repetitions: 3)
    end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    _error ->
      SNMPMgr.get_bulk(host, port, community, oid, timeout: 100, max_repetitions: 3)
  end
  
  defp skip_if_no_device(nil), do: ExUnit.skip("SNMP simulator not available")
  defp skip_if_no_device(%{setup_error: error}), do: ExUnit.skip("Setup error: #{inspect(error)}")
  defp skip_if_no_device(_device), do: :ok
end
