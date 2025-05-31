defmodule SNMPMgr.PDU do
  @moduledoc """
  SNMP PDU (Protocol Data Unit) encoding and decoding.
  
  Supports both SNMPv1 and SNMPv2c protocols including GETBULK operations.
  Leverages Erlang's SNMP modules when available, with basic fallback implementation.
  """

  @doc """
  Creates a basic SNMP GET request PDU structure.
  """
  def build_get_request(oid_list, request_id) do
    %{
      type: :get_request,
      request_id: request_id,
      error_status: 0,
      error_index: 0,
      varbinds: [{oid_list, :null, :null}]
    }
  end

  @doc """
  Creates a basic SNMP GETNEXT request PDU structure.
  """
  def build_get_next_request(oid_list, request_id) do
    %{
      type: :get_next_request,
      request_id: request_id,
      error_status: 0,
      error_index: 0,
      varbinds: [{oid_list, :null, :null}]
    }
  end

  @doc """
  Creates a basic SNMP SET request PDU structure.
  """
  def build_set_request(oid_list, {type, value}, request_id) do
    %{
      type: :set_request,
      request_id: request_id,
      error_status: 0,
      error_index: 0,
      varbinds: [{oid_list, type, value}]
    }
  end

  @doc """
  Creates a basic SNMP GETBULK request PDU structure for SNMPv2c.
  """
  def build_get_bulk_request(oid_list, request_id, non_repeaters \\ 0, max_repetitions \\ 10) do
    %{
      type: :get_bulk_request,
      request_id: request_id,
      non_repeaters: non_repeaters,
      max_repetitions: max_repetitions,
      varbinds: [{oid_list, :null, :null}]
    }
  end

  @doc """
  Creates a basic SNMP message structure with version support.
  """
  def build_message(pdu, community, version \\ :v1) do
    version_number = case version do
      :v1 -> 0
      :v2c -> 1
      _ -> 0
    end
    
    %{
      version: version_number,
      community: community,
      data: pdu
    }
  end

  @doc """
  Attempts to encode an SNMP message using Erlang's SNMP modules if available.
  Falls back to error if not available (Phase 1 limitation).
  """
  def encode_message(message) do
    try do
      # Try to use Erlang's SNMP encoder if available
      case Code.ensure_loaded(:snmp_pdus) do
        {:module, :snmp_pdus} ->
          encoded = :snmp_pdus.enc_message(message)
          {:ok, encoded}
        {:error, _} ->
          {:error, :snmp_modules_not_available}
      end
    catch
      error -> {:error, {:encoding_error, error}}
    end
  end

  @doc """
  Attempts to decode an SNMP response using Erlang's SNMP modules if available.
  """
  def decode_message(response) do
    try do
      case Code.ensure_loaded(:snmp_pdus) do
        {:module, :snmp_pdus} ->
          decoded = :snmp_pdus.dec_message(response)
          {:ok, decoded}
        {:error, _} ->
          {:error, :snmp_modules_not_available}
      end
    catch
      error -> {:error, {:decoding_error, error}}
    end
  end
end