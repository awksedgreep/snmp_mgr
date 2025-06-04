defmodule SNMPMgr.Core do
  @moduledoc """
  Core SNMP operations using Erlang's SNMP PDU functions directly.
  
  This module handles the low-level SNMP PDU encoding/decoding and UDP communication
  without requiring the heavyweight :snmpm manager process.
  """


  @doc """
  Sends an SNMP GET request and returns the response.
  """
  def send_get_request(target, oid, opts \\ []) do
    # Parse target to extract host and port
    {host, updated_opts} = case SNMPMgr.Target.parse(target) do
      {:ok, %{host: host, port: port}} -> 
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {host, opts_with_port}
      {:ok, %{address: address, port: port}} -> 
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {address, opts_with_port}
      _ -> 
        # Failed to parse, use as-is
        {target, opts}
    end
    
    # Convert oid to proper format
    oid_parsed = case parse_oid(oid) do
      {:ok, oid_list} -> oid_list
      _ -> oid
    end
    
    # Map options to snmp_lib format
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)
    
    # Use SnmpLib.Manager for the actual operation
    case SnmpLib.Manager.get(host, oid_parsed, snmp_lib_opts) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, map_error_from_snmp_lib(reason)}
    end
  end

  @doc """
  Sends an SNMP GETNEXT request and returns the response.
  Note: SnmpLib.Manager doesn't have direct GETNEXT support, so we fall back to bulk with max_repetitions=1
  """
  def send_get_next_request(target, oid, opts \\ []) do
    # Parse target to extract host and port
    {host, updated_opts} = case SNMPMgr.Target.parse(target) do
      {:ok, %{host: host, port: port}} -> 
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {host, opts_with_port}
      {:ok, %{address: address, port: port}} -> 
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {address, opts_with_port}
      _ -> 
        # Failed to parse, use as-is
        {target, opts}
    end
    
    # Convert oid to proper format
    oid_parsed = case parse_oid(oid) do
      {:ok, oid_list} -> oid_list
      _ -> oid
    end
    
    # Map options to snmp_lib format and force max_repetitions=1 for GETNEXT behavior
    # Also force version to :v2c since we're using get_bulk
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)
    snmp_lib_opts = [{:max_repetitions, 1}, {:version, :v2c} | snmp_lib_opts]
    
    # Use SnmpLib.Manager.get_bulk with single repetition to simulate GETNEXT
    case SnmpLib.Manager.get_bulk(host, oid_parsed, snmp_lib_opts) do
      {:ok, [result]} -> {:ok, result}  # Extract single result
      {:ok, results} when is_list(results) -> {:ok, List.first(results)}
      {:error, reason} -> {:error, map_error_from_snmp_lib(reason)}
    end
  end

  @doc """
  Sends an SNMP SET request and returns the response.
  """
  def send_set_request(target, oid, value, opts \\ []) do
    # Parse target to extract host and port
    {host, updated_opts} = case SNMPMgr.Target.parse(target) do
      {:ok, %{host: host, port: port}} -> 
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {host, opts_with_port}
      {:ok, %{address: address, port: port}} -> 
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {address, opts_with_port}
      _ -> 
        # Failed to parse, use as-is
        {target, opts}
    end
    
    # Convert oid to proper format
    oid_parsed = case parse_oid(oid) do
      {:ok, oid_list} -> oid_list
      _ -> oid
    end
    
    # Convert value to snmp_lib format
    typed_value = case SNMPMgr.Types.encode_value(value, opts) do
      {:ok, tv} -> tv
      _ -> value
    end
    
    # Map options to snmp_lib format
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)
    
    # Use SnmpLib.Manager for the actual operation
    case SnmpLib.Manager.set(host, oid_parsed, typed_value, snmp_lib_opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, map_error_from_snmp_lib(reason)}
    end
  end

  @doc """
  Sends an SNMP GETBULK request (SNMPv2c only).
  """
  def send_get_bulk_request(target, oid, opts \\ []) do
    version = Keyword.get(opts, :version, :v2c)
    if version != :v2c do
      {:error, {:unsupported_operation, :get_bulk_requires_v2c}}
    else
      # Parse target to extract host and port
      {host, updated_opts} = case SNMPMgr.Target.parse(target) do
        {:ok, %{host: host, port: port}} -> 
          # Use parsed port, overriding any default
          opts_with_port = Keyword.put(opts, :port, port)
          {host, opts_with_port}
        {:ok, %{address: address, port: port}} -> 
          # Use parsed port, overriding any default
          opts_with_port = Keyword.put(opts, :port, port)
          {address, opts_with_port}
        _ -> 
          # Failed to parse, use as-is
          {target, opts}
      end
      
      # Convert oid to proper format
      oid_parsed = case parse_oid(oid) do
        {:ok, oid_list} -> oid_list
        _ -> oid
      end
      
      # Map options to snmp_lib format
      snmp_lib_opts = map_options_to_snmp_lib(updated_opts)
      
      # Use SnmpLib.Manager for the actual operation
      case SnmpLib.Manager.get_bulk(host, oid_parsed, snmp_lib_opts) do
        {:ok, results} -> {:ok, results}
        {:error, reason} -> {:error, map_error_from_snmp_lib(reason)}
      end
    end
  end

  @doc """
  Sends an asynchronous SNMP GET request.
  """
  def send_get_request_async(target, oid, opts \\ []) do
    caller = self()
    ref = make_ref()
    
    spawn(fn ->
      result = send_get_request(target, oid, opts)
      send(caller, {ref, result})
    end)
    
    ref
  end

  @doc """
  Sends an asynchronous SNMP GETBULK request.
  """
  def send_get_bulk_request_async(target, oid, opts \\ []) do
    caller = self()
    ref = make_ref()
    
    spawn(fn ->
      result = send_get_bulk_request(target, oid, opts)
      send(caller, {ref, result})
    end)
    
    ref
  end

  # Private functions for snmp_lib integration

  defp map_options_to_snmp_lib(opts) do
    # Map SNMPMgr options to SnmpLib.Manager options
    mapped = []
    
    mapped = if community = Keyword.get(opts, :community), do: [{:community, community} | mapped], else: mapped
    mapped = if timeout = Keyword.get(opts, :timeout), do: [{:timeout, timeout} | mapped], else: mapped
    mapped = if retries = Keyword.get(opts, :retries), do: [{:retries, retries} | mapped], else: mapped
    mapped = if version = Keyword.get(opts, :version), do: [{:version, version} | mapped], else: mapped
    mapped = if port = Keyword.get(opts, :port), do: [{:port, port} | mapped], else: mapped
    mapped = if max_repetitions = Keyword.get(opts, :max_repetitions), do: [{:max_repetitions, max_repetitions} | mapped], else: mapped
    mapped = if non_repeaters = Keyword.get(opts, :non_repeaters), do: [{:non_repeaters, non_repeaters} | mapped], else: mapped
    
    mapped
  end
  
  defp map_error_from_snmp_lib(reason) do
    # Map SnmpLib errors back to SNMPMgr error format for backward compatibility
    case reason do
      :timeout -> :timeout
      :host_unreachable -> :host_unreachable
      :network_unreachable -> :network_unreachable
      :connection_refused -> :connection_refused
      :invalid_community -> :authentication_error
      :decode_error -> :decode_error
      :no_such_name -> :no_such_name
      :no_such_object -> :no_such_object
      :no_such_instance -> :no_such_instance
      :invalid_input -> :gen_err  # Map genErr (status 5) to proper SNMP error
      {:snmp_error, code} -> {:snmp_error, code}
      other -> other
    end
  end

  @doc """
  Parses and normalizes an OID using SnmpLib.OID.normalize.
  """
  def parse_oid(oid) do
    # Use SnmpLib.OID.normalize which handles both string and list inputs
    # and provides comprehensive validation and normalization
    case SnmpLib.OID.normalize(oid) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, reason} -> {:error, reason}
    end
  end
end
