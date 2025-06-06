ExUnit.start()

require Logger

Logger.configure(level: :error)

# Ensure test support modules are compiled
Code.require_file("support/snmp_simulator.ex", __DIR__)

# Start SnmpSim for all tests that need it
case Application.ensure_all_started(:snmp_sim_ex) do
  {:ok, _} ->
    IO.puts("SnmpSim available for testing")
  {:error, _} ->
    IO.puts("SnmpSim not available - some tests may be skipped")
    ExUnit.configure(exclude: [:needs_simulator])
end
