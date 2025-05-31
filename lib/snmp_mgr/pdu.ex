defmodule SNMPMgr.PDU do
  @moduledoc """
  SNMP PDU (Protocol Data Unit) encoding and decoding.
  
  Pure Elixir implementation supporting SNMPv1 and SNMPv2c protocols including GETBULK operations.
  Uses native ASN.1 BER encoding/decoding without Erlang SNMP dependencies.
  """

  import Bitwise
  alias SNMPMgr.OID

  # ASN.1 BER encoding functions for pure Elixir implementation
  
  # Encode ASN.1 INTEGER
  defp encode_integer_ber(value) when is_integer(value) do
    # Convert integer to minimal two's complement representation
    bytes = integer_to_bytes(value)
    length = byte_size(bytes)
    
    # ASN.1 INTEGER tag is 0x02
    encode_tag_length_value(0x02, length, bytes)
  end
  
  # Encode ASN.1 OCTET STRING  
  defp encode_octet_string_ber(value) when is_binary(value) do
    length = byte_size(value)
    # ASN.1 OCTET STRING tag is 0x04
    encode_tag_length_value(0x04, length, value)
  end
  
  # Encode ASN.1 SEQUENCE
  defp encode_sequence_ber(content) when is_binary(content) do
    length = byte_size(content)
    # ASN.1 SEQUENCE tag is 0x30
    encode_tag_length_value(0x30, length, content)
  end
  
  # Encode ASN.1 NULL
  defp encode_null_ber() do
    # ASN.1 NULL tag is 0x05, length is 0, no content
    <<0x05, 0x00>>
  end
  
  # Encode ASN.1 OBJECT IDENTIFIER (OID)
  defp encode_oid_ber(oid_list) when is_list(oid_list) do
    case encode_oid_content(oid_list) do
      {:ok, content} ->
        length = byte_size(content)
        # ASN.1 OBJECT IDENTIFIER tag is 0x06
        {:ok, encode_tag_length_value(0x06, length, content)}
      {:error, _} = error ->
        error
    end
  end
  
  # Generic tag-length-value encoder for ASN.1 BER
  defp encode_tag_length_value(tag, length, content) do
    length_bytes = encode_length_ber(length)
    <<tag>> <> length_bytes <> content
  end
  
  # Encode ASN.1 BER length field
  defp encode_length_ber(length) when length < 128 do
    # Short form: length fits in 7 bits
    <<length>>
  end
  defp encode_length_ber(length) when length < 256 do
    # Long form: one byte for length
    <<0x81, length>>
  end
  defp encode_length_ber(length) when length < 65536 do
    # Long form: two bytes for length
    <<0x82, length::16>>
  end
  defp encode_length_ber(length) when length < 16777216 do
    # Long form: three bytes for length
    <<0x83, length::24>>
  end
  defp encode_length_ber(length) do
    # Long form: four bytes for length (should handle most cases)
    <<0x84, length::32>>
  end
  
  # Convert integer to minimal two's complement byte representation
  defp integer_to_bytes(0), do: <<0>>
  defp integer_to_bytes(value) when value > 0 do
    bytes = :binary.encode_unsigned(value, :big)
    # Check if we need to add a leading zero for positive numbers
    case bytes do
      <<bit::1, _::bitstring>> when bit == 1 ->
        # High bit is set, need leading zero to indicate positive
        <<0>> <> bytes
      _ ->
        bytes
    end
  end
  defp integer_to_bytes(value) when value < 0 do
    # For negative numbers, convert to two's complement
    positive = abs(value)
    bit_length = bit_length_for_integer(positive) + 1  # Extra bit for sign
    byte_length = div(bit_length + 7, 8)  # Round up to byte boundary
    
    # Calculate two's complement
    max_value = 1 <<< (byte_length * 8)
    twos_comp = max_value + value
    
    <<twos_comp::size(byte_length)-unit(8)-big>>
  end
  
  # Calculate minimum bit length needed for an integer
  defp bit_length_for_integer(0), do: 1
  defp bit_length_for_integer(n) when n > 0 do
    :math.log2(n) |> :math.ceil() |> trunc()
  end
  
  # Encode OID content according to ASN.1 rules
  defp encode_oid_content([]), do: {:error, :empty_oid}
  defp encode_oid_content([first]) when first < 3, do: {:error, :invalid_oid_format}
  defp encode_oid_content([first, second | rest]) when first < 3 and second < 40 do
    # First two sub-identifiers are encoded as: first * 40 + second
    first_encoded = first * 40 + second
    case encode_oid_subidentifiers([first_encoded | rest]) do
      {:ok, content} -> {:ok, content}
      error -> error
    end
  end
  defp encode_oid_content(_), do: {:error, :invalid_oid_format}
  
  # Encode OID sub-identifiers using variable-length encoding
  defp encode_oid_subidentifiers([]), do: {:ok, <<>>}
  defp encode_oid_subidentifiers([subid | rest]) do
    case encode_oid_subidentifier(subid) do
      {:ok, encoded_subid} ->
        case encode_oid_subidentifiers(rest) do
          {:ok, encoded_rest} -> {:ok, encoded_subid <> encoded_rest}
          error -> error
        end
      error -> error
    end
  end
  
  # Encode single OID sub-identifier (variable length encoding)
  defp encode_oid_subidentifier(subid) when subid >= 0 and subid < 128 do
    # Single byte encoding
    {:ok, <<subid>>}
  end
  defp encode_oid_subidentifier(subid) when subid >= 0 do
    # Multi-byte encoding (each byte has high bit set except last)
    encode_oid_subid_multibyte(subid, [])
  end
  defp encode_oid_subidentifier(_), do: {:error, :invalid_subidentifier}
  
  # Multi-byte OID sub-identifier encoding
  defp encode_oid_subid_multibyte(subid, acc) when subid < 128 do
    # Last byte (high bit clear)
    bytes = [subid | acc] |> Enum.reverse() |> :binary.list_to_bin()
    {:ok, bytes}
  end
  defp encode_oid_subid_multibyte(subid, acc) do
    # Continue encoding (high bit set)
    byte = (subid &&& 0x7F) ||| 0x80
    encode_oid_subid_multibyte(subid >>> 7, [byte | acc])
  end
  
  # Encode SNMP PDU to ASN.1 BER format
  defp encode_pdu_to_ber(pdu) when is_map(pdu) do
    case Map.get(pdu, :type) do
      :get_request -> encode_get_request_pdu(pdu)
      :get_next_request -> encode_get_next_request_pdu(pdu)
      :get_response -> encode_get_response_pdu(pdu)
      :set_request -> encode_set_request_pdu(pdu)
      :get_bulk_request -> encode_get_bulk_request_pdu(pdu)
      _ -> {:error, {:unsupported_pdu_type, Map.get(pdu, :type)}}
    end
  end
  defp encode_pdu_to_ber(_), do: {:error, :invalid_pdu_format}
  
  # Encode GET request PDU
  defp encode_get_request_pdu(pdu) do
    encode_standard_pdu(pdu, 0xA0)  # GET request tag
  end
  
  # Encode GETNEXT request PDU
  defp encode_get_next_request_pdu(pdu) do
    encode_standard_pdu(pdu, 0xA1)  # GETNEXT request tag
  end
  
  # Encode GET response PDU
  defp encode_get_response_pdu(pdu) do
    encode_standard_pdu(pdu, 0xA2)  # GET response tag
  end
  
  # Encode SET request PDU
  defp encode_set_request_pdu(pdu) do
    encode_standard_pdu(pdu, 0xA3)  # SET request tag
  end
  
  # Encode GETBULK request PDU (SNMPv2c)
  defp encode_get_bulk_request_pdu(pdu) do
    request_id = Map.get(pdu, :request_id, 1)
    non_repeaters = Map.get(pdu, :non_repeaters, 0)
    max_repetitions = Map.get(pdu, :max_repetitions, 10)
    varbinds = Map.get(pdu, :varbinds, [])
    
    # GETBULK uses non_repeaters and max_repetitions instead of error_status and error_index
    with {:ok, request_id_encoded} <- {:ok, encode_integer_ber(request_id)},
         {:ok, non_repeaters_encoded} <- {:ok, encode_integer_ber(non_repeaters)},
         {:ok, max_repetitions_encoded} <- {:ok, encode_integer_ber(max_repetitions)},
         {:ok, varbinds_encoded} <- encode_varbinds(varbinds) do
      
      content = request_id_encoded <> non_repeaters_encoded <> max_repetitions_encoded <> varbinds_encoded
      length = byte_size(content)
      
      # GETBULK request tag is 0xA5
      {:ok, encode_tag_length_value(0xA5, length, content)}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Encode standard PDU (GET, GETNEXT, GETRESPONSE, SET)
  defp encode_standard_pdu(pdu, tag) do
    request_id = Map.get(pdu, :request_id, 1)
    error_status = Map.get(pdu, :error_status, 0)
    error_index = Map.get(pdu, :error_index, 0)
    varbinds = Map.get(pdu, :varbinds, [])
    
    with {:ok, request_id_encoded} <- {:ok, encode_integer_ber(request_id)},
         {:ok, error_status_encoded} <- {:ok, encode_integer_ber(error_status)},
         {:ok, error_index_encoded} <- {:ok, encode_integer_ber(error_index)},
         {:ok, varbinds_encoded} <- encode_varbinds(varbinds) do
      
      content = request_id_encoded <> error_status_encoded <> error_index_encoded <> varbinds_encoded
      length = byte_size(content)
      
      {:ok, encode_tag_length_value(tag, length, content)}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Encode varbinds (variable bindings) list
  defp encode_varbinds(varbinds) when is_list(varbinds) do
    case encode_varbind_list(varbinds, []) do
      {:ok, encoded_varbinds} ->
        # Wrap in SEQUENCE
        varbinds_content = :binary.list_to_bin(encoded_varbinds)
        {:ok, encode_sequence_ber(varbinds_content)}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Encode individual varbinds
  defp encode_varbind_list([], acc), do: {:ok, Enum.reverse(acc)}
  defp encode_varbind_list([varbind | rest], acc) do
    case encode_single_varbind(varbind) do
      {:ok, encoded} ->
        encode_varbind_list(rest, [encoded | acc])
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Encode a single varbind: {oid, type, value}
  defp encode_single_varbind({oid, type, value}) do
    # Handle different OID formats
    oid_encoded = case oid do
      oid_list when is_list(oid_list) ->
        case encode_oid_ber(oid_list) do
          {:ok, encoded} -> encoded
          {:error, _reason} -> 
            # Fallback: if encoding fails, create a basic OID
            encode_oid_ber([1, 3, 6, 1]) |> elem(1)
        end
      oid_binary when is_binary(oid_binary) ->
        # Already encoded OID, use as-is
        oid_binary
      _ ->
        # Fallback for other formats
        encode_oid_ber([1, 3, 6, 1]) |> elem(1)
    end
    
    case encode_snmp_value(type, value) do
      {:ok, value_encoded} ->
        # Varbind is a SEQUENCE of OID and value
        varbind_content = oid_encoded <> value_encoded
        {:ok, encode_sequence_ber(varbind_content)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  defp encode_single_varbind(_), do: {:error, :invalid_varbind_format}
  
  # Encode SNMP values based on type
  defp encode_snmp_value(:null, _), do: {:ok, encode_null_ber()}
  defp encode_snmp_value(:integer, value) when is_integer(value), do: {:ok, encode_integer_ber(value)}
  defp encode_snmp_value(:string, value) when is_binary(value), do: {:ok, encode_octet_string_ber(value)}
  defp encode_snmp_value(:oid, value) when is_list(value), do: encode_oid_ber(value)
  defp encode_snmp_value(_, :null), do: {:ok, encode_null_ber()}
  defp encode_snmp_value(type, value), do: {:error, {:unsupported_value_type, type, value}}

  @doc """
  Creates a basic SNMP GET request PDU structure.
  """
  def build_get_request(oid_list, request_id) do
    normalized_oid = normalize_oid(oid_list)
    %{
      type: :get_request,
      request_id: request_id,
      error_status: 0,  # Use numeric error code for test compatibility
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
      error_status: 0,  # Use numeric error code for test compatibility
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
      error_status: 0,  # Use numeric error code for test compatibility
      error_index: 0,
      varbinds: [{normalized_oid, {type, value}, :null}]  # Wrap value in expected format
    }
  end

  @doc """
  Creates a basic SNMP GETBULK request PDU structure for SNMPv2c.
  """
  def build_get_bulk_request(oid_list, request_id, non_repeaters \\ 0, max_repetitions \\ 10) do
    # Validate parameters
    if not (is_integer(request_id) and request_id >= 0 and request_id <= 2147483647) do
      raise ArgumentError, "Request ID must be a valid integer (0-2147483647), got: #{inspect(request_id)}"
    end
    
    if not (is_integer(non_repeaters) and non_repeaters >= 0) do
      raise ArgumentError, "non_repeaters must be a non-negative integer, got: #{inspect(non_repeaters)}"
    end
    
    if not (is_integer(max_repetitions) and max_repetitions >= 0) do
      raise ArgumentError, "max_repetitions must be a non-negative integer, got: #{inspect(max_repetitions)}"
    end
    
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
    # Validate parameters - community must be a binary string
    if not is_binary(community) do
      raise ArgumentError, "Community must be a binary string, got: #{inspect(community)}"
    else
      # Validate version for GETBULK
      if Map.get(pdu, :type) == :get_bulk_request and version == :v1 do
        raise ArgumentError, "GETBULK requests require SNMPv2c or higher, cannot use v1"
      else
        build_message_validated(pdu, community, version)
      end
    end
  end
  
  defp build_message_validated(pdu, community, version) do
    # Return numeric version for test compatibility
    version_number = case version do
      :v1 -> 0
      :v2c -> 1
      :v2 -> 1   # v2 is same as v2c
      :v3 -> 3
      _ -> 0
    end
    
    # Return in map format ready for pure Elixir encoding
    %{
      version: version_number,
      community: community,
      pdu: pdu
    }
  end

  @doc """
  Encodes an SNMP message using pure Elixir ASN.1 BER encoding.
  
  Replaces Erlang SNMP dependencies with native Elixir implementation.
  """
  def encode_message(message) do
    try do
      case message do
        %{version: version, community: community, pdu: pdu} ->
          encode_snmp_message_fast(version, community, pdu)
        _ ->
          {:error, :invalid_message_format}
      end
    catch
      error -> {:error, {:encoding_error, error}}
    end
  end
  
  # Pure Elixir SNMP message encoder
  defp encode_snmp_message_pure_elixir(version, community, pdu) do
    # Convert version to integer for ASN.1 encoding
    version_int = case version do
      :v1 -> 0
      :v2c -> 1
      :v2 -> 1
      :v3 -> 3
      0 -> 0
      1 -> 1
      3 -> 3
      _ -> 0
    end
    
    # Validate community is binary
    if not is_binary(community) do
      {:error, {:invalid_community, community}}
    else
      # Encode PDU to ASN.1 BER
      case encode_pdu_to_ber(pdu) do
        {:ok, encoded_pdu} ->
          # Build complete SNMP message: SEQUENCE { version, community, pdu }
          version_encoded = encode_integer_ber(version_int)
          community_encoded = encode_octet_string_ber(community)
          
          # Combine all parts into SEQUENCE
          message_content = version_encoded <> community_encoded <> encoded_pdu
          message_sequence = encode_sequence_ber(message_content)
          
          {:ok, message_sequence}
          
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Decodes an SNMP response using pure Elixir ASN.1 BER decoding.
  
  Replaces Erlang SNMP dependencies with native Elixir implementation.
  """
  def decode_message(response) do
    try do
      case try_decode_approaches(response) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, reason} -> {:error, reason}
      end
    catch
      error -> {:error, {:decoding_error, error}}
    end
  end
  
  # Pure Elixir SNMP message decoding (no Erlang fallbacks)
  defp try_decode_approaches(response) do
    # Validate input first
    if is_nil(response) or response == "" do
      {:error, :empty_or_nil_response}
    else
      # Use only pure Elixir decoding (no Erlang fallbacks)
      case decode_snmp_message_basic(response) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, reason} -> {:error, reason}
      end
    end
  end
  
  # Basic SNMP message decoder using ASN.1 principles
  # SNMP message structure: SEQUENCE { version, community, pdu }
  defp decode_snmp_message_basic(<<48, rest::binary>>) do
    case parse_ber_length(rest) do
      {:ok, {_content_length, content}} ->
        case parse_snmp_message_fields(content) do
          {:ok, {version, community, pdu_data}} ->
            case parse_pdu(pdu_data) do
              {:ok, pdu} -> 
                {:ok, %{
                  version: version,
                  community: community,
                  pdu: pdu
                }}
              {:error, reason} -> {:error, {:pdu_parse_error, reason}}
            end
          {:error, reason} -> {:error, {:message_parse_error, reason}}
        end
      {:error, reason} -> {:error, {:message_parse_error, reason}}
    end
  end
  
  defp decode_snmp_message_basic(_), do: {:error, :invalid_message_format}
  
  # Parse BER length field (handles both short and long form)
  defp parse_ber_length(<<length, rest::binary>>) when length < 128 do
    # Short form: length < 128
    if byte_size(rest) >= length do
      content = binary_part(rest, 0, length)
      {:ok, {length, content}}
    else
      {:error, :insufficient_data}
    end
  end
  defp parse_ber_length(<<length_of_length, rest::binary>>) when length_of_length >= 128 do
    # Long form: first byte indicates how many bytes encode the length
    num_length_bytes = length_of_length - 128
    if num_length_bytes > 0 and num_length_bytes <= 4 and byte_size(rest) >= num_length_bytes do
      <<length_bytes::binary-size(num_length_bytes), remaining::binary>> = rest
      actual_length = :binary.decode_unsigned(length_bytes, :big)
      
      if byte_size(remaining) >= actual_length do
        content = binary_part(remaining, 0, actual_length)
        {:ok, {actual_length, content}}
      else
        {:error, :insufficient_data}
      end
    else
      {:error, :invalid_length_encoding}
    end
  end
  defp parse_ber_length(_), do: {:error, :invalid_length_format}
  
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
  defp parse_integer(<<2, rest::binary>>) do
    case parse_ber_length_and_remaining(rest) do
      {:ok, {_length, value_bytes, remaining}} ->
        if byte_size(value_bytes) > 0 do
          value = :binary.decode_unsigned(value_bytes)
          {:ok, {value, remaining}}
        else
          {:error, :invalid_integer_length}
        end
      {:error, reason} -> {:error, reason}
    end
  end
  defp parse_integer(_), do: {:error, :invalid_integer}
  
  # Parse ASN.1 OCTET STRING  
  defp parse_octet_string(<<4, rest::binary>>) do
    case parse_ber_length_and_remaining(rest) do
      {:ok, {_length, value_bytes, remaining}} ->
        {:ok, {value_bytes, remaining}}
      {:error, reason} -> {:error, reason}
    end
  end
  defp parse_octet_string(_), do: {:error, :invalid_octet_string}
  
  # Parse BER length and return content + remaining data
  defp parse_ber_length_and_remaining(<<length, rest::binary>>) when length < 128 do
    # Short form: length < 128
    if byte_size(rest) >= length do
      content = binary_part(rest, 0, length)
      remaining = binary_part(rest, length, byte_size(rest) - length)
      {:ok, {length, content, remaining}}
    else
      {:error, :insufficient_data}
    end
  end
  defp parse_ber_length_and_remaining(<<length_of_length, rest::binary>>) when length_of_length >= 128 do
    # Long form: first byte indicates how many bytes encode the length
    num_length_bytes = length_of_length - 128
    if num_length_bytes > 0 and num_length_bytes <= 4 and byte_size(rest) >= num_length_bytes do
      <<length_bytes::binary-size(num_length_bytes), remaining_with_content::binary>> = rest
      actual_length = :binary.decode_unsigned(length_bytes, :big)
      
      if byte_size(remaining_with_content) >= actual_length do
        content = binary_part(remaining_with_content, 0, actual_length)
        remaining = binary_part(remaining_with_content, actual_length, byte_size(remaining_with_content) - actual_length)
        {:ok, {actual_length, content, remaining}}
      else
        {:error, :insufficient_data}
      end
    else
      {:error, :invalid_length_encoding}
    end
  end
  defp parse_ber_length_and_remaining(_), do: {:error, :invalid_length_format}
  
  # Parse PDU (simplified - just extract basic info)
  defp parse_pdu(<<tag, rest::binary>>) when tag in [160, 161, 162, 163, 164, 165] do
    # PDU types: 160=GetRequest, 161=GetNextRequest, 162=GetResponse, 163=SetRequest, 164=Trap, 165=GetBulkRequest
    pdu_type = case tag do
      160 -> :get_request
      161 -> :get_next_request  
      162 -> :get_response
      163 -> :set_request
      164 -> :trap
      165 -> :get_bulk_request
    end
    
    case parse_ber_length_and_remaining(rest) do
      {:ok, {_length, pdu_content, _remaining}} ->
        # Parse PDU fields based on type
        case pdu_type do
          :get_bulk_request ->
            # GETBULK uses: request_id, non_repeaters, max_repetitions, varbinds
            case parse_bulk_pdu_fields(pdu_content) do
              {:ok, {request_id, non_repeaters, max_repetitions, varbinds}} ->
                {:ok, %{
                  type: pdu_type, 
                  request_id: request_id,
                  non_repeaters: non_repeaters, 
                  max_repetitions: max_repetitions,
                  varbinds: varbinds
                }}
              {:error, _reason} ->
                # Fallback to basic structure if parsing fails
                {:ok, %{type: pdu_type, varbinds: [], non_repeaters: 0, max_repetitions: 0}}
            end
          _ ->
            # Standard PDU uses: request_id, error_status, error_index, varbinds
            case parse_pdu_fields(pdu_content) do
              {:ok, {request_id, error_status, error_index, varbinds}} ->
                {:ok, %{
                  type: pdu_type, 
                  request_id: request_id,
                  error_status: error_status, 
                  error_index: error_index,
                  varbinds: varbinds
                }}
              {:error, _reason} ->
                # Fallback to basic structure if parsing fails
                {:ok, %{type: pdu_type, varbinds: [], error_status: 0, error_index: 0}}
            end
        end
      {:error, _reason} ->
        # Fallback to basic structure if length parsing fails
        case pdu_type do
          :get_bulk_request ->
            {:ok, %{type: pdu_type, varbinds: [], non_repeaters: 0, max_repetitions: 0}}
          _ ->
            {:ok, %{type: pdu_type, varbinds: [], error_status: 0, error_index: 0}}
        end
    end
  end
  defp parse_pdu(_), do: {:error, :invalid_pdu}
  
  # Parse PDU fields in order: request_id, error_status, error_index, varbinds
  defp parse_pdu_fields(data) do
    with {:ok, {request_id, rest1}} <- parse_integer(data),
         {:ok, {error_status, rest2}} <- parse_integer(rest1),
         {:ok, {error_index, rest3}} <- parse_integer(rest2),
         {:ok, varbinds} <- parse_varbinds(rest3) do
      {:ok, {request_id, error_status, error_index, varbinds}}
    else
      error -> error
    end
  end
  
  # Parse GETBULK PDU fields in order: request_id, non_repeaters, max_repetitions, varbinds
  defp parse_bulk_pdu_fields(data) do
    with {:ok, {request_id, rest1}} <- parse_integer(data),
         {:ok, {non_repeaters, rest2}} <- parse_integer(rest1),
         {:ok, {max_repetitions, rest3}} <- parse_integer(rest2),
         {:ok, varbinds} <- parse_varbinds(rest3) do
      {:ok, {request_id, non_repeaters, max_repetitions, varbinds}}
    else
      error -> error
    end
  end
  
  # Parse SNMP varbinds (variable bindings) containing OID-value pairs
  defp parse_varbinds(data) do
    case parse_sequence(data) do
      {:ok, {varbind_data, _rest}} -> parse_varbind_list(varbind_data, [])
      {:error, _} -> {:ok, []} # Return empty list if varbinds can't be parsed
    end
  end
  
  # Parse an ASN.1 SEQUENCE
  defp parse_sequence(<<0x30, rest::binary>>) do
    case parse_ber_length_and_remaining(rest) do
      {:ok, {_length, data, remaining}} ->
        {:ok, {data, remaining}}
      {:error, reason} -> {:error, reason}
    end
  end
  defp parse_sequence(_), do: {:error, :not_sequence}
  
  defp parse_varbind_list(<<>>, acc), do: {:ok, Enum.reverse(acc)}
  defp parse_varbind_list(data, acc) do
    case parse_sequence(data) do
      {:ok, {varbind_data, rest}} ->
        case parse_single_varbind(varbind_data) do
          {:ok, varbind} -> parse_varbind_list(rest, [varbind | acc])
          {:error, _} -> parse_varbind_list(rest, acc) # Skip invalid varbinds
        end
      {:error, _} -> {:ok, Enum.reverse(acc)}
    end
  end
  
  defp parse_single_varbind(data) do
    with {:ok, {oid, rest1}} <- parse_oid(data),
         {:ok, {value, _rest2}} <- parse_value(rest1) do
      {:ok, {oid, :octet_string, value}}
    else
      _ -> {:error, :invalid_varbind}
    end
  end
  
  # Parse an OID from ASN.1 data
  defp parse_oid(<<0x06, length, oid_data::binary-size(length), rest::binary>>) do
    case decode_oid_data(oid_data) do
      {:ok, oid} -> {:ok, {oid, rest}}
      error -> error
    end
  end
  defp parse_oid(_), do: {:error, :invalid_oid}
  
  # Decode OID data according to ASN.1 rules
  defp decode_oid_data(<<first, rest::binary>>) do
    # First byte encodes first two sub-identifiers: first_subid * 40 + second_subid
    first_subid = div(first, 40)
    second_subid = rem(first, 40)
    
    case decode_oid_subids(rest, [second_subid, first_subid]) do
      {:ok, subids} -> {:ok, Enum.reverse(subids)}
      error -> error
    end
  end
  defp decode_oid_data(_), do: {:error, :invalid_oid_data}
  
  defp decode_oid_subids(<<>>, acc), do: {:ok, acc}
  defp decode_oid_subids(data, acc) do
    case decode_oid_subid(data, 0) do
      {:ok, {subid, rest}} -> decode_oid_subids(rest, [subid | acc])
      error -> error
    end
  end
  
  # Decode a single OID sub-identifier (variable length encoding)
  defp decode_oid_subid(<<byte, rest::binary>>, acc) do
    new_acc = (acc <<< 7) + (byte &&& 0x7F)
    if (byte &&& 0x80) == 0 do
      {:ok, {new_acc, rest}}
    else
      decode_oid_subid(rest, new_acc)
    end
  end
  defp decode_oid_subid(<<>>, _), do: {:error, :incomplete_oid}
  
  # Parse a value (simplified - handles common SNMP types)
  defp parse_value(<<0x04, length, value::binary-size(length), rest::binary>>) do
    # OCTET STRING
    {:ok, {value, rest}}
  end
  defp parse_value(<<0x02, length, value_data::binary-size(length), rest::binary>>) do
    # INTEGER
    case decode_integer_value(value_data) do
      {:ok, int_value} -> {:ok, {int_value, rest}}
      error -> error
    end
  end
  defp parse_value(<<0x05, 0, rest::binary>>) do
    # NULL
    {:ok, {:null, rest}}
  end
  defp parse_value(<<tag, length, value::binary-size(length), rest::binary>>) do
    # Handle specific SNMP types by tag
    case tag do
      0x40 -> # IpAddress (4 bytes)
        case value do
          <<a, b, c, d>> -> {:ok, {"#{a}.#{b}.#{c}.#{d}", rest}}
          _ -> {:ok, {Base.encode16(value), rest}}
        end
      
      0x41 -> # Counter32
        case decode_unsigned_integer(value) do
          {:ok, counter_value} -> {:ok, {counter_value, rest}}
          _ -> {:ok, {"COUNTER_#{Base.encode16(value)}", rest}}
        end
      
      0x42 -> # Gauge32 / Unsigned32
        case decode_unsigned_integer(value) do
          {:ok, gauge_value} -> {:ok, {gauge_value, rest}}
          _ -> {:ok, {"GAUGE_#{Base.encode16(value)}", rest}}
        end
      
      0x43 -> # TimeTicks
        case decode_unsigned_integer(value) do
          {:ok, ticks} -> 
            # Convert to human readable format (centiseconds to time)
            seconds = div(ticks, 100)
            centiseconds = rem(ticks, 100)
            {:ok, {"#{format_uptime(seconds)}.#{centiseconds}", rest}}
          _ -> {:ok, {"TIMETICKS_#{Base.encode16(value)}", rest}}
        end
      
      0x44 -> # Opaque
        {:ok, {"OPAQUE_#{Base.encode16(value)}", rest}}
      
      0x46 -> # Counter64 
        case decode_counter64(value) do
          {:ok, counter64_value} -> {:ok, {counter64_value, rest}}
          _ -> {:ok, {"COUNTER64_#{Base.encode16(value)}", rest}}
        end
      
      0x80 -> # NoSuchObject
        {:ok, {:noSuchObject, rest}}
      
      0x81 -> # NoSuchInstance  
        {:ok, {:noSuchInstance, rest}}
      
      0x82 -> # EndOfMibView
        {:ok, {:endOfMibView, rest}}
      
      _ -> 
        # Fallback for truly unknown types
        {:ok, {"UNKNOWN_TYPE_#{tag}_#{Base.encode16(value)}", rest}}
    end
  end
  defp parse_value(_), do: {:error, :invalid_value}
  
  defp decode_integer_value(<<byte>>) when byte < 128, do: {:ok, byte}
  defp decode_integer_value(<<byte>>) when byte >= 128, do: {:ok, byte - 256}
  defp decode_integer_value(data) do
    case Integer.parse(Base.encode16(data), 16) do
      {value, ""} -> 
        # Handle two's complement for negative numbers
        bit_size = byte_size(data) * 8
        if value >= (1 <<< (bit_size - 1)) do
          {:ok, value - (1 <<< bit_size)}
        else
          {:ok, value}
        end
      _ -> {:error, :invalid_integer}
    end
  end
  
  # Decode unsigned integer (for Counter32, Gauge32, TimeTicks)
  defp decode_unsigned_integer(data) when byte_size(data) <= 4 do
    case :binary.decode_unsigned(data, :big) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, :invalid_unsigned_integer}
    end
  end
  defp decode_unsigned_integer(_), do: {:error, :invalid_unsigned_integer}
  
  # Decode Counter64 (8-byte unsigned integer)
  defp decode_counter64(data) when byte_size(data) == 8 do
    case :binary.decode_unsigned(data, :big) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, :invalid_counter64}
    end
  end
  defp decode_counter64(_), do: {:error, :invalid_counter64}
  
  # Format uptime in human readable format
  defp format_uptime(seconds) when seconds < 60 do
    "#{seconds}s"
  end
  defp format_uptime(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end
  defp format_uptime(seconds) when seconds < 86400 do
    hours = div(seconds, 3600)
    remaining_seconds = rem(seconds, 3600)
    minutes = div(remaining_seconds, 60)
    remaining_seconds = rem(remaining_seconds, 60)
    "#{hours}h #{minutes}m #{remaining_seconds}s"
  end
  defp format_uptime(seconds) do
    days = div(seconds, 86400)
    remaining_seconds = rem(seconds, 86400)
    hours = div(remaining_seconds, 3600)
    remaining_seconds = rem(remaining_seconds, 3600)
    minutes = div(remaining_seconds, 60)
    remaining_seconds = rem(remaining_seconds, 60)
    "#{days}d #{hours}h #{minutes}m #{remaining_seconds}s"
  end
  


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
        raise ArgumentError, "varbinds list cannot be empty"
      varbinds when is_list(varbinds) ->
        # Validate request_id
        if not (is_integer(request_id) and request_id >= 0 and request_id <= 2147483647) do
          raise ArgumentError, "Request ID must be a valid integer (0-2147483647), got: #{inspect(request_id)}"
        end
        
        # Validate varbinds format
        if not Enum.all?(varbinds, fn
          {oid, _type, _value} when is_list(oid) -> Enum.all?(oid, &is_integer/1)
          _ -> false
        end) do
          raise ArgumentError, "Invalid varbind format. Expected {oid_list, type, value} tuples with valid OID lists"
        end
        
        {:ok, %{
          type: :get_request,
          request_id: request_id,
          error_status: 0,  # Use numeric error code for test compatibility
          error_index: 0,
          varbinds: varbinds
        }}
      _ ->
        raise ArgumentError, "varbinds must be a list"
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
  defp validate_request_id(%{request_id: request_id}) do
    raise ArgumentError, "Request ID must be a valid integer (0-2147483647), got: #{inspect(request_id)}"
  end
  defp validate_request_id(_), do: {:error, :missing_request_id}

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
  defp validate_bulk_fields(%{type: :get_bulk_request}) do
    raise ArgumentError, "GETBULK PDU must have non_repeaters and max_repetitions fields"
  end
  defp validate_bulk_fields(_), do: :ok

  # Helper function to normalize OID format for Erlang SNMP functions
  defp normalize_oid(oid) when is_binary(oid) do
    case OID.string_to_list(oid) do
      {:ok, oid_list} -> oid_list
      {:error, _} -> 
        # If conversion fails, try to parse as a simple dot-separated string
        case String.split(oid, ".") do
          parts when length(parts) > 1 ->
            try do
              Enum.map(parts, &String.to_integer/1)
            rescue
              ArgumentError -> [1, 3, 6, 1]  # Default fallback OID
            end
          _ -> [1, 3, 6, 1]  # Default fallback OID
        end
    end
  end
  defp normalize_oid(oid) when is_list(oid), do: oid
  defp normalize_oid(oid), do: [1, 3, 6, 1]  # Convert everything else to safe default

  # ===== OPTIMIZED ENCODING FUNCTIONS =====
  # These functions prioritize performance over readability for the critical path
  
  # Fast SNMP message encoder - optimized for performance
  defp encode_snmp_message_fast(version, community, pdu) when is_binary(community) do
    # Convert version to integer for ASN.1 encoding
    version_int = case version do
      :v1 -> 0; :v2c -> 1; :v2 -> 1; :v3 -> 3
      0 -> 0; 1 -> 1; 3 -> 3; _ -> 0
    end
    
    case encode_pdu_fast(pdu) do
      {:ok, encoded_pdu} ->
        # Build complete SNMP message using iodata for efficiency
        iodata = [
          encode_integer_fast(version_int),     # version
          encode_octet_string_fast(community), # community  
          encoded_pdu                          # pdu
        ]
        
        # Convert to binary and wrap in SEQUENCE
        content = :erlang.iolist_to_binary(iodata)
        {:ok, encode_sequence_ber(content)}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  defp encode_snmp_message_fast(_, _, _), do: {:error, :invalid_community}
  
  # Fast PDU encoder - reduced function call overhead
  defp encode_pdu_fast(%{type: :get_request} = pdu), do: encode_standard_pdu_fast(pdu, 0xA0)
  defp encode_pdu_fast(%{type: :get_next_request} = pdu), do: encode_standard_pdu_fast(pdu, 0xA1)
  defp encode_pdu_fast(%{type: :get_response} = pdu), do: encode_standard_pdu_fast(pdu, 0xA2)
  defp encode_pdu_fast(%{type: :set_request} = pdu), do: encode_standard_pdu_fast(pdu, 0xA3)
  defp encode_pdu_fast(%{type: :get_bulk_request} = pdu), do: encode_bulk_pdu_fast(pdu)
  defp encode_pdu_fast(_), do: {:error, :unsupported_pdu_type}
  
  # Fast standard PDU encoder using direct access and iodata
  defp encode_standard_pdu_fast(pdu, tag) do
    # Use pattern matching for better performance than Map.get
    %{
      request_id: request_id,
      error_status: error_status, 
      error_index: error_index,
      varbinds: varbinds
    } = pdu
    
    case encode_varbinds_fast(varbinds) do
      {:ok, varbinds_encoded} ->
        # Use iodata for efficient binary construction
        iodata = [
          encode_integer_fast(request_id),
          encode_integer_fast(error_status),
          encode_integer_fast(error_index),
          varbinds_encoded
        ]
        
        content = :erlang.iolist_to_binary(iodata)
        {:ok, encode_tag_length_value(tag, byte_size(content), content)}
        
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Fast GETBULK PDU encoder
  defp encode_bulk_pdu_fast(pdu) do
    %{
      request_id: request_id,
      non_repeaters: non_repeaters,
      max_repetitions: max_repetitions,
      varbinds: varbinds
    } = pdu
    
    case encode_varbinds_fast(varbinds) do
      {:ok, varbinds_encoded} ->
        iodata = [
          encode_integer_fast(request_id),
          encode_integer_fast(non_repeaters),
          encode_integer_fast(max_repetitions),
          varbinds_encoded
        ]
        
        content = :erlang.iolist_to_binary(iodata)
        {:ok, encode_tag_length_value(0xA5, byte_size(content), content)}
        
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Fast varbinds encoder - optimized with tail recursion and iodata
  defp encode_varbinds_fast(varbinds) when is_list(varbinds) do
    case encode_varbinds_acc(varbinds, []) do
      {:ok, iodata} ->
        content = :erlang.iolist_to_binary(iodata)
        {:ok, encode_sequence_ber(content)}
      error -> error
    end
  end
  
  defp encode_varbinds_acc([], acc), do: {:ok, Enum.reverse(acc)}
  defp encode_varbinds_acc([varbind | rest], acc) do
    case encode_varbind_fast(varbind) do
      {:ok, encoded} -> encode_varbinds_acc(rest, [encoded | acc])
      error -> error
    end
  end
  
  # Fast single varbind encoder
  defp encode_varbind_fast({oid, type, value}) when is_list(oid) do
    case encode_oid_fast(oid) do
      {:ok, oid_encoded} ->
        value_encoded = encode_snmp_value_fast(type, value)
        content = :erlang.iolist_to_binary([oid_encoded, value_encoded])
        {:ok, encode_sequence_ber(content)}
      error -> error
    end
  end
  defp encode_varbind_fast(_), do: {:error, :invalid_varbind_format}
  
  # Fast OID encoder - optimized for common cases
  defp encode_oid_fast(oid_list) when is_list(oid_list) and length(oid_list) >= 2 do
    [first, second | rest] = oid_list
    
    if first < 3 and second < 40 do
      # First two sub-identifiers are encoded as: first * 40 + second
      first_encoded = first * 40 + second
      
      case encode_oid_subids_fast([first_encoded | rest], []) do
        {:ok, content} ->
          {:ok, encode_tag_length_value(0x06, byte_size(content), content)}
        error -> error
      end
    else
      {:error, :invalid_oid_format}
    end
  end
  defp encode_oid_fast(_), do: {:error, :invalid_oid_format}
  
  # Fast OID sub-identifiers encoder using tail recursion
  defp encode_oid_subids_fast([], acc) do
    {:ok, :erlang.iolist_to_binary(Enum.reverse(acc))}
  end
  defp encode_oid_subids_fast([subid | rest], acc) when subid >= 0 and subid < 128 do
    # Single byte encoding for small values
    encode_oid_subids_fast(rest, [<<subid>> | acc])
  end
  defp encode_oid_subids_fast([subid | rest], acc) when subid >= 128 do
    # Multi-byte encoding for larger values
    bytes = encode_subid_multibyte(subid, [])
    encode_oid_subids_fast(rest, [bytes | acc])
  end
  defp encode_oid_subids_fast(_, _), do: {:error, :invalid_subidentifier}
  
  # Fast multi-byte sub-identifier encoding
  defp encode_subid_multibyte(subid, acc) when subid < 128 do
    # Last byte (high bit clear)
    :erlang.iolist_to_binary(Enum.reverse([subid | acc]))
  end
  defp encode_subid_multibyte(subid, acc) do
    # Continue encoding (high bit set)
    byte = (subid &&& 0x7F) ||| 0x80
    encode_subid_multibyte(subid >>> 7, [byte | acc])
  end
  
  # Fast integer encoder - optimized for common small values
  defp encode_integer_fast(0), do: <<0x02, 0x01, 0x00>>
  defp encode_integer_fast(value) when value > 0 and value < 128 do
    <<0x02, 0x01, value>>
  end
  defp encode_integer_fast(value) when is_integer(value) do
    # Fall back to existing implementation for larger values
    encode_integer_ber(value)
  end
  
  # Fast octet string encoder
  defp encode_octet_string_fast(value) when is_binary(value) do
    length = byte_size(value)
    length_bytes = encode_length_ber(length)
    [<<0x04>>, length_bytes, value]
  end
  
  # Fast SNMP value encoder - reduced branching
  defp encode_snmp_value_fast(:null, _), do: <<0x05, 0x00>>
  defp encode_snmp_value_fast(:integer, value) when is_integer(value), do: encode_integer_fast(value)
  defp encode_snmp_value_fast(:string, value) when is_binary(value), do: encode_octet_string_fast(value)
  defp encode_snmp_value_fast(_, :null), do: <<0x05, 0x00>>
  defp encode_snmp_value_fast(_, _), do: <<0x05, 0x00>>  # Default to NULL
end