defmodule SnmpMgr.SetInvestigationTest do
  use ExUnit.Case, async: false

  alias SnmpMgr.TestSupport.SNMPSimulator
  alias SnmpLib.Manager # For direct calls

  setup do
    case SNMPSimulator.create_test_device() do
      {:ok, device} ->
        :ok = SNMPSimulator.wait_for_device_ready(device)
        on_exit(fn -> SNMPSimulator.stop_device(device) end)
        %{device: device}
      {:error, reason} ->
        # If simulator setup fails, skip tests in this module
        {:skip, %{reason: "SNMP simulator setup failed: #{inspect(reason)}"}}
    end
  end

  test "investigate SET operation on sysLocation.0 with SnmpLib.Manager.set/4", %{device: device} do
    # Host identifier should be an Erlang IP tuple e.g. {127,0,0,1} or a hostname charlist
    charlist_host = String.to_charlist(device.host)
    {:ok, erlang_ip_address} = :inet.parse_address(charlist_host)
    # erlang_ip_address is now like {127,0,0,1}

    community_string = device.community
    port_number = device.port
    oid_to_set = "1.3.6.1.2.1.1.6.0" # sysLocation.0
    value_to_set = "new_investigation_location"
    type_of_value = :string

    IO.puts("Attempting SnmpLib.Manager.set/4 with:")
    IO.inspect(host: erlang_ip_address, port: port_number, community: community_string, oid: oid_to_set, value: value_to_set, type: type_of_value)

    # SnmpLib.Manager.set/4 likely expects:
    # set(host_identifier, oid_string, {type_atom, value}, options_list_including_port_and_community)
    
    opts = [
      port: port_number,
      community: community_string,
      version: :v2c, 
      timeout: 2000, 
      retries: 0
    ]

    result = Manager.set(erlang_ip_address, oid_to_set, {type_of_value, value_to_set}, opts)

    IO.puts("Raw result from SnmpLib.Manager.set/4:")
    IO.inspect(result, label: "SnmpLib.Manager.set result")

    # For now, we just want to observe. The actual success/failure depends on snmp_sim's behavior.
    # If it's :gen_err, this test will help confirm it comes directly from snmp_lib (forwarding snmp_sim's response).
    assert true # Placeholder assertion for observation
  end
end
