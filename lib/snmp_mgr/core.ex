defmodule SnmpMgr.Core do
  @moduledoc """
  Core SNMP operations using Erlang's SNMP PDU functions directly.

  This module handles the low-level SNMP PDU encoding/decoding and UDP communication
  without requiring the heavyweight :snmpm manager process.
  """

  @type snmp_result :: {:ok, term()} | {:error, atom() | tuple()}
  @type target :: binary() | tuple() | map()
  @type oid :: binary() | list(non_neg_integer())
  @type opts :: keyword()

  @doc """
  Sends an SNMP GET request and returns the response.
  """
  @spec send_get_request(target(), oid(), opts()) :: snmp_result()
  def send_get_request(target, oid, opts \\ []) do
    # Parse target to extract host and port
    {host, updated_opts} = case SnmpMgr.Target.parse(target) do
      {:ok, %{host: host, port: port}} ->
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {host, opts_with_port}
      {:error, _reason} ->
        # Failed to parse, use as-is
        {target, opts}
    end

    # Convert oid to proper format
    oid_parsed = case parse_oid(oid) do
      {:ok, oid_list} -> oid_list
      {:error, _} -> oid
    end

    # Map options to snmp_lib format
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)

    # Use SnmpLib.Manager for the actual operation
    try do
      case SnmpLib.Manager.get(host, oid_parsed, snmp_lib_opts) do
        {:ok, value} -> {:ok, value}
        {:error, reason} -> {:error, map_error_from_snmp_lib(reason)}
      end
    rescue
      e in [RuntimeError, ErlangError] -> {:error, {:exception, e}}
    end
  end

  @doc """
  Sends a GETNEXT request to retrieve the next OID in the MIB tree.
  
  Now uses the proper SnmpLib.Manager.get_next/3 function which handles
  version-specific logic (GETNEXT for v1, GETBULK for v2c+) correctly.
  """
  @spec send_get_next_request(target(), oid(), opts()) :: snmp_result()
  def send_get_next_request(target, oid, opts \\ []) do
    # Parse target to extract host and port
    {host, updated_opts} = case SnmpMgr.Target.parse(target) do
      {:ok, %{host: host, port: port}} -> 
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {host, opts_with_port}
      {:error, _reason} -> 
        # Failed to parse, use as-is
        {target, opts}
    end
    
    # Convert oid to proper format
    oid_parsed = case parse_oid(oid) do
      {:ok, oid_list} -> oid_list
      {:error, _} -> oid
    end
    
    # Map options to snmp_lib format
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)
    
    # Use the new SnmpLib.Manager.get_next function which properly handles version logic
    try do
      case SnmpLib.Manager.get_next(host, oid_parsed, snmp_lib_opts) do
        {:ok, {next_oid, value}} -> {:ok, {next_oid, value}}
        {:error, reason} -> {:error, map_error_from_snmp_lib(reason)}
      end
    rescue
      error in [RuntimeError, ErlangError] ->
        {:error, {:exception, Exception.message(error)}}
    end
  end

  @doc """
  Sends an SNMP SET request and returns the response.
  """
  @spec send_set_request(target(), oid(), term(), opts()) :: snmp_result()
  def send_set_request(target, oid, value, opts \\ []) do
    # Parse target to extract host and port
    {host, updated_opts} = case SnmpMgr.Target.parse(target) do
      {:ok, %{host: host, port: port}} ->
        # Use parsed port, overriding any default
        opts_with_port = Keyword.put(opts, :port, port)
        {host, opts_with_port}
      {:error, _reason} ->
        # Failed to parse, use as-is
        {target, opts}
    end

    # Convert oid to proper format
    oid_parsed = case parse_oid(oid) do
      {:ok, oid_list} -> oid_list
      {:error, _} -> oid
    end

    # Convert value to snmp_lib format
    typed_value = case SnmpMgr.Types.encode_value(value, opts) do
      {:ok, tv} -> tv
      {:error, _} -> value
    end

    # Map options to snmp_lib format
    snmp_lib_opts = map_options_to_snmp_lib(updated_opts)

    # Use SnmpLib.Manager for the actual operation
    try do
      case SnmpLib.Manager.set(host, oid_parsed, typed_value, snmp_lib_opts) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, map_error_from_snmp_lib(reason)}
      end
    rescue
      e in [RuntimeError, ErlangError] -> {:error, {:exception, e}}
    end
  end

  @doc """
  Sends an SNMP GETBULK request (SNMPv2c only).
  """
  @spec send_get_bulk_request(target(), oid(), opts()) :: snmp_result()
  def send_get_bulk_request(target, oid, opts \\ []) do
    version = Keyword.get(opts, :version, :v2c)

    case version do
      :v2c ->
        # Parse target to extract host and port
        {host, updated_opts} = case SnmpMgr.Target.parse(target) do
          {:ok, %{host: host, port: port}} ->
            # Use parsed port, overriding any default
            opts_with_port = Keyword.put(opts, :port, port)
            {host, opts_with_port}
          {:error, _reason} ->
            # Failed to parse, use as-is
            {target, opts}
        end

        # Convert oid to proper format
        oid_parsed = case parse_oid(oid) do
          {:ok, oid_list} -> oid_list
          {:error, _} -> oid
        end

        # Map options to snmp_lib format
        snmp_lib_opts = map_options_to_snmp_lib(updated_opts)

        # Use SnmpLib.Manager for the actual operation
        try do
          case SnmpLib.Manager.get_bulk(host, oid_parsed, snmp_lib_opts) do
            {:ok, results} -> 
              # Process the results to extract varbinds in 3-tuple format
              processed_results = case results do
                # Map format (snmp_lib v1.0.5+)
                %{"varbinds" => varbinds} when is_list(varbinds) ->
                  varbinds
                
                # Direct list format (older versions)
                results when is_list(results) ->
                  results
                
                # Other formats
                _other ->
                  []
              end
              
              {:ok, processed_results}
            {:error, reason} -> {:error, map_error_from_snmp_lib(reason)}
          end
        rescue
          e in [RuntimeError, ErlangError] -> {:error, {:exception, e}}
        end

      _ ->
        {:error, :getbulk_requires_v2c}
    end
  end

  @doc """
  Sends an asynchronous SNMP GET request.
  """
  @spec send_get_request_async(target(), oid(), opts()) :: reference()
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
  @spec send_get_bulk_request_async(target(), oid(), opts()) :: reference()
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

  @spec map_options_to_snmp_lib(opts()) :: list()
  defp map_options_to_snmp_lib(opts) do
    # Map SnmpMgr options to SnmpLib.Manager options
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

  @spec map_error_from_snmp_lib(term()) :: term()
  defp map_error_from_snmp_lib(reason) do
    # Map SnmpLib errors back to SnmpMgr error format for backward compatibility
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
      {:snmp_error, code} -> {:snmp_error, code}
      other -> other
    end
  end

  @doc """
  Parses and normalizes an OID using SnmpLib.OID.normalize with MIB support.
  """
  @spec parse_oid(oid()) :: {:ok, list(non_neg_integer())} | {:error, term()}
  def parse_oid(oid) do
    # Try MIB registry first for symbolic names like "sysDescr.0"
    case try_mib_resolution(oid) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, _} ->
        # Fall back to basic OID parsing for numeric strings and lists
        case SnmpLib.OID.normalize(oid) do
          {:ok, oid_list} -> {:ok, oid_list}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Private helper to try MIB resolution first
  @spec try_mib_resolution(oid()) :: {:ok, list(non_neg_integer())} | {:error, term()}
  defp try_mib_resolution(oid) when is_binary(oid) do
    # First try MIB registry resolution for symbolic names
    SnmpLib.MIB.Registry.resolve_name(oid)
  end
  defp try_mib_resolution(oid) when is_list(oid) do
    # For lists, validate directly
    case SnmpLib.OID.valid_oid?(oid) do
      :ok -> {:ok, oid}
      error -> error
    end
  end
  defp try_mib_resolution(_), do: {:error, :invalid_input}
end
