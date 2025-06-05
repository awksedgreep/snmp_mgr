# SnmpMgr.Table Module Guide

The `SnmpMgr.Table` module provides utilities for processing SNMP table data, converting flat OID/value lists into structured table representations and performing table analysis operations.

## Overview

SNMP tables are represented as a series of OID/value pairs where:
- Each row has a unique index
- Each column represents a different object type
- OIDs follow the pattern: `table.entry.column.index`

The Table module helps convert the flat list format returned by SNMP walks into structured, queryable table formats.

## Core Functions

### `to_table/2`

Converts flat OID/value pairs to a structured table format.

```elixir
to_table(oid_value_pairs, table_oid)
```

**Parameters:**
- `oid_value_pairs` - List of `{oid_string, value}` tuples from table walk
- `table_oid` - Base table OID to determine structure

**Returns:**
- `{:ok, table}` - Structured table as nested maps
- `{:error, reason}` - Error with reason

**Examples:**

```elixir
# Interface table data from SNMP walk
pairs = [
  {"1.3.6.1.2.1.2.2.1.2.1", "eth0"},      # ifDescr.1
  {"1.3.6.1.2.1.2.2.1.2.2", "eth1"},      # ifDescr.2
  {"1.3.6.1.2.1.2.2.1.3.1", 6},           # ifType.1
  {"1.3.6.1.2.1.2.2.1.3.2", 6},           # ifType.2
  {"1.3.6.1.2.1.2.2.1.5.1", 1000000000},  # ifSpeed.1
  {"1.3.6.1.2.1.2.2.1.5.2", 1000000000}   # ifSpeed.2
]

# Convert to structured table
{:ok, table} = SnmpMgr.Table.to_table(pairs, [1, 3, 6, 1, 2, 1, 2, 2])

# Result structure:
# %{
#   1 => %{2 => "eth0", 3 => 6, 5 => 1000000000},    # Row 1
#   2 => %{2 => "eth1", 3 => 6, 5 => 1000000000}     # Row 2
# }

# Access specific values
interface_name = table[1][2]  # "eth0"
interface_type = table[1][3]  # 6
interface_speed = table[1][5] # 1000000000
```

### `to_records/3`

Converts table data to a list of records with named fields.

```elixir
to_records(table, column_map, opts \\ [])
```

**Parameters:**
- `table` - Structured table from `to_table/2`
- `column_map` - Map of column numbers to field names
- `opts` - Options for record processing

**Examples:**

```elixir
# Define column mapping for interface table
column_map = %{
  2 => :description,
  3 => :type,
  5 => :speed,
  8 => :admin_status,
  9 => :oper_status
}

# Convert to records
{:ok, interfaces} = SnmpMgr.Table.to_records(table, column_map)

# Result:
# [
#   %{index: 1, description: "eth0", type: 6, speed: 1000000000, admin_status: 1, oper_status: 1},
#   %{index: 2, description: "eth1", type: 6, speed: 1000000000, admin_status: 1, oper_status: 1}
# ]

# Access records
Enum.each(interfaces, fn interface ->
  IO.puts("Interface #{interface.index}: #{interface.description}")
  IO.puts("  Speed: #{interface.speed} bps")
  IO.puts("  Status: #{format_status(interface.oper_status)}")
end)
```

### `get_column/3`

Extracts a specific column from a table.

```elixir
get_column(table, column_number, opts \\ [])
```

**Examples:**

```elixir
# Get all interface descriptions
{:ok, descriptions} = SnmpMgr.Table.get_column(table, 2)
# %{1 => "eth0", 2 => "eth1"}

# Get as list with indexes
{:ok, desc_list} = SnmpMgr.Table.get_column(table, 2, format: :list)
# [{1, "eth0"}, {2, "eth1"}]

# Get just values
{:ok, values} = SnmpMgr.Table.get_column(table, 2, format: :values)
# ["eth0", "eth1"]
```

### `filter_rows/3`

Filters table rows based on criteria.

```elixir
filter_rows(table, column, criteria)
```

**Examples:**

```elixir
# Filter interfaces by type (Ethernet = 6)
{:ok, ethernet_interfaces} = SnmpMgr.Table.filter_rows(table, 3, 6)

# Filter by operational status (up = 1)
{:ok, active_interfaces} = SnmpMgr.Table.filter_rows(table, 9, 1)

# Filter with custom function
{:ok, gigabit_interfaces} = SnmpMgr.Table.filter_rows(table, 5, fn speed ->
  speed >= 1000000000
end)
```

## Advanced Table Operations

### `join_tables/3`

Joins two tables on matching indexes.

```elixir
join_tables(table1, table2, join_type \\ :inner)
```

**Examples:**

```elixir
# Get interface descriptions and statistics separately
{:ok, if_info} = SnmpMgr.walk("device", "ifDescr")
{:ok, if_stats} = SnmpMgr.walk("device", "ifInOctets") 

# Convert to tables
{:ok, info_table} = SnmpMgr.Table.to_table(if_info, [1,3,6,1,2,1,2,2,1,2])
{:ok, stats_table} = SnmpMgr.Table.to_table(if_stats, [1,3,6,1,2,1,2,2,1,10])

# Join tables
{:ok, combined} = SnmpMgr.Table.join_tables(info_table, stats_table)

# Result contains both interface info and statistics
combined[1]  # %{2 => "eth0", 10 => 123456789}  # Description and InOctets
```

### `aggregate_column/3`

Performs aggregation operations on table columns.

```elixir
aggregate_column(table, column, operation)
```

**Examples:**

```elixir
# Sum all input octets
{:ok, total_input} = SnmpMgr.Table.aggregate_column(stats_table, 10, :sum)

# Get average interface speed
{:ok, avg_speed} = SnmpMgr.Table.aggregate_column(table, 5, :avg)

# Find maximum interface index
{:ok, max_index} = SnmpMgr.Table.aggregate_column(table, :index, :max)

# Count operational interfaces
{:ok, oper_count} = SnmpMgr.Table.aggregate_column(table, 9, {:count, 1})
```

### `sort_table/3`

Sorts table rows by column values.

```elixir
sort_table(table, column, direction \\ :asc)
```

**Examples:**

```elixir
# Sort by interface speed (ascending)
{:ok, sorted_by_speed} = SnmpMgr.Table.sort_table(table, 5, :asc)

# Sort by description (descending)
{:ok, sorted_by_desc} = SnmpMgr.Table.sort_table(table, 2, :desc)

# Sort by multiple columns
{:ok, multi_sorted} = SnmpMgr.Table.sort_table(table, [
  {3, :asc},    # Type first
  {5, :desc}    # Then speed descending
])
```

## Complete Table Processing Examples

### Interface Table Analysis

```elixir
defmodule InterfaceAnalyzer do
  def analyze_interfaces(device_ip, community \\ "public") do
    with {:ok, if_data} <- SnmpMgr.walk(device_ip, "ifTable", community: community),
         {:ok, table} <- SnmpMgr.Table.to_table(if_data, [1,3,6,1,2,1,2,2]) do
      
      # Define interface table columns
      column_map = %{
        2 => :description,
        3 => :type,
        5 => :speed,
        8 => :admin_status,
        9 => :oper_status,
        10 => :in_octets,
        16 => :out_octets
      }
      
      # Convert to records
      {:ok, interfaces} = SnmpMgr.Table.to_records(table, column_map)
      
      # Analyze the data
      analysis = %{
        total_interfaces: length(interfaces),
        active_interfaces: count_active_interfaces(interfaces),
        interface_types: group_by_type(interfaces),
        speed_distribution: analyze_speeds(interfaces),
        top_utilization: find_top_utilization(interfaces)
      }
      
      {:ok, analysis}
    end
  end

  defp count_active_interfaces(interfaces) do
    Enum.count(interfaces, fn if -> if.oper_status == 1 end)
  end

  defp group_by_type(interfaces) do
    interfaces
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, ifs} -> {interface_type_name(type), length(ifs)} end)
  end

  defp analyze_speeds(interfaces) do
    speeds = Enum.map(interfaces, & &1.speed)
    
    %{
      min: Enum.min(speeds),
      max: Enum.max(speeds), 
      avg: Enum.sum(speeds) / length(speeds),
      distribution: Enum.frequencies_by(speeds, &speed_category/1)
    }
  end

  defp find_top_utilization(interfaces) do
    interfaces
    |> Enum.map(fn if ->
      total_octets = if.in_octets + if.out_octets
      %{if | utilization: total_octets}
    end)
    |> Enum.sort_by(& &1.utilization, :desc)
    |> Enum.take(5)
  end
end
```

### Routing Table Processing

```elixir
defmodule RoutingTableProcessor do
  def process_routing_table(device_ip, community \\ "public") do
    with {:ok, route_data} <- SnmpMgr.walk(device_ip, "ipRouteTable", community: community),
         {:ok, table} <- SnmpMgr.Table.to_table(route_data, [1,3,6,1,2,1,4,21]) do
      
      # Define routing table columns
      column_map = %{
        1 => :destination,
        2 => :if_index,
        3 => :metric,
        7 => :next_hop,
        8 => :type,
        9 => :protocol
      }
      
      {:ok, routes} = SnmpMgr.Table.to_records(table, column_map)
      
      # Process and categorize routes
      processed_routes = Enum.map(routes, fn route ->
        %{route |
          destination: format_ip_address(route.destination),
          next_hop: format_ip_address(route.next_hop),
          type_name: route_type_name(route.type),
          protocol_name: route_protocol_name(route.protocol)
        }
      end)
      
      {:ok, processed_routes}
    end
  end

  defp format_ip_address(ip_tuple) when is_tuple(ip_tuple) do
    ip_tuple |> Tuple.to_list() |> Enum.join(".")
  end
  defp format_ip_address(ip_string), do: ip_string

  defp route_type_name(1), do: "other"
  defp route_type_name(2), do: "direct"
  defp route_type_name(3), do: "indirect"
  defp route_type_name(_), do: "unknown"

  defp route_protocol_name(1), do: "other"
  defp route_protocol_name(2), do: "local"
  defp route_protocol_name(8), do: "rip"
  defp route_protocol_name(13), do: "ospf"
  defp route_protocol_name(_), do: "unknown"
end
```

### ARP Table Analysis

```elixir
defmodule ARPTableAnalyzer do
  def analyze_arp_table(device_ip, community \\ "public") do
    with {:ok, arp_data} <- SnmpMgr.walk(device_ip, "ipNetToMediaTable", community: community),
         {:ok, table} <- SnmpMgr.Table.to_table(arp_data, [1,3,6,1,2,1,4,22]) do
      
      column_map = %{
        1 => :if_index,
        2 => :physical_address,
        3 => :net_address,
        4 => :type
      }
      
      {:ok, arp_entries} = SnmpMgr.Table.to_records(table, column_map)
      
      # Process ARP entries
      processed_entries = Enum.map(arp_entries, fn entry ->
        %{entry |
          physical_address: format_mac_address(entry.physical_address),
          net_address: format_ip_address(entry.net_address),
          type_name: arp_type_name(entry.type)
        }
      end)
      
      # Analyze the ARP table
      analysis = %{
        total_entries: length(processed_entries),
        entries_by_interface: group_by_interface(processed_entries),
        duplicate_ips: find_duplicate_ips(processed_entries),
        duplicate_macs: find_duplicate_macs(processed_entries)
      }
      
      {:ok, %{entries: processed_entries, analysis: analysis}}
    end
  end

  defp format_mac_address(mac_binary) when is_binary(mac_binary) do
    mac_binary
    |> :binary.bin_to_list()
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> Enum.join(":")
    |> String.upcase()
  end

  defp group_by_interface(entries) do
    Enum.group_by(entries, & &1.if_index)
    |> Map.new(fn {if_index, entries} -> {if_index, length(entries)} end)
  end

  defp find_duplicate_ips(entries) do
    entries
    |> Enum.group_by(& &1.net_address)
    |> Enum.filter(fn {_ip, entries} -> length(entries) > 1 end)
    |> Enum.map(fn {ip, entries} -> {ip, length(entries)} end)
  end

  defp find_duplicate_macs(entries) do
    entries
    |> Enum.group_by(& &1.physical_address)
    |> Enum.filter(fn {_mac, entries} -> length(entries) > 1 end)
    |> Enum.map(fn {mac, entries} -> {mac, length(entries)} end)
  end
end
```

## Multi-Device Table Operations

### Comparative Table Analysis

```elixir
defmodule MultiDeviceTableAnalysis do
  def compare_interface_tables(devices) do
    # Collect interface tables from all devices
    requests = Enum.map(devices, fn device ->
      {device.ip, "ifTable", [community: device.community]}
    end)
    
    results = SnmpMgr.Multi.walk_multi(requests)
    
    # Process each device's table
    device_tables = Enum.zip(devices, results)
    |> Enum.map(fn {device, result} ->
      case result do
        {:ok, table_data} ->
          {:ok, table} = SnmpMgr.Table.to_table(table_data, [1,3,6,1,2,1,2,2])
          {device.ip, table}
        {:error, reason} ->
          {device.ip, {:error, reason}}
      end
    end)
    
    # Compare tables
    comparison = %{
      device_count: length(devices),
      successful_devices: count_successful(device_tables),
      interface_summary: summarize_interfaces(device_tables),
      speed_comparison: compare_speeds(device_tables),
      status_comparison: compare_status(device_tables)
    }
    
    {:ok, comparison}
  end

  defp count_successful(device_tables) do
    Enum.count(device_tables, fn {_device, result} ->
      not match?({:error, _}, result)
    end)
  end

  defp summarize_interfaces(device_tables) do
    device_tables
    |> Enum.filter(fn {_device, result} -> not match?({:error, _}, result) end)
    |> Enum.map(fn {device, table} ->
      interface_count = map_size(table)
      active_count = count_active_interfaces_in_table(table)
      
      {device, %{total: interface_count, active: active_count}}
    end)
    |> Map.new()
  end
end
```

### Table Export and Reporting

```elixir
defmodule TableReporter do
  def export_table_to_csv(table, column_map, filename) do
    # Convert table to records
    {:ok, records} = SnmpMgr.Table.to_records(table, column_map)
    
    # Create CSV content
    headers = [:index | Map.values(column_map)]
    header_line = Enum.join(headers, ",")
    
    data_lines = Enum.map(records, fn record ->
      values = Enum.map(headers, fn header -> Map.get(record, header, "") end)
      Enum.join(values, ",")
    end)
    
    csv_content = [header_line | data_lines] |> Enum.join("\n")
    
    # Write to file
    File.write(filename, csv_content)
  end

  def generate_table_report(table, column_map, title) do
    {:ok, records} = SnmpMgr.Table.to_records(table, column_map)
    
    report = """
    #{title}
    =====================================
    
    Total Records: #{length(records)}
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}
    
    Records:
    #{format_records_for_report(records)}
    """
    
    report
  end

  defp format_records_for_report(records) do
    Enum.map(records, fn record ->
      "Index #{record.index}: #{inspect(record)}"
    end)
    |> Enum.join("\n")
  end
end
```

## Integration with Other Modules

### Using with Multi Operations

```elixir
# Collect tables from multiple devices
devices = ["192.168.1.1", "192.168.1.2", "192.168.1.3"]

table_requests = Enum.map(devices, fn ip ->
  {ip, "ifTable", [community: "public"]}
end)

walk_results = SnmpMgr.Multi.walk_multi(table_requests)

# Process all tables
processed_tables = Enum.zip(devices, walk_results)
|> Enum.map(fn {device_ip, walk_result} ->
  case walk_result do
    {:ok, table_data} ->
      {:ok, table} = SnmpMgr.Table.to_table(table_data, [1,3,6,1,2,1,2,2])
      
      column_map = %{2 => :description, 3 => :type, 5 => :speed}
      {:ok, records} = SnmpMgr.Table.to_records(table, column_map)
      
      {device_ip, records}
    {:error, reason} ->
      {device_ip, {:error, reason}}
  end
end)
```

### Using with Types Module

```elixir
# Process table values with proper type handling
defmodule TypedTableProcessor do
  def process_typed_table(table_data, table_oid) do
    {:ok, table} = SnmpMgr.Table.to_table(table_data, table_oid)
    
    # Process each cell with appropriate type handling
    typed_table = Map.new(table, fn {row_index, row} ->
      typed_row = Map.new(row, fn {col_index, value} ->
        typed_value = SnmpMgr.Types.decode_value(value)
        {col_index, typed_value}
      end)
      {row_index, typed_row}
    end)
    
    {:ok, typed_table}
  end
end
```

## Best Practices

### 1. Always Specify Table OID

```elixir
# Correct - specify the table OID
{:ok, table} = SnmpMgr.Table.to_table(walk_data, [1,3,6,1,2,1,2,2])

# Avoid - letting the function guess the structure
{:ok, table} = SnmpMgr.Table.to_table(walk_data, :auto)
```

### 2. Use Column Maps for Clarity

```elixir
# Preferred - clear field names
column_map = %{
  2 => :description,
  3 => :type,
  5 => :speed,
  8 => :admin_status,
  9 => :oper_status
}

{:ok, interfaces} = SnmpMgr.Table.to_records(table, column_map)

# Avoid - working with raw column numbers
speed = table[1][5]  # What is column 5?
```

### 3. Handle Missing Data Gracefully

```elixir
defmodule SafeTableProcessor do
  def safe_get_column(table, column, default \\ nil) do
    case SnmpMgr.Table.get_column(table, column) do
      {:ok, column_data} -> column_data
      {:error, :column_not_found} -> %{}
      {:error, _} -> %{}
    end
  end

  def safe_get_cell(table, row, column, default \\ nil) do
    table
    |> Map.get(row, %{})
    |> Map.get(column, default)
  end
end
```

### 4. Validate Table Structure

```elixir
defmodule TableValidator do
  def validate_interface_table(table) do
    required_columns = [2, 3, 5, 8, 9]  # Description, Type, Speed, AdminStatus, OperStatus
    
    # Check if all required columns exist
    missing_columns = Enum.filter(required_columns, fn col ->
      not has_column?(table, col)
    end)
    
    case missing_columns do
      [] -> {:ok, table}
      missing -> {:error, {:missing_columns, missing}}
    end
  end

  defp has_column?(table, column) do
    table
    |> Map.values()
    |> Enum.any?(fn row -> Map.has_key?(row, column) end)
  end
end
```