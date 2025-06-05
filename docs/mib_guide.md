# SNMPMgr.MIB Module Guide

The `SNMPMgr.MIB` module provides MIB (Management Information Base) compilation and symbolic name resolution. It includes built-in support for standard MIB objects and allows loading custom MIB files.

## Overview

The MIB module serves two main purposes:
1. **Built-in MIB registry**: Provides immediate access to standard SNMP objects using symbolic names
2. **MIB compilation**: Compiles custom MIB files using SNMPMgr's built-in compiler (SnmpLib.MIB)

## Starting the MIB Service

```elixir
# Start with default configuration
{:ok, pid} = SNMPMgr.MIB.start_link()

# Start with custom MIB paths
{:ok, pid} = SNMPMgr.MIB.start_link([
  mib_paths: ["/opt/mibs", "/usr/local/share/mibs"]
])
```

## Built-in MIB Objects

The module includes a comprehensive registry of standard MIB objects:

### System Group (1.3.6.1.2.1.1)

```elixir
# These symbolic names are built-in
{:ok, desc} = SNMPMgr.get("device", "sysDescr.0")
{:ok, oid} = SNMPMgr.get("device", "sysObjectID.0")
{:ok, uptime} = SNMPMgr.get("device", "sysUpTime.0")
{:ok, contact} = SNMPMgr.get("device", "sysContact.0")
{:ok, name} = SNMPMgr.get("device", "sysName.0")
{:ok, location} = SNMPMgr.get("device", "sysLocation.0")
{:ok, services} = SNMPMgr.get("device", "sysServices.0")
```

### Interfaces Group (1.3.6.1.2.1.2)

```elixir
# Interface information
{:ok, if_count} = SNMPMgr.get("device", "ifNumber.0")
{:ok, interfaces} = SNMPMgr.walk("device", "ifDescr")
{:ok, types} = SNMPMgr.walk("device", "ifType")
{:ok, speeds} = SNMPMgr.walk("device", "ifSpeed")
{:ok, admin_status} = SNMPMgr.walk("device", "ifAdminStatus")
{:ok, oper_status} = SNMPMgr.walk("device", "ifOperStatus")

# Interface statistics
{:ok, in_octets} = SNMPMgr.walk("device", "ifInOctets")
{:ok, out_octets} = SNMPMgr.walk("device", "ifOutOctets")
{:ok, in_packets} = SNMPMgr.walk("device", "ifInUcastPkts")
{:ok, out_packets} = SNMPMgr.walk("device", "ifOutUcastPkts")
```

### IP Group (1.3.6.1.2.1.4)

```elixir
# IP statistics and configuration
{:ok, forwarding} = SNMPMgr.get("device", "ipForwarding.0")
{:ok, ttl} = SNMPMgr.get("device", "ipDefaultTTL.0")
{:ok, in_receives} = SNMPMgr.get("device", "ipInReceives.0")
{:ok, addr_table} = SNMPMgr.walk("device", "ipAdEntAddr")
{:ok, route_table} = SNMPMgr.walk("device", "ipRouteTable")
```

### ICMP Group (1.3.6.1.2.1.5)

```elixir
# ICMP statistics
{:ok, in_msgs} = SNMPMgr.get("device", "icmpInMsgs.0")
{:ok, out_msgs} = SNMPMgr.get("device", "icmpOutMsgs.0")
{:ok, in_errors} = SNMPMgr.get("device", "icmpInErrors.0")
```

### TCP Group (1.3.6.1.2.1.6)

```elixir
# TCP statistics
{:ok, active_opens} = SNMPMgr.get("device", "tcpActiveOpens.0")
{:ok, passive_opens} = SNMPMgr.get("device", "tcpPassiveOpens.0")
{:ok, curr_estab} = SNMPMgr.get("device", "tcpCurrEstab.0")
{:ok, conn_table} = SNMPMgr.walk("device", "tcpConnTable")
```

### UDP Group (1.3.6.1.2.1.7)

```elixir
# UDP statistics
{:ok, in_datagrams} = SNMPMgr.get("device", "udpInDatagrams.0")
{:ok, out_datagrams} = SNMPMgr.get("device", "udpOutDatagrams.0")
{:ok, no_ports} = SNMPMgr.get("device", "udpNoPorts.0")
```

## OID Resolution Functions

### `resolve_oid/1`

Converts symbolic names to numeric OIDs.

```elixir
# Convert symbolic name to OID
{:ok, oid} = SNMPMgr.MIB.resolve_oid("sysDescr")
# {:ok, [1, 3, 6, 1, 2, 1, 1, 1]}

{:ok, oid} = SNMPMgr.MIB.resolve_oid("ifDescr")
# {:ok, [1, 3, 6, 1, 2, 1, 2, 2, 1, 2]}

# Already numeric OIDs pass through unchanged
{:ok, oid} = SNMPMgr.MIB.resolve_oid("1.3.6.1.2.1.1.1.0")
# {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}

# Handle compound names
{:ok, oid} = SNMPMgr.MIB.resolve_oid("sysDescr.0")
# {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}
```

### `resolve_name/1`

Converts numeric OIDs to symbolic names (when available).

```elixir
# Convert OID to symbolic name
{:ok, name} = SNMPMgr.MIB.resolve_name([1, 3, 6, 1, 2, 1, 1, 1])
# {:ok, "sysDescr"}

{:ok, name} = SNMPMgr.MIB.resolve_name("1.3.6.1.2.1.2.2.1.2")
# {:ok, "ifDescr"}

# Unknown OIDs return the numeric form
{:ok, name} = SNMPMgr.MIB.resolve_name([1, 3, 6, 1, 4, 1, 9999])
# {:ok, "1.3.6.1.4.1.9999"}
```

## Custom MIB Loading

### `load_mib/1`

Loads and compiles a MIB file using SNMPMgr's built-in MIB compiler.

```elixir
# Load a custom MIB file
{:ok, objects} = SNMPMgr.MIB.load_mib("CISCO-SYSTEM-MIB")

# Load vendor-specific MIB
{:ok, objects} = SNMPMgr.MIB.load_mib("/path/to/CUSTOM-MIB.mib")

# Handle compilation errors
case SNMPMgr.MIB.load_mib("INVALID-MIB") do
  {:ok, objects} -> 
    Logger.info("Loaded #{length(objects)} MIB objects")
  {:error, reason} -> 
    Logger.error("Failed to load MIB: #{inspect(reason)}")
end
```

### `load_mib_directory/1`

Loads all MIB files from a directory.

```elixir
# Load all MIBs from a directory
{:ok, results} = SNMPMgr.MIB.load_mib_directory("/opt/custom_mibs")

# Process results
Enum.each(results, fn
  {:ok, mib_name, objects} -> 
    Logger.info("Loaded #{mib_name} with #{length(objects)} objects")
  {:error, mib_name, reason} -> 
    Logger.error("Failed to load #{mib_name}: #{inspect(reason)}")
end)
```

## MIB Management

### `list_loaded_mibs/0`

Lists all currently loaded MIB objects.

```elixir
mibs = SNMPMgr.MIB.list_loaded_mibs()
IO.puts("Loaded MIB objects: #{length(mibs)}")

# Find specific objects
system_objects = Enum.filter(mibs, fn {name, _oid} ->
  String.starts_with?(name, "sys")
end)
```

### `get_mib_info/1`

Retrieves information about a specific MIB object.

```elixir
{:ok, info} = SNMPMgr.MIB.get_mib_info("sysDescr")
# %{
#   name: "sysDescr",
#   oid: [1, 3, 6, 1, 2, 1, 1, 1],
#   type: :string,
#   access: :read_only,
#   description: "A textual description of the entity"
# }
```

### `search_mib/1`

Searches for MIB objects by partial name.

```elixir
# Find all interface-related objects
if_objects = SNMPMgr.MIB.search_mib("if")
# Returns list of matching objects

# Find all TCP objects
tcp_objects = SNMPMgr.MIB.search_mib("tcp")
```

## Advanced Features

### MIB Path Management

```elixir
# Add MIB search paths
SNMPMgr.MIB.add_mib_path("/opt/vendor_mibs")
SNMPMgr.MIB.add_mib_path("/usr/local/share/snmp/mibs")

# Get current search paths
paths = SNMPMgr.MIB.get_mib_paths()

# Set search paths
SNMPMgr.MIB.set_mib_paths([
  "/etc/snmp/mibs",
  "/var/lib/mibs",
  "./project_mibs"
])
```

### MIB Compilation Options

```elixir
# Load MIB with specific options
{:ok, objects} = SNMPMgr.MIB.load_mib("CUSTOM-MIB", [
  include_paths: ["/opt/dependencies"],
  output_dir: "/tmp/compiled_mibs",
  warnings_as_errors: false
])
```

### Custom Object Registration

```elixir
# Register custom objects manually
SNMPMgr.MIB.register_object("customSysInfo", [1, 3, 6, 1, 4, 1, 9999, 1, 1])
SNMPMgr.MIB.register_object("customIfStats", [1, 3, 6, 1, 4, 1, 9999, 2, 1])

# Now use them in SNMP operations
{:ok, value} = SNMPMgr.get("device", "customSysInfo.0")
```

## Integration Examples

### Device Discovery with MIB Names

```elixir
defmodule DeviceDiscovery do
  def discover_device(ip) do
    community = "public"
    timeout = 3000

    with {:ok, desc} <- SNMPMgr.get(ip, "sysDescr.0", 
                                   community: community, timeout: timeout),
         {:ok, name} <- SNMPMgr.get(ip, "sysName.0", 
                                   community: community, timeout: timeout),
         {:ok, location} <- SNMPMgr.get(ip, "sysLocation.0", 
                                       community: community, timeout: timeout) do
      {:ok, %{
        ip: ip,
        description: desc,
        name: name,
        location: location,
        type: classify_device(desc)
      }}
    else
      {:error, reason} -> {:error, {ip, reason}}
    end
  end

  defp classify_device(description) do
    cond do
      String.contains?(description, "Cisco") -> :cisco
      String.contains?(description, "Linux") -> :linux
      String.contains?(description, "Windows") -> :windows
      true -> :unknown
    end
  end
end
```

### Interface Monitoring

```elixir
defmodule InterfaceMonitor do
  def get_interface_stats(device_ip) do
    community = "public"
    
    with {:ok, if_count} <- SNMPMgr.get(device_ip, "ifNumber.0", community: community),
         {:ok, descriptions} <- SNMPMgr.walk(device_ip, "ifDescr", community: community),
         {:ok, admin_status} <- SNMPMgr.walk(device_ip, "ifAdminStatus", community: community),
         {:ok, oper_status} <- SNMPMgr.walk(device_ip, "ifOperStatus", community: community),
         {:ok, in_octets} <- SNMPMgr.walk(device_ip, "ifInOctets", community: community),
         {:ok, out_octets} <- SNMPMgr.walk(device_ip, "ifOutOctets", community: community) do
      
      interfaces = build_interface_list(descriptions, admin_status, oper_status, 
                                       in_octets, out_octets)
      
      {:ok, %{
        device: device_ip,
        interface_count: if_count,
        interfaces: interfaces
      }}
    end
  end

  defp build_interface_list(descriptions, admin_status, oper_status, in_octets, out_octets) do
    # Combine all the walked data into interface records
    indexes = extract_indexes(descriptions)
    
    Enum.map(indexes, fn index ->
      %{
        index: index,
        description: find_value_by_index(descriptions, index),
        admin_status: parse_status(find_value_by_index(admin_status, index)),
        oper_status: parse_status(find_value_by_index(oper_status, index)),
        in_octets: find_value_by_index(in_octets, index),
        out_octets: find_value_by_index(out_octets, index)
      }
    end)
  end
end
```

### Custom MIB Application

```elixir
defmodule CompanyMIBLoader do
  @company_mibs [
    "COMPANY-SYSTEM-MIB",
    "COMPANY-NETWORK-MIB", 
    "COMPANY-SECURITY-MIB"
  ]

  def load_company_mibs do
    # Add company MIB directory
    SNMPMgr.MIB.add_mib_path("/opt/company/mibs")
    
    results = Enum.map(@company_mibs, fn mib ->
      case SNMPMgr.MIB.load_mib(mib) do
        {:ok, objects} -> 
          Logger.info("Loaded #{mib} with #{length(objects)} objects")
          {:ok, mib, objects}
        {:error, reason} -> 
          Logger.error("Failed to load #{mib}: #{inspect(reason)}")
          {:error, mib, reason}
      end
    end)
    
    # Register commonly used custom objects
    register_common_objects()
    
    results
  end

  defp register_common_objects do
    # Register company-specific OIDs for easy access
    SNMPMgr.MIB.register_object("companySystemStatus", [1, 3, 6, 1, 4, 1, 12345, 1, 1])
    SNMPMgr.MIB.register_object("companyNetworkHealth", [1, 3, 6, 1, 4, 1, 12345, 2, 1])
    SNMPMgr.MIB.register_object("companySecurityLevel", [1, 3, 6, 1, 4, 1, 12345, 3, 1])
  end

  def get_company_status(device_ip) do
    with {:ok, sys_status} <- SNMPMgr.get(device_ip, "companySystemStatus.0"),
         {:ok, net_health} <- SNMPMgr.get(device_ip, "companyNetworkHealth.0"),
         {:ok, sec_level} <- SNMPMgr.get(device_ip, "companySecurityLevel.0") do
      {:ok, %{
        system_status: parse_system_status(sys_status),
        network_health: parse_network_health(net_health),
        security_level: parse_security_level(sec_level)
      }}
    end
  end
end
```

## Error Handling

### Common MIB Errors

```elixir
case SNMPMgr.MIB.resolve_oid("unknownObject") do
  {:ok, oid} -> 
    # Object found
    use_oid(oid)
  {:error, :not_found} -> 
    # Object not in MIB registry
    Logger.warn("Object not found in MIB registry")
  {:error, reason} -> 
    # Other error
    Logger.error("MIB resolution failed: #{inspect(reason)}")
end

case SNMPMgr.MIB.load_mib("BROKEN-MIB") do
  {:ok, objects} -> 
    Logger.info("Successfully loaded MIB")
  {:error, :snmp_compiler_not_available} -> 
    Logger.warn("MIB compilation not available")
  {:error, :file_not_found} -> 
    Logger.error("MIB file not found")
  {:error, {:compilation_error, details}} -> 
    Logger.error("MIB compilation failed: #{inspect(details)}")
end
```

## Best Practices

### 1. Use Symbolic Names

```elixir
# Preferred - readable and maintainable
{:ok, desc} = SNMPMgr.get(device, "sysDescr.0")

# Avoid - numeric OIDs are hard to read
{:ok, desc} = SNMPMgr.get(device, "1.3.6.1.2.1.1.1.0")
```

### 2. Load Custom MIBs Early

```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    # Load custom MIBs during application startup
    load_custom_mibs()
    
    children = [
      # ... other children
    ]
    
    Supervisor.start_link(children, opts)
  end

  defp load_custom_mibs do
    SNMPMgr.MIB.add_mib_path("/opt/custom_mibs")
    SNMPMgr.MIB.load_mib_directory("/opt/custom_mibs")
  end
end
```

### 3. Handle MIB Resolution Gracefully

```elixir
defmodule SafeSNMP do
  def safe_get(device, object_name, opts \\ []) do
    case SNMPMgr.MIB.resolve_oid(object_name) do
      {:ok, _oid} -> 
        SNMPMgr.get(device, object_name, opts)
      {:error, :not_found} -> 
        {:error, {:unknown_object, object_name}}
    end
  end
end
```

### 4. Organize Custom Objects

```elixir
defmodule MyApp.MIBRegistry do
  @custom_objects %{
    "companySystemInfo" => [1, 3, 6, 1, 4, 1, 12345, 1],
    "companyDeviceHealth" => [1, 3, 6, 1, 4, 1, 12345, 2],
    "companyNetworkStats" => [1, 3, 6, 1, 4, 1, 12345, 3]
  }

  def register_all do
    Enum.each(@custom_objects, fn {name, oid} ->
      SNMPMgr.MIB.register_object(name, oid)
    end)
  end

  def list_custom_objects do
    Map.keys(@custom_objects)
  end
end
```