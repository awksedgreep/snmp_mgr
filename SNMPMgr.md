# SNMP_EX Library Development Roadmap

A comprehensive plan for building a production-ready Elixir SNMP management library.

## 📋 Project Overview

**Goal**: Create a modern, idiomatic Elixir SNMP client library that leverages Erlang's proven SNMP implementation without the heavyweight management infrastructure.

**Philosophy**: Cherry-pick the useful parts of Erlang's SNMP stack (ASN.1 encoding, MIB parsing, PDU handling) while building a clean, pipe-friendly Elixir API on top.

---

## 🚀 Phase 1: SNMP_Lite - Foundation (2-3 weeks)

### Core API Design

```elixir
defmodule SNMP do
  @moduledoc """
  Lightweight SNMP client library for Elixir
  """
  
  # Basic synchronous operations
  def get(target, oid, opts \\ [])
  def get_next(target, oid, opts \\ [])
  def set(target, oid, value, opts \\ [])
  
  # Simple async wrapper
  def get_async(target, oid, opts \\ [])
end

# Usage examples:
SNMP.get("192.168.1.1:161", "1.3.6.1.2.1.1.1.0", community: "public")
# => {:ok, "Cisco IOS Software..."}

SNMP.set("device.local", "1.3.6.1.2.1.1.6.0", "New Location")
# => {:ok, "New Location"}

SNMP.get_next("10.0.0.1", "1.3.6.1.2.1.1")
# => {:ok, {"1.3.6.1.2.1.1.1.0", "System Description"}}
```

### Internal Architecture

```elixir
defmodule SNMP.Core do
  # Direct Erlang PDU usage - no processes
  def encode_get_request(oid, community, request_id)
  def encode_set_request(oid, value, community, request_id)
  def decode_response(bytes)
  def send_receive_udp(target, packet, timeout)
end

defmodule SNMP.Types do
  # SNMP data type handling
  def encode_value(type, value)
  def decode_value(encoded)
  def infer_type(value)  # Auto-detect INTEGER, STRING, etc.
end

defmodule SNMP.Target do
  # Target parsing and validation
  def parse("192.168.1.1:161")     # => %{host: {192,168,1,1}, port: 161}
  def parse("device.local")        # => %{host: "device.local", port: 161}
  def resolve_hostname(target)
end
```

### Error Handling

```elixir
# Comprehensive error types
{:error, :timeout}
{:error, :no_response}
{:error, :invalid_community}
{:error, {:snmp_error, :no_such_name}}
{:error, {:network_error, :host_unreachable}}
```

### Testing Strategy

- Unit tests with mock UDP responses
- Integration tests against cable modem simulator
- Property-based testing for encoding/decoding
- Performance benchmarks vs native tools

### Success Criteria

- [ ] Basic GET/SET operations work reliably
- [ ] Clean, documented API
- [ ] Comprehensive test suite
- [ ] Performance comparable to native tools
- [ ] Works with cable modem simulator

---

## 📚 Phase 2: MIB Support & Full SNMPv1 (3-4 weeks)

### MIB Compilation & Loading

```elixir
defmodule SNMP.MIB do
  @moduledoc """
  MIB compilation and symbolic name resolution
  """
  
  # Compile MIBs using :snmpc
  def compile(mib_file, opts \\ [])
  def compile_dir(directory)
  
  # Load compiled MIBs
  def load(compiled_mib)
  def load_standard_mibs()  # RFC1213, SNMPv2, etc.
  
  # Name resolution
  def resolve(name)         # "sysDescr.0" => "1.3.6.1.2.1.1.1.0"
  def reverse_lookup(oid)   # "1.3.6.1.2.1.1.1.0" => "sysDescr.0"
  
  # Browse MIB tree
  def children(oid)
  def parent(oid)
  def walk_tree(root_oid)
end

# Usage with symbolic names:
SNMP.get("router.local", "sysDescr.0")
# => {:ok, "Cisco IOS Software..."}

SNMP.MIB.resolve("ifTable")
# => "1.3.6.1.2.1.2.2"

SNMP.MIB.children("system")
# => ["sysDescr", "sysObjectID", "sysUpTime", ...]
```

### Enhanced API

```elixir
# Walk operations (GETNEXT iteration)
def walk(target, root_oid, opts \\ [])
def walk_table(target, table_oid, opts \\ [])

# Table-specific helpers
def get_table(target, table_oid, opts \\ [])
def get_column(target, table_oid, column, opts \\ [])

# Usage:
SNMP.walk("switch.local", "ifTable")
# => [
#   {"1.3.6.1.2.1.2.2.1.2.1", "eth0"},
#   {"1.3.6.1.2.1.2.2.1.2.2", "eth1"},
#   ...
# ]
```

### Configuration System

```elixir
defmodule SNMP.Config do
  # Global defaults
  def set_default_community(community)
  def set_default_timeout(milliseconds)
  def set_default_retries(count)
  
  # MIB search paths
  def add_mib_path(directory)
  def set_mib_paths(directories)
end
```

### Success Criteria

- [ ] Standard MIBs compile and load
- [ ] Symbolic name resolution works
- [ ] Table operations handle real network devices
- [ ] Documentation with MIB examples

---

## 🔄 Phase 3: SNMPv2c & GETBULK (2-3 weeks)

### Protocol Version Support

```elixir
# Version-specific APIs
SNMP.get("device", "sysDescr.0", version: :v2c)
SNMP.get("device", "sysDescr.0", version: :v1)  # Explicit v1

# GETBULK operations (v2c only)
SNMP.get_bulk(target, oids, opts \\ [])
SNMP.get_bulk(target, root_oid, max_repetitions: 10, non_repeaters: 0)
```

### Bulk Operations

```elixir
defmodule SNMP.Bulk do
  # Single GETBULK request
  def get_bulk(target, oids, opts)
  
  # Optimized table retrieval
  def get_table_bulk(target, table_oid, opts)
  
  # Bulk walk (better than iterative GETNEXT)
  def walk_bulk(target, root_oid, opts)
end

# Usage examples:
SNMP.Bulk.get_bulk("switch", "ifTable", max_repetitions: 20)
# => {:ok, [
#   {"1.3.6.1.2.1.2.2.1.2.1", "eth0"},
#   {"1.3.6.1.2.1.2.2.1.2.2", "eth1"},
#   ...  # Up to 20 entries
# ]}
```

### Error Handling Improvements

```elixir
# Version-specific error handling
{:error, {:v2c_error, :too_big}}
{:error, {:v2c_error, :no_such_name, oid: "1.2.3.4.5"}}
{:error, {:protocol_error, :version_mismatch}}
```

### Performance Optimizations

```elixir
# Concurrent requests
SNMP.get_multi([
  {"device1", "sysDescr.0"},
  {"device2", "sysUpTime.0"},
  {"device3", "ifNumber.0"}
], timeout: 5000)
# => [
#   {:ok, "Device 1 Description"},
#   {:ok, 123456},
#   {:error, :timeout}
# ]
```

### Success Criteria

- [ ] SNMPv2c GETBULK significantly faster than GETNEXT
- [ ] Handles large tables efficiently  
- [ ] Proper error handling for v2c-specific errors
- [ ] Backward compatibility with v1

---

## 📊 Phase 4: Advanced Bulk Operations & Tables (3-4 weeks)

### Intelligent Bulk Walking

```elixir
defmodule SNMP.Walk do
  # Adaptive bulk walk - automatically adjusts repetitions
  def bulk_walk(target, root_oid, opts \\ [])
  
  # Table-optimized walking
  def table_walk(target, table_oid, opts \\ [])
  def indexed_table_walk(target, table_oid, index_column, opts \\ [])
  
  # Streaming walks for large tables
  def stream_walk(target, root_oid, opts \\ [])
  def stream_table(target, table_oid, opts \\ [])
end

# Usage:
SNMP.Walk.stream_table("core-switch", "ifTable")
|> Stream.filter(fn {oid, value} -> String.contains?(value, "GigabitEthernet") end)
|> Stream.map(&process_interface/1)
|> Enum.to_list()
```

### Table Processing Utilities

```elixir
defmodule SNMP.Table do
  # Convert flat OID list to structured table
  def to_table(oid_value_pairs, table_oid)
  def to_map(oid_value_pairs, key_column)
  def to_rows(oid_value_pairs)
  
  # Table analysis
  def get_indexes(table_data)
  def get_columns(table_data)
  def filter_by_index(table_data, index_filter)
end

# Example:
SNMP.get_table("router", "ifTable")
|> SNMP.Table.to_map("ifIndex")
# => %{
#   1 => %{ifDescr: "eth0", ifType: 6, ifSpeed: 1000000000},
#   2 => %{ifDescr: "eth1", ifType: 6, ifSpeed: 1000000000}
# }
```

### Adaptive Performance

```elixir
defmodule SNMP.Adaptive do
  # Auto-tune bulk parameters based on device response
  def optimize_bulk_size(target, table_oid)
  def benchmark_device(target)
  def get_optimal_params(target)
end
```

### Success Criteria

- [ ] Can walk 10,000+ entry tables efficiently
- [ ] Streaming API handles memory efficiently
- [ ] Adaptive performance tuning works
- [ ] Production-ready table processing

---

## 🌊 Phase 5: Streaming PDU Engine with Request Routing (4-5 weeks)

### Architecture Overview

```elixir
# Central request dispatcher and response router
defmodule SNMP.Engine do
  use GenServer
  
  # Manages UDP socket, request tracking, response routing
  def start_link(opts \\ [])
  def send_request(pid, target, pdu, caller_pid)
  def send_request_async(pid, target, pdu, callback)
end

# Request correlation and routing
defmodule SNMP.RequestTracker do
  # Tracks outstanding requests by request_id
  def register_request(request_id, caller_pid, target, timestamp)
  def route_response(request_id, response)
  def cleanup_expired_requests()
end
```

### Streaming API

```elixir
defmodule SNMP.Stream do
  @moduledoc """
  High-performance streaming SNMP operations
  """
  
  # Stream large walks without blocking
  def walk_stream(target, root_oid, opts \\ []) do
    Stream.resource(
      fn -> start_walk(target, root_oid, opts) end,
      fn state -> fetch_next_chunk(state) end,
      fn state -> cleanup_walk(state) end
    )
  end
  
  # Concurrent multi-device operations  
  def multi_device_stream(targets, operation, opts \\ [])
  
  # Real-time monitoring streams
  def monitor_stream(targets, oids, interval: 30_000)
end

# Usage:
devices = ["router1", "router2", "switch1", "switch2"]

SNMP.Stream.multi_device_stream(devices, {:get, "sysUpTime.0"})
|> Stream.each(&process_uptime/1)
|> Stream.run()

# Monitor interface utilization every 30 seconds
SNMP.Stream.monitor_stream(devices, ["ifInOctets", "ifOutOctets"], interval: 30_000)
|> Stream.each(&update_grafana_metrics/1)
|> Stream.run()
```

### Request Multiplexing

```elixir
defmodule SNMP.Multiplexer do
  # Single UDP socket handling multiple concurrent requests
  def start_link(socket_opts \\ [])
  
  # Request queuing and throttling
  def queue_request(request, priority: :normal)
  def set_rate_limit(requests_per_second)
  def set_concurrent_limit(max_concurrent)
  
  # Response correlation by request_id
  def route_response(response_packet, source_address)
end
```

### Advanced Features

```elixir
# Request pipelining - multiple requests without waiting
SNMP.Pipeline.new()
|> SNMP.Pipeline.add_request("device1", "sysDescr.0")
|> SNMP.Pipeline.add_request("device1", "sysUpTime.0") 
|> SNMP.Pipeline.add_request("device2", "ifNumber.0")
|> SNMP.Pipeline.execute()
# => [
#   {:ok, "Device 1 Description"},
#   {:ok, 123456},
#   {:ok, 24}
# ]

# Batch operations with automatic batching
SNMP.Batch.get_many([
  {"router1", ["sysDescr.0", "sysUpTime.0"]},
  {"router2", ["sysDescr.0", "sysUpTime.0"]},
  {"switch1", "ifTable"}
], max_concurrent: 10, timeout: 30_000)
```

### Success Criteria

- [ ] Handles 100+ concurrent requests
- [ ] Request/response correlation is reliable
- [ ] Memory usage remains constant under load
- [ ] Real-time monitoring use cases work

---

## 📦 Technical Implementation Strategy

### Leveraging Erlang SNMP Modules

**Pure Utility Modules (No Process Dependencies):**

#### ASN.1 Encoding/Decoding:
```elixir
# These work standalone:
:snmp_pdus.enc_message(msg)           # Encode SNMP message
:snmp_pdus.dec_message(bytes)         # Decode SNMP message  
:snmp_pdus.enc_pdu(pdu)               # Encode PDU
:snmp_pdus.dec_pdu(bytes)             # Decode PDU
```

#### MIB Compilation & Loading:
```elixir
:snmpc.compile("SNMPv2-MIB.mib")      # Compile MIB to binary
:snmpc.mib_to_hrl("SNMPv2-MIB")       # Generate Erlang headers
:snmp_misc.read_mib("compiled.bin")    # Load compiled MIB
```

#### OID Utilities:
```elixir
:snmp_misc.oid_to_string([1,3,6,1,2,1,1,1,0])  # => "1.3.6.1.2.1.1.1.0"
:snmp_misc.string_to_oid("1.3.6.1.2.1.1.1.0")  # => [1,3,6,1,2,1,1,1,0]
```

### Package Structure

```elixir
# Hex package structure
snmp_ex/
├── lib/
│   ├── snmp.ex              # Main API
│   ├── snmp/
│   │   ├── core.ex          # Core encoding/decoding
│   │   ├── mib.ex           # MIB operations  
│   │   ├── bulk.ex          # Bulk operations
│   │   ├── stream.ex        # Streaming API
│   │   ├── engine.ex        # PDU engine
│   │   └── table.ex         # Table utilities
├── test/
├── docs/
└── examples/
```

## 🎯 Market Opportunity

### Target Users
- **Network Engineers** - Monitoring tools, scripts
- **IoT Developers** - Device management platforms  
- **SRE Teams** - Infrastructure monitoring
- **Elixir Community** - Missing ecosystem piece

### Value Proposition
✅ **Developer Experience** - Clean, pipe-friendly Elixir API  
✅ **GenServer Integration** - Natural fit with OTP supervision trees  
✅ **LiveView Compatible** - Easy async operations for real-time UIs  
✅ **Network Monitoring** - Huge market need (Observability, IoT, Infrastructure)  
✅ **Learning Opportunity** - SNMP, ASN.1, UDP, binary protocols  

### Benefits of This Approach
- **🚀 Fast startup** - No process initialization
- **💾 Low memory** - No persistent state/caches  
- **🔧 Simple deployment** - Just add dependency
- **⚡ Direct control** - UDP sockets, timeouts, retries
- **🎯 Focused** - Only the parts you need
- **🔄 Reuse proven code** - Leverage Erlang's 20+ years of SNMP work

---

## 🚀 Getting Started

This roadmap creates a foundation for a production-ready SNMP library that would be both powerful and easy to use. The phased approach allows for incremental development and validation against real-world use cases.

**Next Steps:**
1. Begin with Phase 1 implementation
2. Validate against cable modem simulator
3. Gather community feedback on API design
4. Iterate and expand based on real-world usage

**Potential Package Names:**
- `snmp_ex` - Simple, clear
- `elixir_snmp` - Descriptive
- `snmp_client` - Focused on client operations

This library could become a significant contribution to the Elixir ecosystem, filling a crucial gap in network management tooling.