# SNMPMgr.Types Module Guide

The `SNMPMgr.Types` module handles SNMP data type encoding and decoding, providing automatic type inference and explicit type specification for SNMP values.

## Overview

SNMP defines various data types for different kinds of values. The Types module provides:
- **Automatic type inference**: Detects appropriate SNMP types from Elixir values
- **Explicit type specification**: Allows forcing specific SNMP types
- **Value encoding**: Converts Elixir values to SNMP format
- **Value decoding**: Converts SNMP values to Elixir format

## Supported SNMP Types

### Basic Types

| SNMP Type | Elixir Type | Description | Example |
|-----------|-------------|-------------|---------|
| `:integer` | Integer | 32-bit signed integer | `42` |
| `:string` | String | Octet string | `"Hello World"` |
| `:oid` | List/String | Object Identifier | `[1,3,6,1,2,1,1,1]` or `"1.3.6.1.2.1.1.1"` |
| `:null` | Atom | Null value | `:null` |
| `:ipAddress` | Tuple/String | IP address | `{192,168,1,1}` or `"192.168.1.1"` |
| `:counter` | Integer | 32-bit counter | `123456` |
| `:gauge` | Integer | 32-bit gauge | `75` |
| `:timeticks` | Integer | Time in hundredths of seconds | `12345` |
| `:opaque` | Binary | Arbitrary binary data | `<<1,2,3,4>>` |

### Advanced Types (SNMP v2c)

| SNMP Type | Elixir Type | Description | Example |
|-----------|-------------|-------------|---------|
| `:counter64` | Integer | 64-bit counter | `9876543210` |
| `:unsigned32` | Integer | 32-bit unsigned integer | `4294967295` |

## Value Encoding

### `encode_value/2`

Encodes Elixir values for SNMP transmission.

```elixir
encode_value(value, opts \\ [])
```

#### Automatic Type Inference

```elixir
# String values
{:ok, {:string, "Hello"}} = SNMPMgr.Types.encode_value("Hello")

# Integer values  
{:ok, {:integer, 42}} = SNMPMgr.Types.encode_value(42)

# Large integers become counters
{:ok, {:counter, 123456789}} = SNMPMgr.Types.encode_value(123456789)

# OID as list
{:ok, {:oid, [1,3,6,1,2,1,1,1]}} = SNMPMgr.Types.encode_value([1,3,6,1,2,1,1,1])

# OID as string
{:ok, {:oid, [1,3,6,1,2,1,1,1]}} = SNMPMgr.Types.encode_value("1.3.6.1.2.1.1.1")

# Null value
{:ok, {:null, :null}} = SNMPMgr.Types.encode_value(:null)

# Binary data
{:ok, {:opaque, <<1,2,3>>}} = SNMPMgr.Types.encode_value(<<1,2,3>>)
```

#### Explicit Type Specification

```elixir
# Force string type
{:ok, {:string, "42"}} = SNMPMgr.Types.encode_value("42", type: :string)

# Force integer type
{:ok, {:integer, 42}} = SNMPMgr.Types.encode_value(42, type: :integer)

# Force IP address type
{:ok, {:ipAddress, {192,168,1,1}}} = SNMPMgr.Types.encode_value("192.168.1.1", type: :ipAddress)

# Force gauge type
{:ok, {:gauge, 75}} = SNMPMgr.Types.encode_value(75, type: :gauge)

# Force counter type
{:ok, {:counter, 1000}} = SNMPMgr.Types.encode_value(1000, type: :counter)

# Force timeticks type
{:ok, {:timeticks, 12345}} = SNMPMgr.Types.encode_value(12345, type: :timeticks)
```

## Value Decoding

### `decode_value/1`

Decodes SNMP values to Elixir format.

```elixir
decode_value(snmp_value)
```

#### Basic Decoding Examples

```elixir
# String decoding
"Hello" = SNMPMgr.Types.decode_value({:string, "Hello"})

# Integer decoding
42 = SNMPMgr.Types.decode_value({:integer, 42})

# OID decoding (returns string format)
"1.3.6.1.2.1.1.1" = SNMPMgr.Types.decode_value({:oid, [1,3,6,1,2,1,1,1]})

# IP address decoding (returns string format)
"192.168.1.1" = SNMPMgr.Types.decode_value({:ipAddress, {192,168,1,1}})

# Counter decoding
123456 = SNMPMgr.Types.decode_value({:counter, 123456})

# Gauge decoding
75 = SNMPMgr.Types.decode_value({:gauge, 75})

# Timeticks decoding (returns formatted string)
uptime_str = SNMPMgr.Types.decode_value({:timeticks, 12345})
# "2 minutes, 3.45 seconds"

# Null decoding
:null = SNMPMgr.Types.decode_value({:null, :null})

# Opaque decoding
<<1,2,3>> = SNMPMgr.Types.decode_value({:opaque, <<1,2,3>>})
```

## Working with Specific Types

### IP Addresses

```elixir
# Encoding IP addresses
{:ok, {:ipAddress, {192,168,1,1}}} = SNMPMgr.Types.encode_value("192.168.1.1", type: :ipAddress)
{:ok, {:ipAddress, {10,0,0,1}}} = SNMPMgr.Types.encode_value({10,0,0,1}, type: :ipAddress)

# Decoding IP addresses
"192.168.1.1" = SNMPMgr.Types.decode_value({:ipAddress, {192,168,1,1}})

# Using in SNMP operations
{:ok, _} = SNMPMgr.set("device", "ipAdEntAddr.1", "192.168.1.100", 
                      type: :ipAddress, community: "private")
```

### Object Identifiers (OIDs)

```elixir
# Various OID formats
{:ok, {:oid, [1,3,6,1,2,1,1,1]}} = SNMPMgr.Types.encode_value("1.3.6.1.2.1.1.1")
{:ok, {:oid, [1,3,6,1,2,1,1,1]}} = SNMPMgr.Types.encode_value([1,3,6,1,2,1,1,1])

# Decoding OIDs
"1.3.6.1.2.1.1.1" = SNMPMgr.Types.decode_value({:oid, [1,3,6,1,2,1,1,1]})

# Using in SNMP operations  
{:ok, _} = SNMPMgr.set("device", "sysObjectID.0", "1.3.6.1.4.1.9.1.1", 
                      type: :oid, community: "private")
```

### Counters and Gauges

```elixir
# Counters (monotonically increasing)
{:ok, {:counter, 1000000}} = SNMPMgr.Types.encode_value(1000000, type: :counter)

# Gauges (can increase or decrease)
{:ok, {:gauge, 75}} = SNMPMgr.Types.encode_value(75, type: :gauge)

# 64-bit counters (SNMP v2c)
{:ok, {:counter64, 9876543210}} = SNMPMgr.Types.encode_value(9876543210, type: :counter64)

# Usage example
{:ok, _} = SNMPMgr.set("device", "customCounter.0", 1000000, 
                      type: :counter, community: "private")
```

### Timeticks

```elixir
# Timeticks represent time in hundredths of seconds
{:ok, {:timeticks, 12345}} = SNMPMgr.Types.encode_value(12345, type: :timeticks)

# Decoding provides formatted time string
uptime = SNMPMgr.Types.decode_value({:timeticks, 12345})
# "2 minutes, 3.45 seconds"

# Working with system uptime
{:ok, uptime_ticks} = SNMPMgr.get("device", "sysUpTime.0")
formatted_uptime = SNMPMgr.Types.decode_value({:timeticks, uptime_ticks})
```

## Type Detection and Validation

### `detect_type/1`

Automatically detects the appropriate SNMP type for a value.

```elixir
:string = SNMPMgr.Types.detect_type("Hello")
:integer = SNMPMgr.Types.detect_type(42)
:oid = SNMPMgr.Types.detect_type([1,3,6,1,2,1,1,1])
:oid = SNMPMgr.Types.detect_type("1.3.6.1.2.1.1.1")
:null = SNMPMgr.Types.detect_type(:null)
:opaque = SNMPMgr.Types.detect_type(<<1,2,3>>)
```

### `validate_type/2`

Validates that a value is compatible with a specific SNMP type.

```elixir
:ok = SNMPMgr.Types.validate_type("Hello", :string)
:ok = SNMPMgr.Types.validate_type(42, :integer)
{:error, :invalid_type} = SNMPMgr.Types.validate_type("Hello", :integer)
{:error, :invalid_format} = SNMPMgr.Types.validate_type("invalid.ip", :ipAddress)
```

## Advanced Features

### Custom Type Handling

```elixir
defmodule CustomTypeHandler do
  def encode_mac_address(mac_string) do
    # Convert MAC address string to SNMP octet string
    mac_bytes = mac_string
    |> String.split(":")
    |> Enum.map(&String.to_integer(&1, 16))
    |> :erlang.list_to_binary()
    
    SNMPMgr.Types.encode_value(mac_bytes, type: :string)
  end

  def decode_mac_address({:string, mac_bytes}) do
    # Convert SNMP octet string back to MAC address
    mac_bytes
    |> :erlang.binary_to_list()
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.map(&String.pad_leading(&1, 2, "0"))
    |> Enum.join(":")
    |> String.upcase()
  end
end

# Usage
{:ok, encoded} = CustomTypeHandler.encode_mac_address("aa:bb:cc:dd:ee:ff")
{:ok, _} = SNMPMgr.set("device", "ifPhysAddress.1", encoded, community: "private")

{:ok, raw_mac} = SNMPMgr.get("device", "ifPhysAddress.1", community: "public")
mac_address = CustomTypeHandler.decode_mac_address(raw_mac)
```

### Bulk Type Processing

```elixir
defmodule BulkTypeProcessor do
  def process_interface_data(walk_results) do
    Enum.map(walk_results, fn {oid, raw_value} ->
      processed_value = case detect_interface_type(oid) do
        :counter -> format_counter(raw_value)
        :status -> format_status(raw_value)
        :speed -> format_speed(raw_value)
        :description -> format_description(raw_value)
        _ -> SNMPMgr.Types.decode_value(raw_value)
      end
      
      {oid, processed_value}
    end)
  end

  defp detect_interface_type(oid) do
    cond do
      String.contains?(oid, "ifInOctets") or String.contains?(oid, "ifOutOctets") -> :counter
      String.contains?(oid, "ifAdminStatus") or String.contains?(oid, "ifOperStatus") -> :status
      String.contains?(oid, "ifSpeed") -> :speed
      String.contains?(oid, "ifDescr") -> :description
      true -> :unknown
    end
  end

  defp format_counter({:counter, value}), do: "#{value} bytes"
  defp format_status({:integer, 1}), do: "up"
  defp format_status({:integer, 2}), do: "down"
  defp format_status({:integer, 3}), do: "testing"
  defp format_speed({:gauge, value}), do: "#{value} bps"
  defp format_description({:string, desc}), do: String.trim(desc)
end
```

## Integration Examples

### SET Operations with Type Validation

```elixir
defmodule SafeSNMPSet do
  def safe_set(device, oid, value, type, opts \\ []) do
    case SNMPMgr.Types.validate_type(value, type) do
      :ok ->
        SNMPMgr.set(device, oid, value, [type: type] ++ opts)
      {:error, reason} ->
        {:error, {:invalid_type, reason}}
    end
  end

  def set_system_contact(device, contact, opts \\ []) do
    safe_set(device, "sysContact.0", contact, :string, opts)
  end

  def set_system_location(device, location, opts \\ []) do
    safe_set(device, "sysLocation.0", location, :string, opts)
  end

  def set_ip_address(device, oid, ip_address, opts \\ []) do
    safe_set(device, oid, ip_address, :ipAddress, opts)
  end
end
```

### Data Collection with Type Processing

```elixir
defmodule NetworkStatsCollector do
  def collect_interface_stats(device_ip) do
    with {:ok, descriptions} <- SNMPMgr.walk(device_ip, "ifDescr"),
         {:ok, in_octets} <- SNMPMgr.walk(device_ip, "ifInOctets"),
         {:ok, out_octets} <- SNMPMgr.walk(device_ip, "ifOutOctets"),
         {:ok, speeds} <- SNMPMgr.walk(device_ip, "ifSpeed") do
      
      processed_stats = process_interface_stats(descriptions, in_octets, out_octets, speeds)
      {:ok, processed_stats}
    end
  end

  defp process_interface_stats(descriptions, in_octets, out_octets, speeds) do
    # Extract interface indexes
    indexes = extract_indexes(descriptions)
    
    Enum.map(indexes, fn index ->
      %{
        index: index,
        description: decode_and_clean(find_by_index(descriptions, index)),
        in_octets: decode_counter(find_by_index(in_octets, index)),
        out_octets: decode_counter(find_by_index(out_octets, index)),
        speed: decode_speed(find_by_index(speeds, index))
      }
    end)
  end

  defp decode_and_clean({:string, value}), do: String.trim(value)
  defp decode_counter({:counter, value}), do: value
  defp decode_speed({:gauge, value}), do: value
end
```

### Custom Type Registry

```elixir
defmodule CompanyTypes do
  @type_mappings %{
    "deviceHealth" => :gauge,
    "securityLevel" => :integer,
    "lastUpdate" => :timeticks,
    "adminContact" => :string,
    "managementIP" => :ipAddress
  }

  def encode_company_value(field_name, value) do
    case Map.get(@type_mappings, field_name) do
      nil -> 
        {:error, {:unknown_field, field_name}}
      type -> 
        SNMPMgr.Types.encode_value(value, type: type)
    end
  end

  def set_company_field(device, field_name, value, opts \\ []) do
    case encode_company_value(field_name, value) do
      {:ok, encoded_value} ->
        oid = build_company_oid(field_name)
        SNMPMgr.set(device, oid, encoded_value, opts)
      error ->
        error
    end
  end

  defp build_company_oid(field_name) do
    # Map field names to company OIDs
    case field_name do
      "deviceHealth" -> "1.3.6.1.4.1.12345.1.1.0"
      "securityLevel" -> "1.3.6.1.4.1.12345.1.2.0"
      "lastUpdate" -> "1.3.6.1.4.1.12345.1.3.0"
      "adminContact" -> "1.3.6.1.4.1.12345.1.4.0"
      "managementIP" -> "1.3.6.1.4.1.12345.1.5.0"
    end
  end
end

# Usage
{:ok, _} = CompanyTypes.set_company_field("192.168.1.1", "deviceHealth", 95, 
                                         community: "private")
```

## Error Handling

### Type Validation Errors

```elixir
case SNMPMgr.Types.encode_value("invalid.ip.address", type: :ipAddress) do
  {:ok, encoded} -> 
    use_encoded_value(encoded)
  {:error, :invalid_ip_format} -> 
    Logger.error("Invalid IP address format")
  {:error, reason} -> 
    Logger.error("Encoding failed: #{inspect(reason)}")
end
```

### Decoding Errors

```elixir
case SNMPMgr.Types.decode_value({:unknown_type, value}) do
  decoded_value when is_binary(decoded_value) or is_integer(decoded_value) ->
    decoded_value
  {:error, reason} ->
    Logger.warn("Could not decode value: #{inspect(reason)}")
    value  # Return raw value as fallback
end
```

## Best Practices

### 1. Use Explicit Types for SET Operations

```elixir
# Preferred - explicit and clear
{:ok, _} = SNMPMgr.set("device", "sysContact.0", "admin@company.com", 
                      type: :string, community: "private")

# Avoid - relies on type inference
{:ok, _} = SNMPMgr.set("device", "sysContact.0", "admin@company.com", 
                      community: "private")
```

### 2. Validate Types Before Setting

```elixir
def safe_snmp_set(device, oid, value, type, opts) do
  with :ok <- SNMPMgr.Types.validate_type(value, type),
       {:ok, result} <- SNMPMgr.set(device, oid, value, [type: type] ++ opts) do
    {:ok, result}
  else
    {:error, :invalid_type} -> {:error, {:validation_failed, value, type}}
    error -> error
  end
end
```

### 3. Handle Different Type Variants

```elixir
def decode_snmp_value(snmp_value) do
  case snmp_value do
    {:string, value} -> String.trim(value)
    {:integer, value} -> value
    {:counter, value} -> value
    {:gauge, value} -> value
    {:timeticks, value} -> format_uptime(value)
    {:ipAddress, ip_tuple} -> format_ip_address(ip_tuple)
    {:oid, oid_list} -> Enum.join(oid_list, ".")
    {:null, :null} -> nil
    other -> other  # Return unknown types as-is
  end
end
```

### 4. Create Type-Specific Utilities

```elixir
defmodule SNMPTypeUtils do
  def format_bytes(byte_count) when is_integer(byte_count) do
    cond do
      byte_count >= 1_073_741_824 -> "#{Float.round(byte_count / 1_073_741_824, 2)} GB"
      byte_count >= 1_048_576 -> "#{Float.round(byte_count / 1_048_576, 2)} MB"
      byte_count >= 1024 -> "#{Float.round(byte_count / 1024, 2)} KB"
      true -> "#{byte_count} B"
    end
  end

  def format_uptime(timeticks) when is_integer(timeticks) do
    seconds = div(timeticks, 100)
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)
    
    "#{days}d #{hours}h #{minutes}m #{secs}s"
  end

  def parse_interface_status(status_int) do
    case status_int do
      1 -> :up
      2 -> :down
      3 -> :testing
      4 -> :unknown
      5 -> :dormant
      6 -> :not_present
      7 -> :lower_layer_down
      _ -> :undefined
    end
  end
end
```