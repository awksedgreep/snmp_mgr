ExUnit.start()

# Ensure test support modules are compiled
Code.require_file("support/snmp_simulator.ex", __DIR__)

# Start SNMPSimEx for all tests that need it
case Application.ensure_all_started(:snmp_sim_ex) do
  {:ok, _} -> 
    IO.puts("SNMPSimEx available for testing")
  {:error, _} -> 
    IO.puts("SNMPSimEx not available - some tests may be skipped")
    ExUnit.configure(exclude: [:needs_simulator])
end
