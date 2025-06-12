# SnmpMgr Library Tour v1.1.0

Welcome to the comprehensive tour of SnmpMgr! This guide will walk you through all the major features using your router at `10.5.50.1` with community string `public`. All examples are ready to copy and paste into your IEx session.

## 🚀 Getting Started

Start your IEx session with the helpful console environment:

```bash
cd /path/to/snmp_mgr
iex -S mix
```

The console will automatically load helper functions and display available modules.

## 📋 Table of Contents

1. [Basic SNMP Operations](#basic-snmp-operations)
2. [System Information](#system-information)
3. [Interface Discovery](#interface-discovery)
4. [Table Operations](#table-operations)
5. [Bulk Operations](#bulk-operations)
6. [Walk Operations](#walk-operations)
7. [Stream Processing](#stream-processing)
8. [Multi-Target Operations](#multi-target-operations)
9. [Type-Aware Processing](#type-aware-processing)
10. [Advanced Features](#advanced-features)

---

## 1. Basic SNMP Operations

### Simple GET Operation
```elixir
# Get system description - notice the 3-tuple format {oid, type, value}
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.1.0")

# Get with type information for consistency with other operations
SnmpMgr.get_with_type("10.5.50.1", "1.3.6.1.2.1.1.1.0")

# Using the helper functions
qget("10.5.50.1", "sysDescr")        # Returns just the value
qget_typed("10.5.50.1", "sysDescr")  # Returns {oid, type, value}
```

### GET with Custom Options
```elixir
# Custom timeout and community
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.1.0", timeout: 10000, community: "public")

# SNMP v2c with specific port
SnmpMgr.get("10.5.50.1:161", "1.3.6.1.2.1.1.1.0", version: :v2c)
```

### GET NEXT Operation
```elixir
# Get the next OID after system description
SnmpMgr.get_next("10.5.50.1", "1.3.6.1.2.1.1.1.0")
```

---

## 2. System Information

### Basic System Info
```elixir
# Get all system information at once
system_info("10.5.50.1")

# Individual system components
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.1.0")  # sysDescr
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.2.0")  # sysObjectID
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.3.0")  # sysUpTime
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.4.0")  # sysContact
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.5.0")  # sysName
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.6.0")  # sysLocation
```

### Formatted Uptime
```elixir
# Get formatted uptime using helper function
uptime("10.5.50.1")

# Raw uptime in timeticks
{:ok, {_oid, :timeticks, raw_ticks}} = SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.3.0")

# Format using SnmpMgr.Format directly
SnmpMgr.Format.uptime(raw_ticks)

# Pretty print any SNMP result
{:ok, result} = SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.3.0")
SnmpMgr.Format.pretty_print(result)
```

---

## 3. Interface Discovery

### Interface Count
```elixir
# Get number of interfaces
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.2.1.0")
```

### Interface Table Walk
```elixir
# Walk the entire interface table - notice 3-tuple format with types!
qwalk("10.5.50.1", "ifTable")

# Or use the full OID
SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")
```

### Specific Interface Information
```elixir
# Get interface descriptions
SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1.2")

# Get interface types
SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1.3")

# Get interface speeds
SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1.5")

# Get interface operational status
SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1.8")
```

---

## 4. Table Operations

### Convert Walk Results to Table Format
```elixir
# First, get interface data
{:ok, if_data} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")

# Convert to structured table (grouped by interface index)
{:ok, table} = SnmpMgr.Table.to_table(if_data, "1.3.6.1.2.1.2.2.1")

# Inspect the table structure
table |> Map.keys() |> Enum.sort()
table[1]  # Look at interface 1 data
```

### Create Map Keyed by Interface Index
```elixir
# Create map keyed by ifIndex (column 1)
{:ok, if_data} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")
{:ok, if_map} = SnmpMgr.Table.to_map(if_data, 1)

# Browse interfaces
if_map |> Map.keys() |> Enum.sort()
if_map[1]  # Interface 1 details
```

### Extract Table Metadata
```elixir
{:ok, if_data} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")
{:ok, table} = SnmpMgr.Table.to_table(if_data, "1.3.6.1.2.1.2.2.1")

# Get all interface indexes
{:ok, indexes} = SnmpMgr.Table.get_indexes(table)

# Get all available columns
{:ok, columns} = SnmpMgr.Table.get_columns(table)

# Convert to row format
{:ok, rows} = SnmpMgr.Table.to_rows(if_data)
```

---

## 5. Bulk Operations

### Bulk GET Operations
```elixir
# Get multiple interface entries efficiently
qbulk("10.5.50.1", "ifTable", max_repetitions: 10)

# Bulk get with custom parameters
SnmpMgr.get_bulk("10.5.50.1", "1.3.6.1.2.1.2.2.1", max_repetitions: 5, non_repeaters: 0)
```

### Bulk Table Retrieval
```elixir
# Get interface table using bulk operations
SnmpMgr.Bulk.get_table("10.5.50.1", "1.3.6.1.2.1.2.2.1", max_repetitions: 10)

# Get ARP table
SnmpMgr.Bulk.get_table("10.5.50.1", "1.3.6.1.2.1.4.22.1", max_repetitions: 20)

# Get routing table
SnmpMgr.Bulk.get_table("10.5.50.1", "1.3.6.1.2.1.4.21.1", max_repetitions: 15)
```

---

## 6. Walk Operations

### Basic Walk
```elixir
# Walk system tree
SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.1")

# Walk interfaces tree
SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2")
```

### Adaptive Walk (Optimized)
```elixir
# Adaptive walk automatically chooses best method (GETNEXT vs GETBULK)
SnmpMgr.AdaptiveWalk.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")

# With custom scope and options
SnmpMgr.AdaptiveWalk.walk("10.5.50.1", "1.3.6.1.2.1.4.22.1", 
  scope: [1, 3, 6, 1, 2, 1, 4, 22, 1], 
  max_repetitions: 25
)
```

### Walk with Filtering
```elixir
# Walk and filter for specific interface types
{:ok, if_data} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")

# Filter for Ethernet interfaces (type 6)
ethernet_interfaces = Enum.filter(if_data, fn {oid, type, value} ->
  String.contains?(oid, "1.3.6.1.2.1.2.2.1.3.") and value == 6
end)
```

---

## 7. Stream Processing

### Type-Aware Filtering
```elixir
# Get interface data and filter by type information
{:ok, if_data} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")

# Filter for string values (interface descriptions)
descriptions = Enum.filter(if_data, fn {_oid, type, _value} ->
  type == :octet_string
end)

# Filter for integer values (interface indexes, types, status)
integers = Enum.filter(if_data, fn {_oid, type, _value} ->
  type == :integer
end)

# Filter for gauge values (interface speeds)
speeds = Enum.filter(if_data, fn {_oid, type, _value} ->
  type == :gauge32
end)
```

### Advanced Stream Processing
```elixir
{:ok, if_data} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")

# Find operational interfaces (ifOperStatus = 1)
operational = Enum.filter(if_data, fn {oid, type, value} ->
  String.contains?(oid, "1.3.6.1.2.1.2.2.1.8.") and 
  type == :integer and 
  value == 1
end)

# Find high-speed interfaces (> 100 Mbps)
high_speed = Enum.filter(if_data, fn {oid, type, value} ->
  String.contains?(oid, "1.3.6.1.2.1.2.2.1.5.") and 
  type == :gauge32 and 
  value > 100_000_000
end)

# Get interface names for operational interfaces
operational_names = operational
|> Enum.map(fn {oid, _type, _value} ->
  # Extract interface index from ifOperStatus OID
  index = oid |> String.split(".") |> List.last()
  # Find corresponding ifDescr
  Enum.find(if_data, fn {desc_oid, _type, _value} ->
    desc_oid == "1.3.6.1.2.1.2.2.1.2.#{index}"
  end)
end)
|> Enum.filter(&(&1 != nil))
```

---

## 8. Multi-Target Operations

### Multiple Device Queries
```elixir
# Define multiple targets (add more of your devices)
targets = [
  %{host: "10.5.50.1", community: "public"},
  # Add more devices as needed:
  # %{host: "10.5.50.2", community: "public"},
  # %{host: "10.5.50.3", community: "public"}
]

# Get system description from all targets
SnmpMgr.Multi.get(targets, "1.3.6.1.2.1.1.1.0")

# Walk interface tables on all targets
SnmpMgr.Multi.walk(targets, "1.3.6.1.2.1.2.2.1")
```

### Parallel Operations with Monitoring
```elixir
# Monitor progress of multi-target operations
monitor_pid = spawn(fn ->
  receive do
    {:progress, target, status} ->
      IO.puts("Target #{target.host}: #{status}")
  end
end)

# Run with progress monitoring
SnmpMgr.Multi.get(targets, "1.3.6.1.2.1.1.1.0", monitor: monitor_pid)
```

---

## 9. Type-Aware Processing

### Understanding SNMP Types
```elixir
# Get various SNMP types and observe the type information
{:ok, results} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.1")

# Group by type to see what types your device returns
results
|> Enum.group_by(fn {_oid, type, _value} -> type end)
|> Enum.map(fn {type, entries} -> {type, length(entries)} end)
```

### Using SnmpMgr.Format Formatting Functions
```elixir
# Get some sample data with different types
{:ok, results} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.1")

# Format timeticks (uptime) - built into snmp_mgr!
{:ok, {_oid, :timeticks, uptime_ticks}} = SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.3.0")
SnmpMgr.Format.uptime(uptime_ticks)
# => "5 days, 12 hours, 34 minutes, 56 seconds"

# Format IP addresses - built into snmp_mgr!
ip_bytes = <<192, 168, 1, 1>>
SnmpMgr.Format.ip_address(ip_bytes)
# => "192.168.1.1"

# Pretty print any SNMP result using SnmpMgr.Format
{:ok, result} = SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.1.0")
SnmpMgr.Format.pretty_print(result)

# Pretty print multiple results
{:ok, results} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.1")
SnmpMgr.Format.pretty_print_all(results) |> Enum.take(5)
```

### Type-Aware Filtering and Processing
```elixir
# Get interface data and process by type
{:ok, if_results} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1")

# Filter by SNMP type using the 3-tuple format
counters = Enum.filter(if_results, fn {_oid, type, _value} -> 
  type in [:counter32, :counter64] 
end)

gauges = Enum.filter(if_results, fn {_oid, type, _value} -> 
  type == :gauge32 
end)

strings = Enum.filter(if_results, fn {_oid, type, _value} -> 
  type == :octet_string 
end)

# Process each type appropriately using SnmpMgr.Format
formatted_results = Enum.map(if_results, fn {oid, type, value} ->
  formatted_value = case type do
    :timeticks -> 
      SnmpMgr.Format.uptime(value)
    :ip_address -> 
      SnmpMgr.Format.ip_address(value)
    :counter32 -> 
      "#{value} (Counter32)"
    :gauge32 -> 
      "#{value} (Gauge32)"
    :octet_string -> 
      inspect(value)
    _ -> 
      inspect(value)
  end
  
  {oid, type, formatted_value}
end)
```

## 10. Advanced Features

### Error Handling and Debugging
```elixir
# Test error handling with invalid OID
SnmpMgr.get("10.5.50.1", "1.2.3.4.5.6.7.8.9.0")

# Test timeout handling
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.1.0", timeout: 1)

# Test invalid community
SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.1.0", community: "wrong")
```

### Performance Testing
```elixir
# Time a walk operation
:timer.tc(fn -> SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1") end)

# Compare walk vs bulk performance
:timer.tc(fn -> SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.2.2.1") end)
:timer.tc(fn -> SnmpMgr.Bulk.get_table("10.5.50.1", "1.3.6.1.2.1.2.2.1") end)
```

### Configuration and Customization
```elixir
# Custom SNMP configuration
custom_opts = [
  version: :v2c,
  timeout: 15000,
  retries: 5,
  community: "public"
]

SnmpMgr.get("10.5.50.1", "1.3.6.1.2.1.1.1.0", custom_opts)
```

### Exploring Your Device
```elixir
# Discover what MIB branches your device supports
branches_to_try = [
  "1.3.6.1.2.1.1",    # System
  "1.3.6.1.2.1.2",    # Interfaces
  "1.3.6.1.2.1.3",    # Address Translation (deprecated)
  "1.3.6.1.2.1.4",    # IP
  "1.3.6.1.2.1.5",    # ICMP
  "1.3.6.1.2.1.6",    # TCP
  "1.3.6.1.2.1.7",    # UDP
  "1.3.6.1.2.1.10",   # Transmission
  "1.3.6.1.2.1.11",   # SNMP
  "1.3.6.1.4.1"       # Enterprise (vendor-specific)
]

# Test each branch
for branch <- branches_to_try do
  case SnmpMgr.get_next("10.5.50.1", branch) do
    {:ok, {oid, type, value}} -> 
      IO.puts("✅ #{branch}: Found #{oid} (#{type}) = #{inspect(value)}")
    {:error, reason} -> 
      IO.puts("❌ #{branch}: #{inspect(reason)}")
  end
end
```

---

## 🎯 Quick Reference Commands

Here are some ready-to-use commands for quick testing:

```elixir
# Quick system info
system_info("10.5.50.1")

# Quick interface overview
qwalk("10.5.50.1", "ifTable") |> Enum.take(10)

# Quick performance test
:timer.tc(fn -> qget("10.5.50.1", "sysDescr") end)

# Quick bulk test
qbulk("10.5.50.1", "ifTable", max_repetitions: 5) |> Enum.take(10)

# Quick type analysis
{:ok, data} = SnmpMgr.walk("10.5.50.1", "1.3.6.1.2.1.1")
data |> Enum.group_by(fn {_, type, _} -> type end) |> Map.keys()
```

---

## 🔍 Troubleshooting

If you encounter issues:

1. **Check connectivity**: `ping 10.5.50.1`
2. **Verify SNMP is enabled**: `snmpwalk -v2c -c public 10.5.50.1 1.3.6.1.2.1.1.1.0`
3. **Check community string**: Try different community strings if "public" doesn't work
4. **Increase timeout**: Add `timeout: 10000` to your options
5. **Try different SNMP version**: Add `version: :v1` or `version: :v2c`

---

## 🎉 Congratulations!

You've completed the SnmpMgr library tour! You should now have a good understanding of:

- ✅ The new 3-tuple format `{oid_string, type, value}`
- ✅ Type-aware processing capabilities
- ✅ All major SNMP operations (GET, GETNEXT, GETBULK, WALK)
- ✅ Table processing and data transformation
- ✅ Stream processing and filtering
- ✅ Multi-target operations
- ✅ Performance optimization techniques

The library is now ready for production use with robust type handling and comprehensive test coverage!

---

*Happy SNMP exploring! 🚀*
