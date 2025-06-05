# SnmpMgr.Multi Module Guide

The `SnmpMgr.Multi` module provides concurrent multi-target SNMP operations, allowing you to perform SNMP requests against multiple devices simultaneously for improved performance and efficiency.

## Overview

The Multi module is designed for scenarios where you need to:
- Query multiple devices for the same information
- Collect data from many devices quickly
- Perform bulk operations across a network
- Handle large-scale device monitoring

All operations are performed concurrently with configurable limits and timeouts.

## Core Functions

### `get_multi/2`

Performs GET operations against multiple targets concurrently.

```elixir
get_multi(targets_and_oids, opts \\ [])
```

**Parameters:**
- `targets_and_oids` - List of request specifications
- `opts` - Global options applied to all requests

**Request Formats:**
```elixir
# Basic format: {target, oid}
{"192.168.1.1", "sysDescr.0"}

# With per-request options: {target, oid, opts}
{"192.168.1.1", "sysDescr.0", [community: "private", timeout: 3000]}
```

**Examples:**

```elixir
# Basic multi-device GET
requests = [
  {"192.168.1.1", "sysDescr.0"},
  {"192.168.1.2", "sysDescr.0"},
  {"192.168.1.3", "sysDescr.0"}
]

results = SnmpMgr.Multi.get_multi(requests, community: "public")
# [
#   {:ok, "Device 1 Description"},
#   {:ok, "Device 2 Description"}, 
#   {:error, :timeout}
# ]

# Mixed OIDs with per-request options
requests = [
  {"router.local", "sysUpTime.0", [community: "public"]},
  {"switch.local", "ifNumber.0", [community: "private", timeout: 2000]},
  {"server.local", "sysName.0", [community: "public", retries: 3]}
]

results = SnmpMgr.Multi.get_multi(requests)
```

### `get_bulk_multi/2`

Performs GETBULK operations against multiple targets concurrently.

```elixir
get_bulk_multi(targets_and_oids, opts \\ [])
```

**Examples:**

```elixir
# Bulk requests to multiple devices
bulk_requests = [
  {"192.168.1.1", "ifDescr", [max_repetitions: 10]},
  {"192.168.1.2", "ifDescr", [max_repetitions: 10]},
  {"192.168.1.3", "ifSpeed", [max_repetitions: 20]}
]

results = SnmpMgr.Multi.get_bulk_multi(bulk_requests, 
                                      community: "public", 
                                      timeout: 10000)

# Process bulk results
Enum.each(results, fn
  {:ok, interfaces} when is_list(interfaces) ->
    IO.puts("Found #{length(interfaces)} interfaces")
  {:error, reason} ->
    IO.puts("Bulk request failed: #{reason}")
end)
```

### `walk_multi/2`

Performs WALK operations against multiple targets concurrently.

```elixir
walk_multi(targets_and_oids, opts \\ [])
```

**Examples:**

```elixir
# Walk system groups on multiple devices
walk_requests = [
  {"192.168.1.1", "1.3.6.1.2.1.1"},
  {"192.168.1.2", "1.3.6.1.2.1.1"},
  {"192.168.1.3", "1.3.6.1.2.1.1"}
]

results = SnmpMgr.Multi.walk_multi(walk_requests, community: "public")

# Process walk results
Enum.zip(["Device1", "Device2", "Device3"], results)
|> Enum.each(fn {device_name, result} ->
  case result do
    {:ok, system_info} ->
      IO.puts("#{device_name}: #{length(system_info)} system objects")
    {:error, reason} ->
      IO.puts("#{device_name}: Walk failed - #{reason}")
  end
end)
```

### `set_multi/2`

Performs SET operations against multiple targets concurrently.

```elixir
set_multi(targets_oids_values, opts \\ [])
```

**Request Format:**
```elixir
# {target, oid, value} or {target, oid, value, opts}
{"192.168.1.1", "sysContact.0", "admin@company.com"}
{"192.168.1.2", "sysLocation.0", "Server Room A", [community: "private"]}
```

**Examples:**

```elixir
# Set contact information on multiple devices
set_requests = [
  {"192.168.1.1", "sysContact.0", "admin@company.com"},
  {"192.168.1.2", "sysContact.0", "admin@company.com"},
  {"192.168.1.3", "sysContact.0", "admin@company.com"}
]

results = SnmpMgr.Multi.set_multi(set_requests, community: "private")

# Verify all sets succeeded
all_successful = Enum.all?(results, fn
  {:ok, _} -> true
  {:error, _} -> false
end)

if all_successful do
  IO.puts("Contact information updated on all devices")
else
  IO.puts("Some SET operations failed")
end
```

## Configuration Options

### Global Options

These options apply to all requests in a multi-operation:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:timeout` | Integer | 10000 | Global timeout for all requests (ms) |
| `:max_concurrent` | Integer | 10 | Maximum concurrent requests |
| `:community` | String | "public" | Default community string |
| `:retries` | Integer | 1 | Default retry attempts |
| `:version` | Atom | `:v1` | Default SNMP version |

### Per-Request Options

Options can be specified for individual requests:

```elixir
requests = [
  # Uses global options
  {"device1", "sysDescr.0"},
  
  # Override timeout for slow device
  {"slow_device", "sysDescr.0", [timeout: 20000]},
  
  # Different community for secure device
  {"secure_device", "sysDescr.0", [community: "private", retries: 3]}
]

SnmpMgr.Multi.get_multi(requests, community: "public", timeout: 5000)
```

## Advanced Features

### Concurrent Limit Control

```elixir
# Limit concurrent requests to prevent overwhelming network/devices
requests = build_large_request_list(100)  # 100 devices

results = SnmpMgr.Multi.get_multi(requests, 
                                 max_concurrent: 5,  # Only 5 concurrent requests
                                 timeout: 15000)
```

### Error Handling and Retries

```elixir
# Configure retries for unreliable networks
requests = [
  {"unreliable_device1", "sysDescr.0", [retries: 5, timeout: 3000]},
  {"unreliable_device2", "sysDescr.0", [retries: 3, timeout: 5000]}
]

results = SnmpMgr.Multi.get_multi(requests, retries: 2)  # Global default

# Process results with error categorization
{successful, failed} = Enum.split_with(results, fn
  {:ok, _} -> true
  {:error, _} -> false
end)

IO.puts("Successful: #{length(successful)}, Failed: #{length(failed)}")
```

### Progress Tracking

```elixir
defmodule ProgressTracker do
  def track_multi_operation(requests, operation_name) do
    total = length(requests)
    IO.puts("Starting #{operation_name} on #{total} devices...")
    
    start_time = System.monotonic_time(:millisecond)
    results = SnmpMgr.Multi.get_multi(requests, community: "public")
    end_time = System.monotonic_time(:millisecond)
    
    duration = end_time - start_time
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = total - successful
    
    IO.puts("""
    #{operation_name} completed in #{duration}ms:
    - Total: #{total}
    - Successful: #{successful}
    - Failed: #{failed}
    - Success rate: #{Float.round(successful / total * 100, 1)}%
    """)
    
    results
  end
end

# Usage
requests = build_device_requests()
results = ProgressTracker.track_multi_operation(requests, "Device Discovery")
```

## Common Use Cases

### Network Device Discovery

```elixir
defmodule NetworkDiscovery do
  def discover_network(ip_range) do
    requests = Enum.map(ip_range, fn ip ->
      {ip, "sysDescr.0", [timeout: 2000, retries: 0]}
    end)
    
    results = SnmpMgr.Multi.get_multi(requests, community: "public")
    
    # Filter reachable devices
    Enum.zip(ip_range, results)
    |> Enum.filter(fn {_ip, result} -> match?({:ok, _}, result) end)
    |> Enum.map(fn {ip, {:ok, description}} ->
      %{
        ip: ip,
        description: description,
        type: classify_device(description)
      }
    end)
  end

  defp classify_device(description) do
    cond do
      String.contains?(description, "Cisco") -> :cisco
      String.contains?(description, "Juniper") -> :juniper
      String.contains?(description, "Linux") -> :linux
      String.contains?(description, "Windows") -> :windows
      true -> :unknown
    end
  end
end

# Discover devices in subnet
ip_range = for i <- 1..254, do: "192.168.1.#{i}"
devices = NetworkDiscovery.discover_network(ip_range)
```

### System Health Monitoring

```elixir
defmodule HealthMonitor do
  @health_oids [
    "sysUpTime.0",
    "sysDescr.0", 
    "ifNumber.0"
  ]

  def check_device_health(device_list) do
    # Create requests for all devices and all health OIDs
    requests = for device <- device_list,
                   oid <- @health_oids,
                   do: {device.ip, oid, [community: device.community]}

    results = SnmpMgr.Multi.get_multi(requests, timeout: 5000)
    
    # Group results by device
    results
    |> Enum.chunk_every(length(@health_oids))
    |> Enum.zip(device_list)
    |> Enum.map(fn {device_results, device} ->
      health_data = parse_health_results(device_results)
      %{device | health: health_data}
    end)
  end

  defp parse_health_results([uptime_result, desc_result, if_count_result]) do
    %{
      uptime: extract_value(uptime_result),
      description: extract_value(desc_result),
      interface_count: extract_value(if_count_result),
      status: determine_status([uptime_result, desc_result, if_count_result])
    }
  end

  defp extract_value({:ok, value}), do: value
  defp extract_value({:error, _}), do: nil

  defp determine_status(results) do
    case Enum.count(results, &match?({:ok, _}, &1)) do
      3 -> :healthy
      2 -> :degraded
      1 -> :warning
      0 -> :critical
    end
  end
end
```

### Interface Statistics Collection

```elixir
defmodule InterfaceStatsCollector do
  @interface_oids [
    "ifDescr",
    "ifOperStatus", 
    "ifInOctets",
    "ifOutOctets",
    "ifSpeed"
  ]

  def collect_all_interfaces(device_list) do
    # Create bulk requests for all devices and interface OIDs
    requests = for device <- device_list,
                   oid <- @interface_oids,
                   do: {device.ip, oid, [
                     max_repetitions: 50,
                     community: device.community
                   ]}

    results = SnmpMgr.Multi.get_bulk_multi(requests, timeout: 15000)
    
    # Process results by device
    results
    |> Enum.chunk_every(length(@interface_oids))
    |> Enum.zip(device_list)
    |> Enum.map(fn {device_results, device} ->
      interfaces = build_interface_table(device_results)
      %{device | interfaces: interfaces}
    end)
  end

  defp build_interface_table([desc_result, status_result, in_result, out_result, speed_result]) do
    # Combine all the interface data into structured format
    case {desc_result, status_result, in_result, out_result, speed_result} do
      {{:ok, descriptions}, {:ok, statuses}, {:ok, in_octets}, {:ok, out_octets}, {:ok, speeds}} ->
        build_interface_list(descriptions, statuses, in_octets, out_octets, speeds)
      _ ->
        []  # Some bulk operation failed
    end
  end
end
```

### Configuration Management

```elixir
defmodule ConfigManager do
  def update_contact_info(devices, contact_info) do
    # Prepare SET requests
    set_requests = Enum.map(devices, fn device ->
      {device.ip, "sysContact.0", contact_info, [community: device.write_community]}
    end)
    
    # Perform all SETs concurrently
    results = SnmpMgr.Multi.set_multi(set_requests, timeout: 10000)
    
    # Verify changes
    verify_requests = Enum.map(devices, fn device ->
      {device.ip, "sysContact.0", [community: device.read_community]}
    end)
    
    verify_results = SnmpMgr.Multi.get_multi(verify_requests)
    
    # Combine set and verify results
    Enum.zip([devices, results, verify_results])
    |> Enum.map(fn {device, set_result, verify_result} ->
      %{
        device: device.ip,
        set_status: set_result,
        verify_status: verify_result,
        success: match?({:ok, _}, set_result) and 
                match?({:ok, ^contact_info}, verify_result)
      }
    end)
  end
end
```

## Performance Optimization

### Batching Large Operations

```elixir
defmodule LargeScaleOperations do
  def process_large_device_list(devices, batch_size \\ 20) do
    devices
    |> Enum.chunk_every(batch_size)
    |> Enum.flat_map(fn batch ->
      requests = Enum.map(batch, fn device ->
        {device.ip, "sysDescr.0", [community: device.community]}
      end)
      
      SnmpMgr.Multi.get_multi(requests, 
                             max_concurrent: 10,
                             timeout: 5000)
    end)
  end
end
```

### Adaptive Timeouts

```elixir
defmodule AdaptiveMulti do
  def smart_multi_get(requests) do
    # Start with shorter timeouts, increase for retries
    fast_requests = Enum.map(requests, fn
      {target, oid} -> {target, oid, [timeout: 2000, retries: 0]}
      {target, oid, opts} -> {target, oid, Keyword.put(opts, :timeout, 2000)}
    end)
    
    fast_results = SnmpMgr.Multi.get_multi(fast_requests)
    
    # Retry failed requests with longer timeout
    failed_indexes = fast_results
    |> Enum.with_index()
    |> Enum.filter(fn {{:error, _}, _index} -> true; _ -> false end)
    |> Enum.map(fn {_, index} -> index end)
    
    if length(failed_indexes) > 0 do
      retry_requests = Enum.map(failed_indexes, fn index ->
        {target, oid, _} = Enum.at(requests, index)
        {target, oid, [timeout: 10000, retries: 2]}
      end)
      
      retry_results = SnmpMgr.Multi.get_multi(retry_requests)
      
      # Merge results
      merge_results(fast_results, retry_results, failed_indexes)
    else
      fast_results
    end
  end
end
```

## Error Handling Best Practices

### Categorizing Errors

```elixir
defmodule ErrorAnalyzer do
  def analyze_multi_results(requests, results) do
    Enum.zip(requests, results)
    |> Enum.group_by(fn {_request, result} ->
      case result do
        {:ok, _} -> :success
        {:error, :timeout} -> :timeout
        {:error, :noSuchObject} -> :no_object
        {:error, :genErr} -> :device_error
        {:error, _} -> :other_error
      end
    end)
    |> Map.new(fn {category, items} ->
      {category, length(items)}
    end)
  end

  def print_error_summary(analysis) do
    total = Enum.sum(Map.values(analysis))
    
    IO.puts("\nMulti-operation Results Summary:")
    IO.puts("Total requests: #{total}")
    
    Enum.each(analysis, fn {category, count} ->
      percentage = Float.round(count / total * 100, 1)
      IO.puts("#{category}: #{count} (#{percentage}%)")
    end)
  end
end
```

### Retry Logic

```elixir
defmodule ResilientMulti do
  def reliable_multi_get(requests, max_retries \\ 3) do
    perform_with_retries(requests, max_retries, [])
  end

  defp perform_with_retries([], _retries, acc), do: Enum.reverse(acc)
  
  defp perform_with_retries(requests, retries_left, acc) when retries_left > 0 do
    results = SnmpMgr.Multi.get_multi(requests)
    
    {successful, failed} = separate_results(requests, results)
    
    if length(failed) > 0 and retries_left > 1 do
      # Retry failed requests
      {failed_requests, _failed_results} = Enum.unzip(failed)
      perform_with_retries(failed_requests, retries_left - 1, 
                          successful ++ acc)
    else
      # Final attempt or no failures
      Enum.reverse(acc) ++ Enum.map(results, fn {_req, result} -> result end)
    end
  end
end
```

## Integration with Other Modules

### Combining with Table Operations

```elixir
# Multi-device table collection
devices = ["192.168.1.1", "192.168.1.2", "192.168.1.3"]

walk_requests = Enum.map(devices, fn ip ->
  {ip, "ifTable", [community: "public", timeout: 10000]}
end)

walk_results = SnmpMgr.Multi.walk_multi(walk_requests)

# Process each device's table data
processed_tables = Enum.zip(devices, walk_results)
|> Enum.map(fn {device_ip, walk_result} ->
  case walk_result do
    {:ok, table_data} ->
      {:ok, table} = SnmpMgr.Table.to_table(table_data, [1,3,6,1,2,1,2,2])
      {device_ip, table}
    {:error, reason} ->
      {device_ip, {:error, reason}}
  end
end)
```

### Using with Configuration

```elixir
# Set global defaults, then use in multi-operations
SnmpMgr.Config.set_default_community("monitoring")
SnmpMgr.Config.set_default_timeout(8000)

# Multi-operations will use these defaults
requests = [
  {"device1", "sysDescr.0"},  # Uses global community "monitoring"
  {"device2", "sysDescr.0", [community: "special"]},  # Overrides to "special"
  {"device3", "sysDescr.0"}   # Uses global community "monitoring"
]

results = SnmpMgr.Multi.get_multi(requests)
```