# SnmpMgr Interactive Console Configuration
# This file provides helpful aliases, functions, and examples for working with SnmpMgr

# Import commonly used modules
import SnmpMgr
import SnmpMgr.{Walk, Bulk, Table, Multi, Config, Types, MIB}

# Aliases for convenience
alias SnmpMgr.{Core, Target, Errors, Metrics, Stream, Engine}

# Set up some default configuration
IO.puts("🔧 Setting up SnmpMgr console environment...")

# Common SNMP community strings
defmodule IEx.Helpers.Snmp do
  @moduledoc """
  Helper functions for SNMP operations in IEx console.
  """

  # Common OIDs for quick reference
  @common_oids %{
    # System group (1.3.6.1.2.1.1)
    "sysDescr" => "1.3.6.1.2.1.1.1.0",
    "sysObjectID" => "1.3.6.1.2.1.1.2.0", 
    "sysUpTime" => "1.3.6.1.2.1.1.3.0",
    "sysContact" => "1.3.6.1.2.1.1.4.0",
    "sysName" => "1.3.6.1.2.1.1.5.0",
    "sysLocation" => "1.3.6.1.2.1.1.6.0",
    "sysServices" => "1.3.6.1.2.1.1.7.0",
    
    # Interface group (1.3.6.1.2.1.2)
    "ifNumber" => "1.3.6.1.2.1.2.1.0",
    "ifTable" => "1.3.6.1.2.1.2.2",
    "ifDescr" => "1.3.6.1.2.1.2.2.1.2",
    "ifType" => "1.3.6.1.2.1.2.2.1.3",
    "ifMtu" => "1.3.6.1.2.1.2.2.1.4",
    "ifSpeed" => "1.3.6.1.2.1.2.2.1.5",
    "ifPhysAddress" => "1.3.6.1.2.1.2.2.1.6",
    "ifAdminStatus" => "1.3.6.1.2.1.2.2.1.7",
    "ifOperStatus" => "1.3.6.1.2.1.2.2.1.8",
    "ifInOctets" => "1.3.6.1.2.1.2.2.1.10",
    "ifOutOctets" => "1.3.6.1.2.1.2.2.1.16",
    
    # IP group (1.3.6.1.2.1.4)
    "ipForwarding" => "1.3.6.1.2.1.4.1.0",
    "ipDefaultTTL" => "1.3.6.1.2.1.4.2.0",
    "ipInReceives" => "1.3.6.1.2.1.4.3.0",
    
    # SNMP group (1.3.6.1.2.1.11)
    "snmpInPkts" => "1.3.6.1.2.1.11.1.0",
    "snmpOutPkts" => "1.3.6.1.2.1.11.2.0",
    "snmpInBadVersions" => "1.3.6.1.2.1.11.3.0"
  }

  @doc "List all available common OIDs"
  def oids, do: @common_oids

  @doc "Get a common OID by name"
  def oid(name) when is_binary(name), do: Map.get(@common_oids, name)
  def oid(name) when is_atom(name), do: Map.get(@common_oids, Atom.to_string(name))

  @doc "Quick GET with common settings"
  def qget(target, oid_name, opts \\ []) do
    oid = oid(oid_name) || oid_name
    default_opts = [community: "public", timeout: 5000]
    SnmpMgr.get(target, oid, Keyword.merge(default_opts, opts))
  end

  @doc "Quick WALK with common settings"
  def qwalk(target, oid_name, opts \\ []) do
    oid = oid(oid_name) || oid_name
    default_opts = [community: "public", timeout: 10000, version: :v2c]
    SnmpMgr.walk(target, oid, Keyword.merge(default_opts, opts))
  end

  @doc "Quick BULK GET with common settings"
  def qbulk(target, oid_name, opts \\ []) do
    oid = oid(oid_name) || oid_name
    default_opts = [community: "public", timeout: 10000, max_repetitions: 20]
    SnmpMgr.Bulk.get_bulk(target, oid, Keyword.merge(default_opts, opts))
  end

  @doc "Get system information (description, uptime, contact, name, location)"
  def system_info(target, opts \\ []) do
    default_opts = [community: "public", timeout: 5000]
    opts = Keyword.merge(default_opts, opts)
    
    %{
      description: SnmpMgr.get(target, oid("sysDescr"), opts),
      uptime: SnmpMgr.get(target, oid("sysUpTime"), opts),
      contact: SnmpMgr.get(target, oid("sysContact"), opts),
      name: SnmpMgr.get(target, oid("sysName"), opts),
      location: SnmpMgr.get(target, oid("sysLocation"), opts)
    }
  end

  @doc "Get interface table as structured data"
  def interface_table(target, opts \\ []) do
    default_opts = [community: "public", timeout: 15000, version: :v2c]
    opts = Keyword.merge(default_opts, opts)
    
    case SnmpMgr.walk(target, oid("ifTable"), opts) do
      {:ok, results} ->
        case SnmpMgr.Table.to_table(results, [1, 3, 6, 1, 2, 1, 2, 2]) do
          {:ok, table} -> {:ok, table}
          error -> error
        end
      error -> error
    end
  end

  @doc "Test connectivity to a device"
  def ping(target, opts \\ []) do
    default_opts = [community: "public", timeout: 3000]
    opts = Keyword.merge(default_opts, opts)
    
    case SnmpMgr.get(target, oid("sysUpTime"), opts) do
      {:ok, _uptime} -> {:ok, :reachable}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Show device uptime in human readable format"
  def uptime(target, opts \\ []) do
    case qget(target, "sysUpTime", opts) do
      {:ok, {:timeticks, ticks}} ->
        seconds = div(ticks, 100)
        days = div(seconds, 86400)
        hours = div(rem(seconds, 86400), 3600)
        minutes = div(rem(seconds, 3600), 60)
        secs = rem(seconds, 60)
        
        {:ok, "#{days} days, #{hours} hours, #{minutes} minutes, #{secs} seconds"}
      
      {:ok, ticks} when is_integer(ticks) ->
        seconds = div(ticks, 100)
        days = div(seconds, 86400)
        hours = div(rem(seconds, 86400), 3600)
        minutes = div(rem(seconds, 3600), 60)
        secs = rem(seconds, 60)
        
        {:ok, "#{days} days, #{hours} hours, #{minutes} minutes, #{secs} seconds"}
      
      error -> error
    end
  end

  @doc "Show interface statistics for a specific interface index"
  def interface_stats(target, if_index, opts \\ []) do
    default_opts = [community: "public", timeout: 5000]
    opts = Keyword.merge(default_opts, opts)
    
    %{
      description: SnmpMgr.get(target, "#{oid("ifDescr")}.#{if_index}", opts),
      admin_status: SnmpMgr.get(target, "#{oid("ifAdminStatus")}.#{if_index}", opts),
      oper_status: SnmpMgr.get(target, "#{oid("ifOperStatus")}.#{if_index}", opts),
      in_octets: SnmpMgr.get(target, "#{oid("ifInOctets")}.#{if_index}", opts),
      out_octets: SnmpMgr.get(target, "#{oid("ifOutOctets")}.#{if_index}", opts),
      speed: SnmpMgr.get(target, "#{oid("ifSpeed")}.#{if_index}", opts)
    }
  end

  @doc "Multi-target system information gathering"
  def multi_system_info(targets, opts \\ []) do
    default_opts = [community: "public", timeout: 5000]
    opts = Keyword.merge(default_opts, opts)
    
    requests = Enum.map(targets, fn target ->
      {target, oid("sysDescr"), opts}
    end)
    
    SnmpMgr.Multi.get_multi(requests)
  end

  @doc "Show help for SNMP helper functions"
  def help do
    IO.puts("""
    
    📡 SnmpMgr Console Helper Functions:
    
    Basic Operations:
      qget(target, oid_name, opts)     - Quick GET operation
      qwalk(target, oid_name, opts)    - Quick WALK operation  
      qbulk(target, oid_name, opts)    - Quick BULK operation
      ping(target, opts)               - Test device connectivity
    
    System Information:
      system_info(target, opts)        - Get all system info
      uptime(target, opts)             - Get formatted uptime
      
    Interface Operations:
      interface_table(target, opts)    - Get structured interface table
      interface_stats(target, if_index, opts) - Get interface statistics
      
    Multi-Target:
      multi_system_info(targets, opts) - Get system info from multiple devices
      
    Utilities:
      oids()                          - List all common OIDs
      oid(name)                       - Get OID by name
      help()                          - Show this help
    
    Example Usage:
      qget("192.168.1.1", "sysDescr")
      qwalk("switch.local", "ifTable", community: "private")
      system_info("router.local")
      uptime("192.168.1.1")
      interface_stats("switch.local", 1)
      
    Common OID Names:
      sysDescr, sysUpTime, sysContact, sysName, sysLocation
      ifTable, ifDescr, ifType, ifSpeed, ifInOctets, ifOutOctets
      
    """)
  end
end

# Import the helper functions into the console
import IEx.Helpers.Snmp

# Set some reasonable defaults
SnmpMgr.Config.set_default_community("public")
SnmpMgr.Config.set_default_timeout(5000)
SnmpMgr.Config.set_default_retries(3)

IO.puts("""
🚀 SnmpMgr Console Ready!

Quick Start Examples:
  qget("192.168.1.1", "sysDescr")              # Get system description
  system_info("device.local")                  # Get all system info
  qwalk("switch.local", "ifTable")             # Walk interface table
  uptime("router.local")                       # Get formatted uptime
  help()                                       # Show all helper functions

Available modules: SnmpMgr, Walk, Bulk, Table, Multi, Config, Types, MIB
Helper functions: qget/3, qwalk/3, qbulk/3, system_info/2, uptime/2, help/0

Type 'help()' for detailed usage information.
""")
