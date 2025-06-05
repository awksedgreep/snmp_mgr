# Getting Started with SnmpMgr

SnmpMgr is a lightweight, stateless SNMP client library for Elixir that provides simple and efficient SNMP operations without requiring heavyweight management processes.

## Installation

Add `snmp_mgr` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:snmp_mgr, "~> 1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### Basic SNMP GET Operation

```elixir
# Fetch system description from a device
{:ok, value} = SnmpMgr.get("192.168.1.1", "1.3.6.1.2.1.1.1.0", 
                          community: "public", timeout: 5000)
IO.puts("System Description: #{value}")
```

### Using Symbolic Names

SnmpMgr includes built-in MIB support for common objects:

```elixir
# Using symbolic MIB names instead of numeric OIDs
{:ok, uptime} = SnmpMgr.get("192.168.1.1", "sysUpTime.0", community: "public")
{:ok, name} = SnmpMgr.get("192.168.1.1", "sysName.0", community: "public")
```

### Walking SNMP Tables

```elixir
# Walk the system group to get all system information
{:ok, results} = SnmpMgr.walk("192.168.1.1", "1.3.6.1.2.1.1", 
                             community: "public", timeout: 10000)

Enum.each(results, fn {oid, value} ->
  IO.puts("#{oid}: #{value}")
end)
```

### Bulk Operations

For more efficient retrieval of multiple values:

```elixir
# Get multiple values efficiently with GET-BULK
{:ok, results} = SnmpMgr.get_bulk("192.168.1.1", "1.3.6.1.2.1.2.2", 
                                 max_repetitions: 10, community: "public")
```

### Setting Values

```elixir
# Set system contact information
{:ok, _} = SnmpMgr.set("192.168.1.1", "sysContact.0", "admin@company.com",
                      community: "private")
```

## Configuration

### Global Configuration

You can set global defaults that apply to all operations:

```elixir
# Start the configuration service
{:ok, _pid} = SnmpMgr.Config.start_link()

# Set global defaults
SnmpMgr.Config.set_default_community("public")
SnmpMgr.Config.set_default_timeout(5000)
SnmpMgr.Config.set_default_version(:v2c)

# Now you can omit these options in calls
{:ok, value} = SnmpMgr.get("192.168.1.1", "sysDescr.0")
```

### Per-Request Configuration

You can override defaults on a per-request basis:

```elixir
{:ok, value} = SnmpMgr.get("192.168.1.1", "sysDescr.0", 
                          community: "special", 
                          timeout: 10000,
                          version: :v1)
```

## SNMP Versions

SnmpMgr supports SNMP versions 1 and 2c:

```elixir
# SNMP v1
{:ok, value} = SnmpMgr.get("device.local", "sysDescr.0", 
                          version: :v1, community: "public")

# SNMP v2c (default, supports bulk operations)
{:ok, results} = SnmpMgr.get_bulk("device.local", "ifTable", 
                                 version: :v2c, max_repetitions: 5)
```

## Error Handling

SnmpMgr provides clear error responses:

```elixir
case SnmpMgr.get("192.168.1.1", "invalid.oid", community: "public") do
  {:ok, value} -> 
    IO.puts("Success: #{value}")
  {:error, :timeout} -> 
    IO.puts("Request timed out")
  {:error, :noSuchObject} -> 
    IO.puts("Object does not exist")
  {:error, reason} -> 
    IO.puts("Error: #{inspect(reason)}")
end
```

## Common Use Cases

### Device Discovery

```elixir
devices = ["192.168.1.1", "192.168.1.2", "192.168.1.3"]

device_info = Enum.map(devices, fn ip ->
  case SnmpMgr.get(ip, "sysDescr.0", community: "public", timeout: 2000) do
    {:ok, desc} -> {ip, desc}
    {:error, _} -> {ip, "unreachable"}
  end
end)
```

### Interface Monitoring

```elixir
# Get interface table
{:ok, interfaces} = SnmpMgr.walk("192.168.1.1", "ifDescr", community: "public")

# Get interface statistics
{:ok, stats} = SnmpMgr.walk("192.168.1.1", "ifInOctets", community: "public")
```

### Multi-Target Operations

```elixir
# Query multiple devices simultaneously
requests = [
  {"192.168.1.1", "sysUpTime.0", [community: "public"]},
  {"192.168.1.2", "sysUpTime.0", [community: "public"]},
  {"192.168.1.3", "sysUpTime.0", [community: "public"]}
]

results = SnmpMgr.get_multi(requests)
```

## Target Formats

SnmpMgr accepts various target formats:

```elixir
# IP address with default port (161)
SnmpMgr.get("192.168.1.1", "sysDescr.0")

# IP address with custom port
SnmpMgr.get("192.168.1.1:1161", "sysDescr.0")

# Hostname
SnmpMgr.get("router.local", "sysDescr.0")

# Hostname with port
SnmpMgr.get("switch.company.com:161", "sysDescr.0")
```

## MIB Support

### Built-in MIBs

SnmpMgr includes built-in support for standard MIB objects:

- **System Group**: `sysDescr`, `sysUpTime`, `sysContact`, `sysName`, `sysLocation`
- **Interfaces Group**: `ifNumber`, `ifDescr`, `ifType`, `ifSpeed`, `ifInOctets`, `ifOutOctets`
- **IP Group**: `ipForwarding`, `ipDefaultTTL`, `ipInReceives`
- **ICMP Group**: `icmpInMsgs`, `icmpOutMsgs`
- **TCP Group**: `tcpActiveOpens`, `tcpPassiveOpens`
- **UDP Group**: `udpInDatagrams`, `udpOutDatagrams`

### Loading Custom MIBs

```elixir
# Add custom MIB paths
SnmpMgr.Config.add_mib_path("/path/to/custom/mibs")

# Load a specific MIB file
{:ok, _} = SnmpMgr.MIB.load_mib("CUSTOM-MIB")
```

## Best Practices

1. **Use appropriate timeouts**: Start with 5000ms and adjust based on network conditions
2. **Handle errors gracefully**: Always pattern match on `{:ok, result}` and `{:error, reason}`
3. **Use bulk operations**: For retrieving multiple values, `get_bulk` is more efficient than multiple `get` calls
4. **Set reasonable limits**: Use `max_repetitions` in bulk operations to avoid overwhelming devices
5. **Use symbolic names**: When possible, use MIB names instead of numeric OIDs for better readability

## Next Steps

- Read the [SnmpMgr Module Guide](snmp_mgr_guide.md) for detailed API documentation
- Explore [Configuration Guide](config_guide.md) for advanced configuration options
- Check out [MIB Guide](mib_guide.md) for working with MIB files
- See [Types Guide](types_guide.md) for SNMP data type handling

## Common Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:community` | String | "public" | SNMP community string |
| `:timeout` | Integer | 5000 | Request timeout in milliseconds |
| `:retries` | Integer | 1 | Number of retry attempts |
| `:version` | Atom | `:v1` | SNMP version (`:v1` or `:v2c`) |
| `:max_repetitions` | Integer | 0 | Maximum repetitions for bulk operations |
| `:non_repeaters` | Integer | 0 | Non-repeating variables in bulk operations |

## Troubleshooting

### Common Issues

**Timeout errors**: Increase timeout value or check network connectivity
```elixir
SnmpMgr.get("device", "sysDescr.0", timeout: 10000)
```

**Authentication errors**: Verify community string
```elixir
SnmpMgr.get("device", "sysDescr.0", community: "correct_community")
```

**No such object**: Verify OID exists on target device
```elixir
# Use walk to explore available OIDs
{:ok, available} = SnmpMgr.walk("device", "1.3.6.1.2.1.1")
```

**Port issues**: Ensure SNMP is enabled on target device and port 161 is accessible
```elixir
# Test with custom port if needed
SnmpMgr.get("device:1161", "sysDescr.0")
```