defmodule SNMPMgr.PDU do
  @moduledoc """
  SNMP PDU (Protocol Data Unit) encoding and decoding.
  
  Supports both SNMPv1 and SNMPv2c protocols including GETBULK operations.
  Leverages Erlang's SNMP modules when available, with basic fallback implementation.
  """

  alias SNMPMgr.OID

  @doc """
  Creates a basic SNMP GET request PDU structure.
  """
  def build_get_request(oid_list, request_id) do
    normalized_oid = normalize_oid(oid_list)
    %{
      type: :get_request,
      request_id: request_id,
      error_status: :noError,
      error_index: 0,
      varbinds: [{normalized_oid, :null, :null}]
    }
  end

  @doc """
  Creates a basic SNMP GETNEXT request PDU structure.
  """
  def build_get_next_request(oid_list, request_id) do
    normalized_oid = normalize_oid(oid_list)
    %{
      type: :get_next_request,
      request_id: request_id,
      error_status: :noError,
      error_index: 0,
      varbinds: [{normalized_oid, :null, :null}]
    }
  end

  @doc """
  Creates a basic SNMP SET request PDU structure.
  """
  def build_set_request(oid_list, {type, value}, request_id) do
    normalized_oid = normalize_oid(oid_list)
    %{
      type: :set_request,
      request_id: request_id,
      error_status: :noError,
      error_index: 0,
      varbinds: [{normalized_oid, type, value}]
    }
  end

  @doc """
  Creates a basic SNMP GETBULK request PDU structure for SNMPv2c.
  """
  def build_get_bulk_request(oid_list, request_id, non_repeaters \\ 0, max_repetitions \\ 10) do
    normalized_oid = normalize_oid(oid_list)
    %{
      type: :get_bulk_request,
      request_id: request_id,
      non_repeaters: non_repeaters,
      max_repetitions: max_repetitions,
      varbinds: [{normalized_oid, :null, :null}]
    }
  end

  @doc """
  Creates a basic SNMP message structure with version support.
  """
  def build_message(pdu, community, version \\ :v1) do
    # Use the exact version atoms that Erlang's enc_version/1 expects
    version_atom = case version do
      :v1 -> :"version-1"
      :v2c -> :"version-2"  
      :v2 -> :"version-2"   # v2 is same as v2c
      :v3 -> :"version-3"
      _ -> :"version-1"
    end
    
    # Build proper Erlang record for message
    # Based on snmp_types.hrl: -record(message, {version, vsn_hdr, data})
    # For v1/v2c: vsn_hdr is community string, data is PDU
    message_record = {:message, version_atom, community, convert_pdu_to_record(pdu)}
    message_record
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
          # Try different decoding approaches
          case try_decode_approaches(response) do
            {:ok, decoded} -> {:ok, decoded}
            {:error, reason} -> {:error, reason}
          end
        {:error, _} ->
          {:error, :snmp_modules_not_available}
      end
    catch
      error -> {:error, {:decoding_error, error}}
    end
  end
  
  # Try multiple decoding approaches to handle different message formats
  defp try_decode_approaches(response) do
    approaches = [
      # Try basic ASN.1 decoding first
      fn -> decode_snmp_message_basic(response) end,
      # Try Erlang SNMP functions
      fn -> :snmp_pdus.dec_message_only(response) end,
      fn -> :snmp_pdus.dec_message(response) end,
      fn -> :snmp_pdus.dec_pdu(response) end
    ]
    
    try_approaches(approaches, response)
  end
  
  # Basic SNMP message decoder using ASN.1 principles
  # SNMP message structure: SEQUENCE { version, community, pdu }
  defp decode_snmp_message_basic(<<48, length, rest::binary>>) when length > 0 do
    case parse_snmp_message_fields(rest) do
      {:ok, {version, community, pdu_data}} ->
        case parse_pdu(pdu_data) do
          {:ok, pdu} -> 
            %{
              version: version,
              community: community,
              data: pdu
            }
          {:error, reason} -> throw({:pdu_parse_error, reason})
        end
      {:error, reason} -> throw({:message_parse_error, reason})
    end
  end
  
  defp decode_snmp_message_basic(_), do: throw(:invalid_message_format)
  
  # Parse the three main fields of an SNMP message
  defp parse_snmp_message_fields(data) do
    with {:ok, {version, rest1}} <- parse_integer(data),
         {:ok, {community, rest2}} <- parse_octet_string(rest1),
         {:ok, pdu_data} <- {:ok, rest2} do
      {:ok, {version, community, pdu_data}}
    else
      error -> error
    end
  end
  
  # Parse ASN.1 INTEGER
  defp parse_integer(<<2, length, value_bytes::binary-size(length), rest::binary>>) do
    value = :binary.decode_unsigned(value_bytes)
    {:ok, {value, rest}}
  end
  defp parse_integer(_), do: {:error, :invalid_integer}
  
  # Parse ASN.1 OCTET STRING
  defp parse_octet_string(<<4, length, value_bytes::binary-size(length), rest::binary>>) do
    {:ok, {value_bytes, rest}}
  end
  defp parse_octet_string(_), do: {:error, :invalid_octet_string}
  
  # Parse PDU (simplified - just extract basic info)
  defp parse_pdu(<<tag, length, rest::binary>>) when tag in [160, 161, 162, 163, 164] do
    # PDU types: 160=GetRequest, 161=GetNextRequest, 162=GetResponse, 163=SetRequest, 164=Trap
    pdu_type = case tag do
      160 -> :get_request
      161 -> :get_next_request  
      162 -> :get_response
      163 -> :set_request
      164 -> :trap
    end
    
    # Parse PDU fields: request_id, error_status, error_index, varbinds
    case parse_pdu_fields(rest, length) do
      {:ok, {request_id, error_status, error_index, _varbinds}} ->
        {:ok, %{
          type: pdu_type, 
          request_id: request_id,
          error_status: error_status, 
          error_index: error_index,
          varbinds: []
        }}
      {:error, reason} ->
        # Fallback to basic structure if parsing fails
        {:ok, %{type: pdu_type, varbinds: [], error_status: 0, error_index: 0}}
    end
  end
  defp parse_pdu(_), do: {:error, :invalid_pdu}
  
  # Parse PDU fields in order: request_id, error_status, error_index, varbinds
  defp parse_pdu_fields(data, _length) do
    with {:ok, {request_id, rest1}} <- parse_integer(data),
         {:ok, {error_status, rest2}} <- parse_integer(rest1),
         {:ok, {error_index, rest3}} <- parse_integer(rest2) do
      # For now, skip varbinds parsing - just need the request_id
      {:ok, {request_id, error_status, error_index, []}}
    else
      error -> error
    end
  end
  
  defp try_approaches([], _response) do
    {:error, :all_decode_approaches_failed}
  end
  
  defp try_approaches([approach | rest], response) do
    try do
      result = approach.()
      {:ok, result}
    catch
      _error -> try_approaches(rest, response)
    end
  end

  # Converts our internal PDU map format to Erlang record format.
  defp convert_pdu_to_record(%{type: :get_bulk_request} = pdu) do
    # BULK requests use the same pdu record but with non_repeaters and max_repetitions
    # instead of error_status and error_index
    pdu_type_atom = :"get-bulk-request"
    
    # Convert varbinds to proper Erlang varbind records
    erlang_varbinds = Enum.with_index(pdu.varbinds, 1) |> Enum.map(fn {{oid, type, value}, index} ->
      converted_value = case {type, value} do
        {:null, :null} -> :null
        {_, val} -> val
      end
      {:varbind, oid, convert_value_type(type), converted_value, index}
    end)
    
    # Create pdu record with non_repeaters as error_status and max_repetitions as error_index
    # This is the format expected by Erlang's SNMP modules
    {
      :pdu,
      pdu_type_atom,         # type
      pdu.request_id,        # request_id  
      pdu.non_repeaters,     # error_status (used as non_repeaters for BULK)
      pdu.max_repetitions,   # error_index (used as max_repetitions for BULK)
      erlang_varbinds        # varbinds
    }
  end

  defp convert_pdu_to_record(%{type: type, request_id: request_id, error_status: error_status, error_index: error_index, varbinds: varbinds}) do
    # PDU types as atoms (as expected by Erlang SNMP)
    pdu_type_atom = case type do
      :get_request -> :"get-request"
      :get_next_request -> :"get-next-request"
      :get_response -> :"get-response"
      :set_request -> :"set-request"
      :get_bulk_request -> :"get-bulk-request"
      _ -> :"get-request"
    end
    
    # Convert varbinds to proper Erlang varbind records
    erlang_varbinds = Enum.with_index(varbinds, 1) |> Enum.map(fn {{oid, type, value}, index} ->
      # Create proper varbind record: #varbind{oid, variabletype, value, org_index}
      # For GET requests, NULL type should have empty value
      converted_value = case {type, value} do
        {:null, :null} -> :null  # Standard NULL representation
        {_, val} -> val
      end
      {:varbind, oid, convert_value_type(type), converted_value, index}
    end)
    
    # Create PDU record tuple based on snmp_types.hrl
    # -record(pdu, {type, request_id, error_status, error_index, varbinds})
    {
      :pdu,
      pdu_type_atom,   # type
      request_id,      # request_id  
      error_status,    # error_status
      error_index,     # error_index
      erlang_varbinds  # varbinds
    }
  end

  # Converts value types to Erlang SNMP format.
  defp convert_value_type(:null), do: :"NULL"
  defp convert_value_type(:integer), do: :"INTEGER"
  defp convert_value_type(:string), do: :"OCTET STRING"
  defp convert_value_type(:oid), do: :"OBJECT IDENTIFIER"
  defp convert_value_type(other), do: other

  @doc """
  Creates a basic SNMP response PDU structure.
  """
  def build_response(request_id, error_status, error_index, varbinds \\ []) do
    %{
      type: :get_response,
      request_id: request_id,
      error_status: error_status,
      error_index: error_index,
      varbinds: varbinds
    }
  end

  @doc """
  Creates a SNMP GET request PDU with multiple OID/value pairs.
  """
  def build_get_request_multi(varbinds, request_id) do
    case varbinds do
      [] ->
        {:error, :empty_varbinds}
      _ ->
        {:ok, %{
          type: :get_request,
          request_id: request_id,
          error_status: :noError,
          error_index: 0,
          varbinds: varbinds
        }}
    end
  end

  @doc """
  Validates a PDU structure for correctness.
  """
  def validate(pdu) when is_map(pdu) do
    with :ok <- validate_request_id(pdu),
         :ok <- validate_type(pdu),
         :ok <- validate_varbinds(pdu),
         :ok <- validate_bulk_fields(pdu) do
      {:ok, pdu}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(_), do: {:error, :invalid_pdu_format}

  # Validation helper functions
  defp validate_request_id(%{request_id: request_id}) when is_integer(request_id) and request_id >= 0 and request_id <= 2147483647 do
    :ok
  end
  defp validate_request_id(_), do: {:error, :invalid_request_id}

  defp validate_type(%{type: type}) when type in [:get_request, :get_next_request, :get_response, :set_request, :get_bulk_request] do
    :ok
  end
  defp validate_type(_), do: {:error, :invalid_pdu_type}

  defp validate_varbinds(%{varbinds: varbinds}) when is_list(varbinds) do
    case Enum.all?(varbinds, &validate_varbind/1) do
      true -> :ok
      false -> {:error, :invalid_varbinds}
    end
  end
  defp validate_varbinds(_), do: {:error, :missing_varbinds}

  defp validate_varbind({oid, _type, _value}) when is_list(oid) do
    Enum.all?(oid, &is_integer/1)
  end
  defp validate_varbind(_), do: false

  defp validate_bulk_fields(%{type: :get_bulk_request, non_repeaters: nr, max_repetitions: mr}) 
    when is_integer(nr) and nr >= 0 and is_integer(mr) and mr >= 0 do
    :ok
  end
  defp validate_bulk_fields(%{type: :get_bulk_request}), do: {:error, :missing_bulk_fields}
  defp validate_bulk_fields(_), do: :ok

  # Helper function to normalize OID format for Erlang SNMP functions
  defp normalize_oid(oid) when is_binary(oid) do
    case OID.string_to_list(oid) do
      {:ok, oid_list} -> oid_list
      {:error, _} -> oid  # Return as-is if conversion fails
    end
  end
  defp normalize_oid(oid) when is_list(oid), do: oid
  defp normalize_oid(oid), do: oid  # Return as-is for other types
end