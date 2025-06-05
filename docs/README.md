# SNMPMgr Documentation

Welcome to the SNMPMgr documentation! This comprehensive guide will help you get started with and master the SNMPMgr library for SNMP operations in Elixir.

## Quick Start

- **[Getting Started Guide](getting_started.md)** - Start here for installation, basic usage, and common patterns

## Module Guides

### Core Modules

- **[SNMPMgr Guide](snmp_mgr_guide.md)** - Main API module for all SNMP operations (GET, SET, WALK, BULK)
- **[Config Guide](config_guide.md)** - Configuration management and global defaults
- **[Types Guide](types_guide.md)** - SNMP data type handling and conversion

### Utility Modules

- **[MIB Guide](mib_guide.md)** - MIB compilation and symbolic name resolution
- **[Multi Guide](multi_guide.md)** - Concurrent multi-target SNMP operations
- **[Table Guide](table_guide.md)** - SNMP table processing and analysis utilities

## Documentation Index

### Getting Started
- [Installation and Setup](getting_started.md#installation)
- [Quick Start Examples](getting_started.md#quick-start)
- [Configuration](getting_started.md#configuration)
- [Common Use Cases](getting_started.md#common-use-cases)

### Core Operations
- [Basic SNMP Operations](snmp_mgr_guide.md#core-operations) - GET, SET, GETNEXT
- [Bulk Operations](snmp_mgr_guide.md#bulk-operations) - GETBULK for efficiency
- [Walk Operations](snmp_mgr_guide.md#walk-operations) - Tree traversal
- [Multi-Target Operations](snmp_mgr_guide.md#multi-target-operations) - Concurrent requests

### Configuration Management
- [Global Configuration](config_guide.md#configuration-functions) - Setting defaults
- [Per-Request Options](config_guide.md#option-merging) - Override defaults
- [MIB Path Management](config_guide.md#mib-path-management) - Custom MIB directories
- [Environment Configuration](config_guide.md#environment-based-configuration) - Production setup

### Data Types and Encoding
- [SNMP Type System](types_guide.md#supported-snmp-types) - All supported types
- [Automatic Type Inference](types_guide.md#value-encoding) - Let SNMPMgr choose
- [Explicit Type Specification](types_guide.md#value-encoding) - Force specific types
- [Value Decoding](types_guide.md#value-decoding) - Convert SNMP to Elixir

### MIB Support
- [Built-in MIB Objects](mib_guide.md#built-in-mib-objects) - Standard SNMP objects
- [Symbolic Name Resolution](mib_guide.md#oid-resolution-functions) - Use names instead of OIDs
- [Custom MIB Loading](mib_guide.md#custom-mib-loading) - Load vendor MIBs
- [MIB Management](mib_guide.md#mib-management) - List and search objects

### Multi-Device Operations
- [Concurrent Operations](multi_guide.md#core-functions) - Query multiple devices
- [Performance Optimization](multi_guide.md#performance-optimization) - Scaling strategies
- [Error Handling](multi_guide.md#error-handling-best-practices) - Resilient operations
- [Use Cases](multi_guide.md#common-use-cases) - Device discovery, monitoring

### Table Processing
- [Table Structure](table_guide.md#core-functions) - Understanding SNMP tables
- [Data Conversion](table_guide.md#core-functions) - Flat to structured format
- [Table Operations](table_guide.md#advanced-table-operations) - Filtering, sorting, joining
- [Analysis Examples](table_guide.md#complete-table-processing-examples) - Real-world scenarios

## Common Recipes

### Device Discovery
```elixir
# Discover all SNMP devices in a subnet
ip_range = for i <- 1..254, do: "192.168.1.#{i}"
requests = Enum.map(ip_range, fn ip ->
  {ip, "sysDescr.0", [timeout: 2000, retries: 0]}
end)

results = SNMPMgr.Multi.get_multi(requests, community: "public")
devices = Enum.zip(ip_range, results)
|> Enum.filter(fn {_ip, result} -> match?({:ok, _}, result) end)
```

### Interface Monitoring
```elixir
# Get interface statistics
{:ok, if_data} = SNMPMgr.walk("192.168.1.1", "ifTable", community: "public")
{:ok, table} = SNMPMgr.Table.to_table(if_data, [1,3,6,1,2,1,2,2])

column_map = %{2 => :description, 8 => :admin_status, 9 => :oper_status}
{:ok, interfaces} = SNMPMgr.Table.to_records(table, column_map)
```

### Configuration Management
```elixir
# Set system contact on multiple devices
devices = [
  %{ip: "192.168.1.1", community: "private"},
  %{ip: "192.168.1.2", community: "private"}
]

set_requests = Enum.map(devices, fn device ->
  {device.ip, "sysContact.0", "admin@company.com", [community: device.community]}
end)

results = SNMPMgr.Multi.set_multi(set_requests)
```

### Custom MIB Usage
```elixir
# Load and use custom MIBs
SNMPMgr.Config.add_mib_path("/opt/vendor_mibs")
{:ok, _objects} = SNMPMgr.MIB.load_mib("VENDOR-SYSTEM-MIB")

# Now use vendor-specific objects
{:ok, vendor_status} = SNMPMgr.get("device", "vendorSystemStatus.0")
```

## Error Handling Patterns

### Basic Error Handling
```elixir
case SNMPMgr.get("device", "sysDescr.0", community: "public") do
  {:ok, description} -> 
    IO.puts("Device: #{description}")
  {:error, :timeout} -> 
    IO.puts("Device timeout")
  {:error, :noSuchObject} -> 
    IO.puts("Object not found")
  {:error, reason} -> 
    IO.puts("SNMP error: #{inspect(reason)}")
end
```

### Resilient Operations
```elixir
defmodule ResilientSNMP do
  def reliable_get(device, oid, max_retries \\ 3) do
    perform_get(device, oid, max_retries)
  end

  defp perform_get(_device, _oid, 0), do: {:error, :max_retries_exceeded}
  
  defp perform_get(device, oid, retries_left) do
    case SNMPMgr.get(device, oid, timeout: 5000) do
      {:ok, value} -> {:ok, value}
      {:error, :timeout} -> perform_get(device, oid, retries_left - 1)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Performance Tips

### 1. Use Bulk Operations
```elixir
# Preferred for multiple values
{:ok, interfaces} = SNMPMgr.get_bulk("device", "ifDescr", max_repetitions: 20)

# Avoid multiple individual GETs
# interfaces = Enum.map(1..20, fn i ->
#   SNMPMgr.get("device", "ifDescr.#{i}")
# end)
```

### 2. Configure Appropriate Timeouts
```elixir
# Fast local network
SNMPMgr.Config.set_default_timeout(2000)

# Slow WAN connections
SNMPMgr.Config.set_default_timeout(15000)
```

### 3. Use Concurrent Operations
```elixir
# Query multiple devices simultaneously
requests = Enum.map(devices, fn ip -> {ip, "sysUpTime.0"} end)
results = SNMPMgr.Multi.get_multi(requests, max_concurrent: 10)
```

### 4. Choose the Right SNMP Version
```elixir
# Use v2c for bulk operations
SNMPMgr.Config.set_default_version(:v2c)

# Use v1 for maximum compatibility
SNMPMgr.Config.set_default_version(:v1)
```

## Troubleshooting

### Common Issues

**Timeout Errors**
- Increase timeout values
- Check network connectivity
- Verify SNMP is enabled on target device

**Authentication Errors**
- Verify community string
- Check SNMP access controls on device

**No Such Object Errors**
- Verify OID exists on target device
- Use SNMP walk to explore available objects
- Check MIB support

**Performance Issues**
- Use bulk operations for multiple values
- Implement concurrent requests for multiple devices
- Optimize timeout values

### Debugging Tips

```elixir
# Enable detailed logging
Logger.configure(level: :debug)

# Test connectivity
{:ok, _} = SNMPMgr.get("device", "sysDescr.0", 
                      community: "public", 
                      timeout: 10000)

# Explore available objects
{:ok, objects} = SNMPMgr.walk("device", "1.3.6.1.2.1.1", 
                             community: "public")
```

## API Reference Summary

### Main Functions

| Function | Purpose | Returns |
|----------|---------|---------|
| `SNMPMgr.get/3` | Get single value | `{:ok, value}` or `{:error, reason}` |
| `SNMPMgr.set/4` | Set single value | `{:ok, value}` or `{:error, reason}` |
| `SNMPMgr.get_bulk/3` | Get multiple values | `{:ok, results}` or `{:error, reason}` |
| `SNMPMgr.walk/3` | Walk subtree | `{:ok, results}` or `{:error, reason}` |
| `SNMPMgr.Multi.get_multi/2` | Multi-device GET | List of results |
| `SNMPMgr.Table.to_table/2` | Convert to table | `{:ok, table}` or `{:error, reason}` |

### Configuration Functions

| Function | Purpose |
|----------|---------|
| `SNMPMgr.Config.set_default_community/1` | Set default community |
| `SNMPMgr.Config.set_default_timeout/1` | Set default timeout |
| `SNMPMgr.Config.set_default_version/1` | Set default SNMP version |
| `SNMPMgr.MIB.resolve_oid/1` | Convert name to OID |
| `SNMPMgr.Types.encode_value/2` | Encode value for SNMP |

## Contributing

SNMPMgr is designed to be extensible and welcomes contributions. Key areas for enhancement include:

- Additional MIB support
- Performance optimizations
- Error handling improvements
- Documentation examples
- Testing coverage

## Support

For questions, issues, or feature requests:

1. Check this documentation first
2. Review the module-specific guides
3. Look at the code examples
4. Check the troubleshooting section

Happy SNMP managing! 🐍📊