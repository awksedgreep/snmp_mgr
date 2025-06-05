#!/usr/bin/env elixir

Mix.install([
  {:snmp_sim_ex, path: "../snmp_sim_ex"},
  {:snmp_mgr, path: "."}
])

# Start the simulator application if needed
Application.ensure_all_started(:snmp_sim_ex)
Application.ensure_all_started(:snmp_mgr)

# Start a simple device
{:ok, device} = SnmpMgr.TestSupport.SNMPSimulator.create_test_device(port: 30001)

# Give it a moment to start
Process.sleep(1000)

# Test various OIDs
target = "#{device.host}:#{device.port}"
IO.puts("Testing device at #{target}")

test_oids = [
  {"sysDescr", "1.3.6.1.2.1.1.1.0"},
  {"sysObjectID", "1.3.6.1.2.1.1.2.0"},
  {"sysUpTime", "1.3.6.1.2.1.1.3.0"},
  {"sysContact", "1.3.6.1.2.1.1.4.0"},
  {"sysName", "1.3.6.1.2.1.1.5.0"},
  {"sysLocation", "1.3.6.1.2.1.1.6.0"},
  {"ifNumber", "1.3.6.1.2.1.2.1.0"},
  {"ifIndex.1", "1.3.6.1.2.1.2.2.1.1.1"},
  {"ifDescr.1", "1.3.6.1.2.1.2.2.1.2.1"}
]

for {name, oid} <- test_oids do
  case SnmpMgr.get(target, oid, community: device.community, timeout: 2000) do
    {:ok, value} -> 
      IO.puts("✓ #{name} (#{oid}) = #{inspect(value)}")
    {:error, reason} -> 
      IO.puts("✗ #{name} (#{oid}) failed: #{inspect(reason)}")
  end
  Process.sleep(100)
end

# Clean up
SnmpMgr.TestSupport.SNMPSimulator.stop_device(device)