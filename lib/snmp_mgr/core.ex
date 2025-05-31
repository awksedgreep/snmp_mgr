defmodule SNMPMgr.Core do
  @moduledoc """
  Core SNMP operations using Erlang's SNMP PDU functions directly.
  
  This module handles the low-level SNMP PDU encoding/decoding and UDP communication
  without requiring the heavyweight :snmpm manager process.
  """

  @default_community "public"
  @default_timeout 5000
  @default_retries 1

  @doc """
  Sends an SNMP GET request and returns the response.
  """
  def send_get_request(target, oid, opts \\ []) do
    with {:ok, target_info} <- SNMPMgr.Target.parse(target),
         {:ok, oid_list} <- parse_oid(oid),
         {:ok, pdu} <- build_get_pdu(oid_list, opts),
         {:ok, message} <- encode_message(pdu, opts),
         {:ok, response} <- send_receive_udp(target_info, message, opts) do
      decode_get_response(response)
    else
      error -> error
    end
  end

  @doc """
  Sends an SNMP GETNEXT request and returns the response.
  """
  def send_get_next_request(target, oid, opts \\ []) do
    with {:ok, target_info} <- SNMPMgr.Target.parse(target),
         {:ok, oid_list} <- parse_oid(oid),
         {:ok, pdu} <- build_get_next_pdu(oid_list, opts),
         {:ok, message} <- encode_message(pdu, opts),
         {:ok, response} <- send_receive_udp(target_info, message, opts) do
      decode_get_next_response(response)
    else
      error -> error
    end
  end

  @doc """
  Sends an SNMP SET request and returns the response.
  """
  def send_set_request(target, oid, value, opts \\ []) do
    with {:ok, target_info} <- SNMPMgr.Target.parse(target),
         {:ok, oid_list} <- parse_oid(oid),
         {:ok, typed_value} <- SNMPMgr.Types.encode_value(value, opts),
         {:ok, pdu} <- build_set_pdu(oid_list, typed_value, opts),
         {:ok, message} <- encode_message(pdu, opts),
         {:ok, response} <- send_receive_udp(target_info, message, opts) do
      decode_set_response(response)
    else
      error -> error
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
      with {:ok, target_info} <- SNMPMgr.Target.parse(target),
           {:ok, oid_list} <- parse_oid(oid),
           {:ok, pdu} <- build_get_bulk_pdu(oid_list, opts),
           {:ok, message} <- encode_message(pdu, opts),
           {:ok, response} <- send_receive_udp(target_info, message, opts) do
        decode_get_bulk_response(response)
      else
        error -> error
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

  # Private functions

  defp build_get_pdu(oid_list, _opts) do
    request_id = :rand.uniform(1000000)
    pdu = SNMPMgr.PDU.build_get_request(oid_list, request_id)
    {:ok, pdu}
  end

  defp build_get_next_pdu(oid_list, _opts) do
    request_id = :rand.uniform(1000000)
    pdu = SNMPMgr.PDU.build_get_next_request(oid_list, request_id)
    {:ok, pdu}
  end

  defp build_set_pdu(oid_list, {type, value}, _opts) do
    request_id = :rand.uniform(1000000)
    pdu = SNMPMgr.PDU.build_set_request(oid_list, {type, value}, request_id)
    {:ok, pdu}
  end

  defp build_get_bulk_pdu(oid_list, opts) do
    request_id = :rand.uniform(1000000)
    non_repeaters = Keyword.get(opts, :non_repeaters, 0)
    max_repetitions = Keyword.get(opts, :max_repetitions, 10)
    pdu = SNMPMgr.PDU.build_get_bulk_request(oid_list, request_id, non_repeaters, max_repetitions)
    {:ok, pdu}
  end

  defp encode_message(pdu, opts) do
    community = Keyword.get(opts, :community, @default_community)
    version = Keyword.get(opts, :version, :v1)
    message = SNMPMgr.PDU.build_message(pdu, community, version)
    SNMPMgr.PDU.encode_message(message)
  end

  defp send_receive_udp(target_info, message, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @default_retries)
    
    send_receive_udp_with_retries(target_info, message, timeout, retries)
  end

  defp send_receive_udp_with_retries(target_info, message, timeout, retries) do
    case do_send_receive_udp(target_info, message, timeout) do
      {:ok, response} -> {:ok, response}
      {:error, :timeout} when retries > 0 ->
        send_receive_udp_with_retries(target_info, message, timeout, retries - 1)
      error -> error
    end
  end

  defp do_send_receive_udp(%{host: host, port: port}, message, timeout) do
    case :gen_udp.open(0, [:binary, {:active, false}]) do
      {:ok, socket} ->
        try do
          case :gen_udp.send(socket, host, port, message) do
            :ok ->
              case :gen_udp.recv(socket, 0, timeout) do
                {:ok, {_host, _port, response}} -> {:ok, response}
                {:error, :timeout} -> {:error, :timeout}
                {:error, reason} -> {:error, {:network_error, reason}}
              end
            {:error, reason} -> {:error, {:network_error, reason}}
          end
        after
          :gen_udp.close(socket)
        end
      {:error, reason} -> {:error, {:socket_error, reason}}
    end
  end

  defp decode_get_response(response) do
    case SNMPMgr.PDU.decode_message(response) do
      {:ok, %{data: %{type: :get_response, varbinds: varbinds, error_status: error_status}}} ->
        case error_status do
          0 ->
            case varbinds do
              [{_oid, _type, value}] -> {:ok, decode_value(value)}
              _ -> {:error, :invalid_response}
            end
          error -> {:error, {:snmp_error, error}}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_get_next_response(response) do
    case SNMPMgr.PDU.decode_message(response) do
      {:ok, %{data: %{type: :get_response, varbinds: varbinds, error_status: error_status}}} ->
        case error_status do
          0 ->
            case varbinds do
              [{oid, _type, value}] -> 
                oid_string = SNMPMgr.OID.list_to_string(oid)
                {:ok, {oid_string, decode_value(value)}}
              _ -> {:error, :invalid_response}
            end
          error -> {:error, {:snmp_error, error}}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_set_response(response) do
    case SNMPMgr.PDU.decode_message(response) do
      {:ok, %{data: %{type: :get_response, varbinds: varbinds, error_status: error_status}}} ->
        case error_status do
          0 ->
            case varbinds do
              [{_oid, _type, value}] -> {:ok, decode_value(value)}
              _ -> {:error, :invalid_response}
            end
          error -> {:error, {:snmp_error, error}}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_get_bulk_response(response) do
    case SNMPMgr.PDU.decode_message(response) do
      {:ok, %{data: %{type: :get_response, varbinds: varbinds, error_status: error_status}}} ->
        case error_status do
          0 ->
            results = 
              varbinds
              |> Enum.map(fn {oid, _type, value} ->
                oid_string = SNMPMgr.OID.list_to_string(oid)
                {oid_string, decode_value(value)}
              end)
              |> Enum.filter(fn {_oid, value} -> 
                # Filter out end-of-mib-view and other special values
                value != :endOfMibView and value != :noSuchObject and value != :noSuchInstance
              end)
            {:ok, results}
          error -> {:error, {:snmp_error, error}}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_value(:noSuchObject), do: nil
  defp decode_value(:noSuchInstance), do: nil
  defp decode_value(:endOfMibView), do: nil
  defp decode_value(value), do: value

  defp parse_oid(oid_string) when is_binary(oid_string) do
    case SNMPMgr.OID.string_to_list(oid_string) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, _} -> {:error, {:invalid_oid, oid_string}}
    end
  end
  defp parse_oid(oid_list) when is_list(oid_list), do: {:ok, oid_list}
  defp parse_oid(_), do: {:error, :invalid_oid_format}
end