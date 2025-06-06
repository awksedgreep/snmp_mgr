alias SnmpMgr.PDU

# Start with a simple case that works
IO.puts("=== Testing Small PDU (should work) ===")
small_varbinds = for i <- 1..5 do
  {[1, 3, 6, 1, 4, 1, 1, i], :null, :null}
end

{:ok, small_pdu} = PDU.build_get_request_multi(small_varbinds, 12345)
small_message = PDU.build_message(small_pdu, "public", :v1)

case PDU.encode_message(small_message) do
  {:ok, small_encoded} ->
    IO.puts("Small PDU encoded successfully: #{byte_size(small_encoded)} bytes")
    case PDU.decode_message(small_encoded) do
      {:ok, small_decoded} ->
        IO.puts("Small PDU decoded successfully: #{length(small_decoded.pdu["varbinds"])} varbinds")
      {:error, reason} ->
        IO.puts("Small PDU decode failed: #{inspect(reason)}")
    end
  {:error, reason} ->
    IO.puts("Small PDU encode failed: #{inspect(reason)}")
end

# Now test progressively larger PDUs to find the breaking point
IO.puts("\n=== Testing Progressively Larger PDUs ===")
test_sizes = [10, 20, 50, 100]

for size <- test_sizes do
  IO.puts("\n--- Testing #{size} varbinds ---")
  
  large_varbinds = for i <- 1..size do
    {[1, 3, 6, 1, 4, 1, 1, i], :null, :null}
  end
  
  {:ok, large_pdu} = PDU.build_get_request_multi(large_varbinds, 12345)
  large_message = PDU.build_message(large_pdu, "public", :v1)
  
  case PDU.encode_message(large_message) do
    {:ok, large_encoded} ->
      IO.puts("#{size} varbinds encoded successfully: #{byte_size(large_encoded)} bytes")
      
      # Debug: Show the first 50 bytes of the encoded message
      first_50 = binary_part(large_encoded, 0, min(50, byte_size(large_encoded)))
      IO.puts("First 50 bytes: #{inspect(first_50)}")
      
      case PDU.decode_message(large_encoded) do
        {:ok, large_decoded} ->
          IO.puts("#{size} varbinds decoded successfully: #{length(large_decoded.pdu["varbinds"])} varbinds")
        {:error, reason} ->
          IO.puts("#{size} varbinds decode failed: #{inspect(reason)}")
          
          # Let's try to understand why by checking the message structure
          case large_encoded do
            <<48, length, rest::binary>> ->
              IO.puts("Message is SEQUENCE with length #{length}, remaining bytes: #{byte_size(rest)}")
              if length != byte_size(rest) do
                IO.puts("LENGTH MISMATCH! Expected #{length} bytes, got #{byte_size(rest)}")
              end
            _ ->
              IO.puts("Message doesn't start with SEQUENCE tag")
          end
      end
    {:error, reason} ->
      IO.puts("#{size} varbinds encode failed: #{inspect(reason)}")
  end
end