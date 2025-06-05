# SnmpMgr.Config Module Guide

The `SnmpMgr.Config` module provides centralized configuration management for all SNMP operations. It allows you to set global defaults that apply across all requests while still permitting per-request overrides.

## Overview

The Config module runs as a GenServer that maintains global default settings. These defaults are automatically merged with per-request options, with request-specific options taking precedence.

## Starting the Configuration Service

```elixir
# Start with default configuration
{:ok, pid} = SnmpMgr.Config.start_link()

# Start with custom initial configuration
{:ok, pid} = SnmpMgr.Config.start_link([
  community: "custom_public",
  timeout: 10000,
  version: :v2c
])
```

## Configuration Functions

### Setting Default Values

#### `set_default_community/1`

Sets the default SNMP community string.

```elixir
# Set default community
SnmpMgr.Config.set_default_community("public")
SnmpMgr.Config.set_default_community("private")

# Now all requests use this community unless overridden
{:ok, value} = SnmpMgr.get("device", "sysDescr.0")  # Uses "private"
{:ok, value} = SnmpMgr.get("device", "sysDescr.0", community: "special")  # Uses "special"
```

#### `set_default_timeout/1`

Sets the default timeout for SNMP requests in milliseconds.

```elixir
# Set default timeout to 3 seconds
SnmpMgr.Config.set_default_timeout(3000)

# Set longer timeout for slow networks
SnmpMgr.Config.set_default_timeout(15000)

# Now all requests use this timeout unless overridden
{:ok, value} = SnmpMgr.get("device", "sysDescr.0")  # Uses 15000ms
{:ok, value} = SnmpMgr.get("device", "sysDescr.0", timeout: 1000)  # Uses 1000ms
```

#### `set_default_retries/1`

Sets the default number of retry attempts.

```elixir
# Set default retries
SnmpMgr.Config.set_default_retries(3)

# Disable retries by default
SnmpMgr.Config.set_default_retries(0)
```

#### `set_default_version/1`

Sets the default SNMP version.

```elixir
# Set to SNMP v2c (supports bulk operations)
SnmpMgr.Config.set_default_version(:v2c)

# Set to SNMP v1 (more compatible)
SnmpMgr.Config.set_default_version(:v1)
```

#### `set_default_port/1`

Sets the default SNMP port.

```elixir
# Set custom default port
SnmpMgr.Config.set_default_port(1161)

# Back to standard port
SnmpMgr.Config.set_default_port(161)
```

### Retrieving Configuration

#### `get_config/0`

Retrieves the complete current configuration.

```elixir
config = SnmpMgr.Config.get_config()
IO.inspect(config)
# %{
#   community: "public",
#   timeout: 5000,
#   retries: 1,
#   version: :v2c,
#   port: 161,
#   mib_paths: []
# }
```

#### Individual Getters

```elixir
community = SnmpMgr.Config.get_default_community()
timeout = SnmpMgr.Config.get_default_timeout()
retries = SnmpMgr.Config.get_default_retries()
version = SnmpMgr.Config.get_default_version()
port = SnmpMgr.Config.get_default_port()
```

### Configuration Reset

#### `reset/0`

Resets all configuration to default values.

```elixir
# After setting custom values
SnmpMgr.Config.set_default_timeout(15000)
SnmpMgr.Config.set_default_community("private")

# Reset to defaults
SnmpMgr.Config.reset()

# Now back to default values
config = SnmpMgr.Config.get_config()
# %{community: "public", timeout: 5000, ...}
```

### Option Merging

#### `merge_opts/1`

Merges provided options with global defaults. This is used internally but can be called directly.

```elixir
# With global timeout of 5000ms and community "public"
merged = SnmpMgr.Config.merge_opts([timeout: 2000, version: :v1])
# [community: "public", timeout: 2000, retries: 1, version: :v1, port: 161]
```

## MIB Path Management

### Adding MIB Paths

#### `add_mib_path/1`

Adds a directory to the MIB search path.

```elixir
# Add custom MIB directory
SnmpMgr.Config.add_mib_path("/opt/snmp/mibs")
SnmpMgr.Config.add_mib_path("/usr/local/share/mibs")

# Add relative path
SnmpMgr.Config.add_mib_path("./custom_mibs")
```

#### `get_mib_paths/0`

Retrieves the current list of MIB search paths.

```elixir
paths = SnmpMgr.Config.get_mib_paths()
IO.inspect(paths)
# ["/opt/snmp/mibs", "/usr/local/share/mibs", "./custom_mibs"]
```

#### `set_mib_paths/1`

Sets the complete list of MIB search paths.

```elixir
# Replace all MIB paths
SnmpMgr.Config.set_mib_paths([
  "/etc/snmp/mibs",
  "/var/lib/mibs",
  "./project_mibs"
])
```

## Configuration Patterns

### Application Startup Configuration

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    # Start configuration service early
    children = [
      {SnmpMgr.Config, [
        community: Application.get_env(:my_app, :snmp_community, "public"),
        timeout: Application.get_env(:my_app, :snmp_timeout, 5000),
        version: Application.get_env(:my_app, :snmp_version, :v2c)
      ]},
      # ... other children
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Environment-Based Configuration

```elixir
defmodule MyApp.SNMPConfig do
  def setup do
    case Mix.env() do
      :prod ->
        SnmpMgr.Config.set_default_community(System.get_env("SNMP_COMMUNITY"))
        SnmpMgr.Config.set_default_timeout(10000)
        SnmpMgr.Config.set_default_retries(3)
      
      :dev ->
        SnmpMgr.Config.set_default_community("public")
        SnmpMgr.Config.set_default_timeout(5000)
        SnmpMgr.Config.set_default_retries(1)
      
      :test ->
        SnmpMgr.Config.set_default_community("test")
        SnmpMgr.Config.set_default_timeout(1000)
        SnmpMgr.Config.set_default_retries(0)
    end
  end
end
```

### Dynamic Configuration Updates

```elixir
defmodule MyApp.ConfigManager do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def update_snmp_config(changes) do
    GenServer.call(__MODULE__, {:update_config, changes})
  end

  def handle_call({:update_config, changes}, _from, state) do
    Enum.each(changes, fn
      {:community, value} -> SnmpMgr.Config.set_default_community(value)
      {:timeout, value} -> SnmpMgr.Config.set_default_timeout(value)
      {:version, value} -> SnmpMgr.Config.set_default_version(value)
      {:retries, value} -> SnmpMgr.Config.set_default_retries(value)
    end)
    
    {:reply, :ok, state}
  end
end

# Usage
MyApp.ConfigManager.update_snmp_config([
  community: "new_community",
  timeout: 8000
])
```

## Configuration Validation

### Custom Validation

```elixir
defmodule MyApp.SNMPConfigValidator do
  def validate_and_set_config(config) do
    with :ok <- validate_community(config[:community]),
         :ok <- validate_timeout(config[:timeout]),
         :ok <- validate_version(config[:version]) do
      apply_config(config)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_community(nil), do: {:error, "Community cannot be nil"}
  defp validate_community(""), do: {:error, "Community cannot be empty"}
  defp validate_community(community) when is_binary(community), do: :ok
  defp validate_community(_), do: {:error, "Community must be a string"}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, "Timeout must be a positive integer"}

  defp validate_version(version) when version in [:v1, :v2c], do: :ok
  defp validate_version(_), do: {:error, "Version must be :v1 or :v2c"}

  defp apply_config(config) do
    if config[:community], do: SnmpMgr.Config.set_default_community(config[:community])
    if config[:timeout], do: SnmpMgr.Config.set_default_timeout(config[:timeout])
    if config[:version], do: SnmpMgr.Config.set_default_version(config[:version])
    :ok
  end
end
```

## Best Practices

### 1. Set Appropriate Defaults

```elixir
# For production environments
SnmpMgr.Config.set_default_timeout(10000)  # Longer timeout for reliability
SnmpMgr.Config.set_default_retries(3)      # More retries for unreliable networks
SnmpMgr.Config.set_default_version(:v2c)   # v2c for bulk operations

# For development/testing
SnmpMgr.Config.set_default_timeout(2000)   # Shorter timeout for faster feedback
SnmpMgr.Config.set_default_retries(1)      # Fewer retries to fail fast
```

### 2. Use Environment Variables

```elixir
# Load configuration from environment
community = System.get_env("SNMP_COMMUNITY", "public")
timeout = String.to_integer(System.get_env("SNMP_TIMEOUT", "5000"))

SnmpMgr.Config.set_default_community(community)
SnmpMgr.Config.set_default_timeout(timeout)
```

### 3. Override for Specific Use Cases

```elixir
# Use defaults for most operations
{:ok, value} = SnmpMgr.get("device", "sysDescr.0")

# Override for slow devices
{:ok, value} = SnmpMgr.get("slow_device", "sysDescr.0", timeout: 30000)

# Override for secure operations
{:ok, _} = SnmpMgr.set("device", "sysContact.0", "admin@company.com", 
                      community: "write_community")
```

### 4. Document Configuration Requirements

```elixir
defmodule MyApp.DeviceManager do
  @moduledoc """
  Device management functions.
  
  ## Configuration Requirements
  
  Before using this module, ensure SNMP configuration is set:
  
      SnmpMgr.Config.set_default_community("your_community")
      SnmpMgr.Config.set_default_timeout(5000)
      SnmpMgr.Config.set_default_version(:v2c)
  
  """

  def get_device_info(ip) do
    # Uses configured defaults
    with {:ok, desc} <- SnmpMgr.get(ip, "sysDescr.0"),
         {:ok, name} <- SnmpMgr.get(ip, "sysName.0"),
         {:ok, uptime} <- SnmpMgr.get(ip, "sysUpTime.0") do
      {:ok, %{description: desc, name: name, uptime: uptime}}
    end
  end
end
```

## Configuration Schema

### Default Configuration

```elixir
%{
  community: "public",      # SNMP community string
  timeout: 5000,           # Request timeout in milliseconds
  retries: 1,              # Number of retry attempts
  port: 161,               # Default SNMP port
  version: :v1,            # SNMP version (:v1 or :v2c)
  mib_paths: []            # List of MIB search paths
}
```

### Valid Options

| Setting | Type | Valid Values | Default |
|---------|------|--------------|---------|
| `community` | String | Any string | "public" |
| `timeout` | Integer | > 0 | 5000 |
| `retries` | Integer | >= 0 | 1 |
| `port` | Integer | 1-65535 | 161 |
| `version` | Atom | `:v1`, `:v2c` | `:v1` |
| `mib_paths` | List | List of strings | `[]` |

## Error Handling

```elixir
# Configuration service not started
case SnmpMgr.Config.get_config() do
  config when is_map(config) -> use_config(config)
  {:error, :noproc} -> 
    Logger.error("Config service not started")
    use_default_config()
end

# Invalid configuration values are validated at runtime
try do
  SnmpMgr.Config.set_default_timeout(-1000)
rescue
  ArgumentError -> Logger.error("Invalid timeout value")
end
```

## Integration with Other Modules

The Config module integrates seamlessly with all other SnmpMgr modules:

```elixir
# Configuration affects all operations
SnmpMgr.Config.set_default_community("private")

# All these use the configured community
{:ok, _} = SnmpMgr.get("device", "sysDescr.0")
{:ok, _} = SnmpMgr.walk("device", "system")
{:ok, _} = SnmpMgr.get_bulk("device", "ifTable")

# MIB operations use configured paths
SnmpMgr.Config.add_mib_path("/opt/mibs")
{:ok, _} = SnmpMgr.MIB.load_mib("CUSTOM-MIB")
```