# SNMPMgr Module Guide

The `SNMPMgr` module is the main entry point for all SNMP operations. It provides a simple, stateless interface for performing SNMP GET, SET, GETNEXT, GETBULK, and WALK operations.

## Overview

All functions in this module are stateless and can be called directly without any setup or configuration (though global configuration is available through `SNMPMgr.Config`).

## Core Operations

### GET Operations

#### `get/3`

Performs an SNMP GET request to retrieve a single value.

```elixir
get(target, oid, opts \\ [])
```

**Parameters:**
- `target` - Device address (string): `"192.168.1.1"`, `"device.local:161"`
- `oid` - Object Identifier: `"1.3.6.1.2.1.1.1.0"` or `"sysDescr.0"`
- `opts` - Keyword list of options

**Returns:**
- `{:ok, value}` - Success with retrieved value
- `{:error, reason}` - Error with reason atom

**Examples:**

```elixir
# Basic GET request
{:ok, description} = SNMPMgr.get("192.168.1.1", "1.3.6.1.2.1.1.1.0", 
                                community: "public")

# Using symbolic names
{:ok, uptime} = SNMPMgr.get("router.local", "sysUpTime.0", 
                           community: "public", timeout: 5000)

# With custom options
{:ok, contact} = SNMPMgr.get("switch.local", "sysContact.0",
                            community: "private", 
                            version: :v2c,
                            timeout: 3000,
                            retries: 2)
```

#### `get_next/3`

Performs an SNMP GETNEXT request to retrieve the next OID in the MIB tree.

```elixir
get_next(target, oid, opts \\ [])
```

**Returns:**
- `{:ok, {next_oid, value}}` - Success with next OID and its value
- `{:error, reason}` - Error with reason

**Examples:**

```elixir
# Get next OID in system group
{:ok, {next_oid, value}} = SNMPMgr.get_next("192.168.1.1", "1.3.6.1.2.1.1", 
                                           community: "public")

# Starting from a symbolic name
{:ok, {oid, val}} = SNMPMgr.get_next("device.local", "sysDescr",
                                    community: "public")
```

### BULK Operations

#### `get_bulk/3`

Performs an SNMP GETBULK request for efficient retrieval of multiple values (SNMP v2c only).

```elixir
get_bulk(target, oid, opts \\ [])
```

**Key Options:**
- `:max_repetitions` - Maximum number of repetitions (default: 10)
- `:non_repeaters` - Number of non-repeating variables (default: 0)

**Returns:**
- `{:ok, results}` - List of `{oid, value}` tuples
- `{:error, reason}` - Error with reason

**Examples:**

```elixir
# Get multiple interface descriptions efficiently
{:ok, interfaces} = SNMPMgr.get_bulk("192.168.1.1", "ifDescr", 
                                    max_repetitions: 20,
                                    community: "public")

# Bulk request with custom settings
{:ok, data} = SNMPMgr.get_bulk("switch.local", "1.3.6.1.2.1.2.2",
                              max_repetitions: 50,
                              non_repeaters: 0,
                              community: "public",
                              timeout: 10000)
```

### SET Operations

#### `set/4`

Performs an SNMP SET request to modify a value on the target device.

```elixir
set(target, oid, value, opts \\ [])
```

**Parameters:**
- `value` - The value to set (string, integer, or specific SNMP type)

**Returns:**
- `{:ok, value}` - Success with the set value
- `{:error, reason}` - Error with reason

**Examples:**

```elixir
# Set system contact
{:ok, _} = SNMPMgr.set("192.168.1.1", "sysContact.0", "admin@company.com",
                      community: "private")

# Set with explicit type
{:ok, _} = SNMPMgr.set("device.local", "1.3.6.1.2.1.1.6.0", "Server Room A",
                      community: "private", 
                      type: :string)

# Set integer value
{:ok, _} = SNMPMgr.set("192.168.1.1", "customOID.0", 42,
                      community: "private")
```

### WALK Operations

#### `walk/3`

Performs an SNMP walk to retrieve all values under a given OID subtree.

```elixir
walk(target, oid, opts \\ [])
```

**Returns:**
- `{:ok, results}` - List of `{oid, value}` tuples
- `{:error, reason}` - Error with reason

**Examples:**

```elixir
# Walk entire system group
{:ok, system_info} = SNMPMgr.walk("192.168.1.1", "1.3.6.1.2.1.1", 
                                 community: "public")

# Walk interface table
{:ok, interfaces} = SNMPMgr.walk("switch.local", "ifTable",
                                community: "public", 
                                timeout: 15000)

# Process walk results
Enum.each(system_info, fn {oid, value} ->
  IO.puts("#{oid}: #{value}")
end)
```

### Multi-Target Operations

#### `get_multi/1`

Performs GET requests on multiple targets concurrently.

```elixir
get_multi(requests)
```

**Parameters:**
- `requests` - List of `{target, oid, opts}` tuples

**Returns:**
- List of results in the same order as requests

**Examples:**

```elixir
# Query multiple devices
requests = [
  {"192.168.1.1", "sysDescr.0", [community: "public"]},
  {"192.168.1.2", "sysDescr.0", [community: "public"]},
  {"192.168.1.3", "sysUpTime.0", [community: "public"]}
]

results = SNMPMgr.get_multi(requests)

# Process results
Enum.zip(requests, results)
|> Enum.each(fn {{target, _oid, _opts}, result} ->
  case result do
    {:ok, value} -> IO.puts("#{target}: #{value}")
    {:error, reason} -> IO.puts("#{target}: Error - #{reason}")
  end
end)
```

#### `get_bulk_multi/1`

Performs GETBULK requests on multiple targets concurrently.

```elixir
get_bulk_multi(requests)
```

**Examples:**

```elixir
# Bulk requests to multiple devices
bulk_requests = [
  {"192.168.1.1", "ifDescr", [max_repetitions: 10, community: "public"]},
  {"192.168.1.2", "ifDescr", [max_repetitions: 10, community: "public"]}
]

results = SNMPMgr.get_bulk_multi(bulk_requests)
```

## Advanced Features

### Table Operations

#### `get_table/3`

Retrieves an entire SNMP table efficiently.

```elixir
get_table(target, table_oid, opts \\ [])
```

**Examples:**

```elixir
# Get interface table
{:ok, if_table} = SNMPMgr.get_table("192.168.1.1", "ifTable",
                                   community: "public")

# Get ARP table  
{:ok, arp_table} = SNMPMgr.get_table("router.local", "ipNetToMediaTable",
                                    community: "public")
```

### Streaming Operations

#### `stream/3`

Creates a stream for large SNMP operations.

```elixir
stream(target, oid, opts \\ [])
```

**Examples:**

```elixir
# Stream large routing table
"192.168.1.1"
|> SNMPMgr.stream("ipRouteTable", community: "public")
|> Enum.take(100)  # Process first 100 entries
|> Enum.each(fn {oid, value} ->
  IO.puts("Route: #{oid} = #{value}")
end)
```

## Options Reference

### Common Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:community` | String | "public" | SNMP community string |
| `:timeout` | Integer | 5000 | Request timeout in milliseconds |
| `:retries` | Integer | 1 | Number of retry attempts |
| `:version` | Atom | `:v1` | SNMP version (`:v1` or `:v2c`) |

### Bulk-Specific Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:max_repetitions` | Integer | 10 | Maximum repetitions for bulk operations |
| `:non_repeaters` | Integer | 0 | Non-repeating variables in bulk operations |

### SET-Specific Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:type` | Atom | auto-detected | Explicit SNMP type for the value |

## Error Handling

### Common Error Reasons

| Error | Description |
|-------|-------------|
| `:timeout` | Request timed out |
| `:noSuchObject` | OID does not exist on target |
| `:noSuchInstance` | OID instance does not exist |
| `:endOfMibView` | Reached end of MIB tree (in walks) |
| `:genErr` | General SNMP error |
| `:tooBig` | Response too large |
| `:noAccess` | Access denied |
| `:wrongType` | Incorrect value type for SET |
| `:wrongLength` | Incorrect value length for SET |
| `:wrongEncoding` | Incorrect value encoding for SET |
| `:wrongValue` | Incorrect value for SET |
| `:noCreation` | Object cannot be created |
| `:inconsistentValue` | Value is inconsistent |
| `:resourceUnavailable` | Resource not available |
| `:commitFailed` | Commit operation failed |
| `:undoFailed` | Undo operation failed |
| `:authorizationError` | Authorization failed |
| `:notWritable` | Object is read-only |
| `:inconsistentName` | Name is inconsistent |

### Error Handling Patterns

```elixir
# Basic error handling
case SNMPMgr.get("device", "oid") do
  {:ok, value} -> process_value(value)
  {:error, :timeout} -> retry_or_log_timeout()
  {:error, :noSuchObject} -> handle_missing_object()
  {:error, reason} -> log_error(reason)
end

# With error logging
with {:ok, desc} <- SNMPMgr.get(target, "sysDescr.0", community: "public"),
     {:ok, name} <- SNMPMgr.get(target, "sysName.0", community: "public") do
  {:ok, %{description: desc, name: name}}
else
  {:error, reason} -> 
    Logger.error("SNMP operation failed: #{inspect(reason)}")
    {:error, reason}
end
```

## Performance Considerations

### Choosing the Right Operation

1. **Single values**: Use `get/3`
2. **Multiple related values**: Use `get_bulk/3`
3. **Table data**: Use `get_table/3` or `walk/3`
4. **Large datasets**: Use `stream/3`
5. **Multiple devices**: Use `get_multi/1` or `get_bulk_multi/1`

### Optimization Tips

```elixir
# Prefer bulk operations for multiple values
{:ok, results} = SNMPMgr.get_bulk("device", "ifDescr", max_repetitions: 20)

# Use appropriate timeouts
{:ok, value} = SNMPMgr.get("device", "oid", timeout: 2000)  # Fast network
{:ok, value} = SNMPMgr.get("device", "oid", timeout: 10000) # Slow network

# Limit bulk operations
{:ok, results} = SNMPMgr.get_bulk("device", "largeTable", max_repetitions: 50)

# Use concurrent operations for multiple devices
requests = build_requests(devices)
results = SNMPMgr.get_multi(requests)
```

## Integration Examples

### With GenServer

```elixir
defmodule DeviceMonitor do
  use GenServer
  
  def start_link(device_ip) do
    GenServer.start_link(__MODULE__, device_ip)
  end
  
  def init(device_ip) do
    schedule_poll()
    {:ok, %{device: device_ip, last_uptime: nil}}
  end
  
  def handle_info(:poll, %{device: device} = state) do
    case SNMPMgr.get(device, "sysUpTime.0", community: "public") do
      {:ok, uptime} -> 
        handle_uptime_change(state.last_uptime, uptime)
        schedule_poll()
        {:noreply, %{state | last_uptime: uptime}}
      {:error, reason} ->
        Logger.error("Failed to poll #{device}: #{reason}")
        schedule_poll()
        {:noreply, state}
    end
  end
  
  defp schedule_poll do
    Process.send_after(self(), :poll, 30_000)  # Poll every 30 seconds
  end
end
```

### With Task.async

```elixir
defmodule NetworkScanner do
  def scan_network(ip_range) do
    ip_range
    |> Enum.map(&Task.async(fn -> discover_device(&1) end))
    |> Task.await_many(5000)
    |> Enum.filter(& &1.reachable)
  end
  
  defp discover_device(ip) do
    case SNMPMgr.get(ip, "sysDescr.0", community: "public", timeout: 2000) do
      {:ok, description} -> 
        %{ip: ip, reachable: true, description: description}
      {:error, _} -> 
        %{ip: ip, reachable: false, description: nil}
    end
  end
end
```