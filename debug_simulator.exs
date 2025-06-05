#!/usr/bin/env elixir

# Debug script to test SNMP simulator capabilities  
Code.put_path("_build/test/lib/snmp_mgr/ebin")
Code.put_path("test")
Application.ensure_all_started(:snmp_mgr)

# Create test device
{:ok, device} = SnmpMgr.TestSupport.SNMPSimulator.create_test_device()
target = "#{device.host}:#{device.port}"

IO.puts("=== Testing SNMP Simulator Data Availability ===")
IO.puts("Target: #{target}")
IO.puts("Community: #{device.community}")
IO.puts("")

# Test specific leaf nodes that should work
test_cases = [
  {"GET 1.3.6.1.2.1.1.1.0 (sysDescr.0)", fn -> 
    SnmpMgr.get(target, "1.3.6.1.2.1.1.1.0", community: device.community, timeout: 200)
  end},
  {"GET 1.3.6.1.2.1.1.3.0 (sysUpTime.0)", fn -> 
    SnmpMgr.get(target, "1.3.6.1.2.1.1.3.0", community: device.community, timeout: 200)
  end},
  {"GET 1.3.6.1.2.1.1.5.0 (sysName.0)", fn -> 
    SnmpMgr.get(target, "1.3.6.1.2.1.1.5.0", community: device.community, timeout: 200)
  end},
  {"GET-NEXT 1.3.6.1.2.1.1.1", fn -> 
    SnmpMgr.get_next(target, "1.3.6.1.2.1.1.1", community: device.community, timeout: 200)
  end},
  {"WALK 1.3.6.1.2.1.1.1 (sysDescr subtree)", fn -> 
    SnmpMgr.walk(target, "1.3.6.1.2.1.1.1", community: device.community, timeout: 200)
  end},
  {"WALK 1.3.6.1.2.1.1 (system group)", fn -> 
    SnmpMgr.walk(target, "1.3.6.1.2.1.1", community: device.community, timeout: 200)
  end}
]

for {description, operation} <- test_cases do
  IO.puts("#{description}:")
  case operation.() do
    {:ok, result} -> 
      IO.puts("  ✓ SUCCESS: #{inspect(result)}")
    {:error, reason} -> 
      IO.puts("  ✗ FAILED: #{inspect(reason)}")
  end
  IO.puts("")
end

# Clean up
SnmpMgr.TestSupport.SNMPSimulator.stop_device(device)
IO.puts("=== Analysis Complete ===")