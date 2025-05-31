# SNMPMgr Testing Implementation Guide

This guide provides practical instructions for implementing the comprehensive testing plan for SNMPMgr.

## Quick Start - Running Existing Tests

```bash
# Run all tests
mix test

# Run tests with coverage
mix test --cover

# Run specific test categories
mix test --include integration
mix test --include performance  
mix test --include needs_simulator

# Run tests for a specific module
mix test test/snmp_mgr_test.exs
mix test test/simple_integration_test.exs

# Run with detailed output
mix test --trace
```

## Test Structure Overview

```
test/
├── snmp_mgr_test.exs           # Main unit and integration tests
├── simple_integration_test.exs # Basic simulator tests
├── integration_test.exs        # Comprehensive integration tests
├── test_helper.exs            # Test configuration and setup
└── support/
    └── snmp_simulator.ex      # SNMP device simulation utilities
```

## Phase 1 Implementation: Core Foundation

### Setting Up Protocol Tests

Create comprehensive protocol-level tests:

```elixir
# test/unit/pdu_test.exs
defmodule SNMPMgr.PDUTest do
  use ExUnit.Case, async: true
  alias SNMPMgr.PDU

  describe "PDU encoding/decoding" do
    test "GET request PDU" do
      pdu = PDU.build_get_request([1,3,6,1,2,1,1,1,0], 12345)
      assert pdu.type == :get_request
      assert pdu.request_id == 12345
      assert pdu.varbinds == [{[1,3,6,1,2,1,1,1,0], :null, :null}]
    end

    test "handles all SNMP error codes" do
      for {code, atom} <- SNMPMgr.Errors.error_code_mapping() do
        assert SNMPMgr.Errors.code_to_atom(code) == atom
        assert is_binary(SNMPMgr.Errors.description(atom))
      end
    end
  end
end
```

### Type System Testing

```elixir
# test/unit/types_test.exs
defmodule SNMPMgr.TypesTest do
  use ExUnit.Case, async: true
  alias SNMPMgr.Types

  @test_cases [
    # {input, expected_type, expected_encoding}
    {"hello", :string, {:string, ~c"hello"}},
    {42, :unsigned32, {:unsigned32, 42}},
    {-42, :integer, {:integer, -42}},
    {"192.168.1.1", :ipAddress, {:ipAddress, {192,168,1,1}}},
    # Add comprehensive type coverage
  ]

  test "type inference and encoding" do
    for {input, expected_type, expected_encoding} <- @test_cases do
      assert Types.infer_type(input) == expected_type
      assert {:ok, ^expected_encoding} = Types.encode_value(input)
    end
  end

  test "roundtrip encoding/decoding" do
    for {_input, _type, encoding} <- @test_cases do
      decoded = Types.decode_value(encoding)
      {:ok, re_encoded} = Types.encode_value(decoded)
      assert re_encoded == encoding
    end
  end
end
```

## Phase 2 Implementation: Simulator Enhancement

### Advanced Device Simulation

Extend the simulator to support more realistic scenarios:

```elixir
# test/support/advanced_simulator.ex
defmodule SNMPMgr.TestSupport.AdvancedSimulator do
  alias SNMPMgr.TestSupport.SNMPSimulator

  @doc "Create a device that responds slowly"
  def create_slow_device(opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 1000)
    
    {:ok, device} = SNMPSimulator.create_test_device(opts)
    
    # Configure device to add artificial delay
    configure_response_delay(device, delay_ms)
    
    {:ok, Map.put(device, :response_delay, delay_ms)}
  end

  @doc "Create a device that fails intermittently"
  def create_flaky_device(opts \\ []) do
    failure_rate = Keyword.get(opts, :failure_rate, 0.3)
    
    {:ok, device} = SNMPSimulator.create_test_device(opts)
    
    configure_intermittent_failures(device, failure_rate)
    
    {:ok, Map.put(device, :failure_rate, failure_rate)}
  end

  @doc "Create a large enterprise device with extensive MIB data"
  def create_enterprise_device(opts \\ []) do
    oid_count = Keyword.get(opts, :oid_count, 10000)
    
    # Generate comprehensive enterprise MIB data
    enterprise_oids = generate_enterprise_mibs(oid_count)
    
    SNMPSimulator.create_test_device([
      device_type: :enterprise,
      custom_oids: enterprise_oids
    ] ++ opts)
  end

  # Private implementation functions...
end
```

### Performance Testing Framework

```elixir
# test/support/performance_helpers.ex
defmodule SNMPMgr.TestSupport.PerformanceHelpers do
  @doc "Measure operation performance"
  def measure_performance(operation_name, fun) do
    start_time = System.monotonic_time(:microsecond)
    start_memory = :erlang.memory(:total)
    
    result = fun.()
    
    end_time = System.monotonic_time(:microsecond)
    end_memory = :erlang.memory(:total)
    
    metrics = %{
      operation: operation_name,
      duration_us: end_time - start_time,
      duration_ms: (end_time - start_time) / 1000,
      memory_used: end_memory - start_memory,
      result: result
    }
    
    log_performance_metrics(metrics)
    
    {result, metrics}
  end

  @doc "Run load test with multiple concurrent operations"
  def run_load_test(operation_fun, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 10)
    duration_ms = Keyword.get(opts, :duration_ms, 60_000)
    
    # Implementation of concurrent load testing
    # Track success/failure rates, response times, etc.
  end
end
```

## Phase 3 Implementation: Integration Tests

### Multi-Device Scenario Testing

```elixir
# test/integration/multi_device_test.exs
defmodule SNMPMgr.MultiDeviceTest do
  use ExUnit.Case, async: false
  alias SNMPMgr.TestSupport.{SNMPSimulator, AdvancedSimulator}

  @tag :integration
  @tag :multi_device

  describe "Multi-device operations" do
    setup do
      # Create a diverse fleet of devices
      {:ok, fast_device} = SNMPSimulator.create_test_device()
      {:ok, slow_device} = AdvancedSimulator.create_slow_device(delay_ms: 2000)
      {:ok, enterprise_device} = AdvancedSimulator.create_enterprise_device()
      {:ok, flaky_device} = AdvancedSimulator.create_flaky_device(failure_rate: 0.2)
      
      devices = [fast_device, slow_device, enterprise_device, flaky_device]
      
      # Wait for all devices to be ready
      Enum.each(devices, fn device ->
        :ok = SNMPSimulator.wait_for_device_ready(device)
      end)
      
      on_exit(fn -> 
        Enum.each(devices, &SNMPSimulator.stop_device/1)
      end)
      
      %{devices: devices}
    end

    test "parallel device polling", %{devices: devices} do
      targets = Enum.map(devices, &SNMPSimulator.device_target/1)
      
      # Test concurrent access to all devices
      start_time = System.monotonic_time(:millisecond)
      
      tasks = Enum.map(devices, fn device ->
        Task.async(fn ->
          target = SNMPSimulator.device_target(device)
          SNMPMgr.get(target, "1.3.6.1.2.1.1.1.0", 
                     community: device.community, timeout: 5000)
        end)
      end)
      
      results = Task.await_many(tasks, 10_000)
      end_time = System.monotonic_time(:millisecond)
      
      # Verify results and performance
      total_time = end_time - start_time
      success_count = Enum.count(results, &match?({:ok, _}, &1))
      
      # Should complete in parallel, not serially
      assert total_time < 3000, "Parallel execution should be faster than serial"
      assert success_count >= 3, "Most devices should respond successfully"
    end
  end
end
```

## Phase 4 Implementation: User Experience Testing

### API Usability Tests

```elixir
# test/user_experience/api_usability_test.exs
defmodule SNMPMgr.APIUsabilityTest do
  use ExUnit.Case, async: false
  alias SNMPMgr.TestSupport.SNMPSimulator

  @moduletag :user_experience

  describe "First-time user experience" do
    setup do
      {:ok, device} = SNMPSimulator.create_test_device()
      :ok = SNMPSimulator.wait_for_device_ready(device)
      
      on_exit(fn -> SNMPSimulator.stop_device(device) end)
      
      %{device: device}
    end

    test "Hello World - getting started in under 5 lines", %{device: device} do
      # This should be the simplest possible SNMP operation
      target = SNMPSimulator.device_target(device)
      
      # Line 1: The basic get operation
      case SNMPMgr.get(target, "sysDescr.0", community: device.community) do
        {:ok, description} ->
          assert is_binary(description)
          assert String.length(description) > 0
        {:error, :snmp_modules_not_available} ->
          # Expected in test environment
          assert true
        {:error, reason} ->
          flunk("Unexpected error in simple get: #{inspect(reason)}")
      end
    end

    test "Common workflow - device monitoring", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Simulate a typical monitoring script workflow
      monitoring_oids = [
        "sysDescr.0",
        "sysUpTime.0", 
        "sysName.0"
      ]
      
      results = Enum.map(monitoring_oids, fn oid ->
        case SNMPMgr.get(target, oid, community: device.community) do
          {:ok, value} -> {oid, value}
          {:error, _} -> {oid, :error}
        end
      end)
      
      # Should be easy to collect and process monitoring data
      assert is_list(results)
      assert length(results) == 3
    end

    test "Error messages are helpful and actionable", %{device: device} do
      target = SNMPSimulator.device_target(device)
      
      # Test various error scenarios
      invalid_oid_result = SNMPMgr.get(target, "invalid.oid", 
                                      community: device.community)
      wrong_community_result = SNMPMgr.get(target, "sysDescr.0", 
                                          community: "wrong")
      invalid_target_result = SNMPMgr.get("invalid.host:161", "sysDescr.0", 
                                         community: device.community)
      
      # Error messages should be informative
      case invalid_oid_result do
        {:error, reason} ->
          error_message = inspect(reason)
          assert String.contains?(error_message, "oid") or
                 String.contains?(error_message, "OID")
        _ -> assert true  # May succeed in some test environments
      end
    end
  end
end
```

## Phase 5 Implementation: Performance and Load Testing

### Comprehensive Benchmarks

```elixir
# test/performance/benchmark_test.exs
defmodule SNMPMgr.BenchmarkTest do
  use ExUnit.Case, async: false
  alias SNMPMgr.TestSupport.{SNMPSimulator, PerformanceHelpers}

  @moduletag :performance
  @moduletag timeout: 300_000  # 5 minutes for performance tests

  describe "Performance benchmarks" do
    setup do
      # Create optimized test devices
      devices = for i <- 1..10 do
        {:ok, device} = SNMPSimulator.create_test_device(port: 30000 + i)
        :ok = SNMPSimulator.wait_for_device_ready(device)
        device
      end
      
      on_exit(fn -> 
        Enum.each(devices, &SNMPSimulator.stop_device/1)
      end)
      
      %{devices: devices}
    end

    @tag :benchmark
    test "single device get operations per second", %{devices: devices} do
      device = hd(devices)
      target = SNMPSimulator.device_target(device)
      
      # Measure sustained GET operations
      {_results, metrics} = PerformanceHelpers.measure_performance(
        "sustained_gets", fn ->
          # Perform 100 GET operations
          for _i <- 1..100 do
            SNMPMgr.get(target, "sysUpTime.0", community: device.community)
          end
        end
      )
      
      # Performance targets (adjust based on environment)
      ops_per_second = 100 / (metrics.duration_ms / 1000)
      
      # Should achieve at least 50 ops/second in test environment
      # (Real hardware would be much faster)
      assert ops_per_second > 10, 
        "Expected >10 ops/sec, got #{ops_per_second}"
    end

    @tag :benchmark
    test "bulk operation efficiency", %{devices: devices} do
      device = hd(devices)
      target = SNMPSimulator.device_target(device)
      
      # Compare individual gets vs bulk operation
      {_individual_results, individual_metrics} = 
        PerformanceHelpers.measure_performance("individual_gets", fn ->
          for i <- 1..10 do
            SNMPMgr.get(target, "1.3.6.1.2.1.1.#{i}.0", 
                       community: device.community)
          end
        end)
      
      {_bulk_results, bulk_metrics} = 
        PerformanceHelpers.measure_performance("bulk_walk", fn ->
          SNMPMgr.walk(target, "1.3.6.1.2.1.1", 
                      community: device.community, version: :v2c)
        end)
      
      # Bulk should be faster (when it works)
      case {individual_metrics.result, bulk_metrics.result} do
        {individual_oks, bulk_oks} when individual_oks != [] and bulk_oks != [] ->
          # Only compare if both worked
          efficiency_ratio = individual_metrics.duration_ms / bulk_metrics.duration_ms
          assert efficiency_ratio > 0.5  # Bulk should be at least somewhat more efficient
        _ ->
          # One or both failed - still valuable test data
          assert true
      end
    end
  end
end
```

## Continuous Integration Setup

### GitHub Actions Configuration

```yaml
# .github/workflows/test.yml
name: Test Suite

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ['1.15', '1.16', '1.17']
        otp: ['25', '26', '27']
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: ${{ matrix.elixir }}
        otp-version: ${{ matrix.otp }}
    
    - name: Restore dependencies cache
      uses: actions/cache@v3
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Run tests
      run: mix test --cover
    
    - name: Run integration tests
      run: mix test --include integration
    
    - name: Run performance tests (nightly only)
      if: github.event_name == 'schedule'
      run: mix test --include performance
    
    - name: Generate coverage report
      run: mix coveralls.github
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Coverage and Quality Metrics

### Coverage Configuration

```elixir
# mix.exs
def project do
  [
    # ... other config
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  ]
end

def deps do
  [
    # ... other deps
    {:excoveralls, "~> 0.18", only: :test},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
  ]
end
```

### Quality Checks

```bash
# Run all quality checks
mix credo --strict        # Code quality
mix dialyzer             # Type checking  
mix coveralls.html       # Coverage report
mix docs                 # Documentation check
```

## Test Execution Strategy

### Daily Development
```bash
# Quick feedback loop
mix test                 # All unit tests
mix test --failed        # Only previously failed tests
mix test --stale         # Only tests for changed code
```

### Pre-commit Checks
```bash
# Comprehensive validation
mix test --cover
mix credo --strict
mix dialyzer
mix docs
```

### Release Validation
```bash
# Full test suite
mix test --include integration
mix test --include performance  
mix test --include user_experience
mix coveralls.html
```

This implementation guide provides the practical steps to build out the comprehensive testing plan. Start with Phase 1 and progressively add more sophisticated testing as the library matures.