defmodule SNMPMgr.Types do
  @moduledoc """
  SNMP data type handling and conversion.
  
  Handles encoding and decoding of SNMP values, including automatic type inference
  and explicit type specification.
  """

  @doc """
  Encodes a value for SNMP with optional type specification.

  ## Parameters
  - `value` - The value to encode
  - `opts` - Options including :type for explicit type specification

  ## Examples

      iex> SNMPMgr.Types.encode_value("Hello World")
      {:ok, {:string, "Hello World"}}

      iex> SNMPMgr.Types.encode_value(42)
      {:ok, {:integer, 42}}

      iex> SNMPMgr.Types.encode_value("192.168.1.1", type: :ipAddress)
      {:ok, {:ipAddress, {192, 168, 1, 1}}}
  """
  def encode_value(value, opts \\ []) do
    case Keyword.get(opts, :type) do
      nil -> infer_and_encode_type(value)
      type -> encode_with_explicit_type(value, type)
    end
  end

  @doc """
  Decodes an SNMP value to an Elixir term.

  ## Examples

      iex> SNMPMgr.Types.decode_value({:string, "Hello"})
      "Hello"

      iex> SNMPMgr.Types.decode_value({:integer, 42})
      42
  """
  def decode_value({:string, value}), do: to_string(value)
  def decode_value({:integer, value}), do: value
  def decode_value({:gauge32, value}), do: value
  def decode_value({:counter32, value}), do: value
  def decode_value({:counter64, value}), do: value
  def decode_value({:unsigned32, value}), do: value
  def decode_value({:timeticks, value}), do: value
  def decode_value({:ipAddress, {a, b, c, d}}), do: "#{a}.#{b}.#{c}.#{d}"
  def decode_value({:objectId, oid}), do: SNMPMgr.OID.list_to_string(oid)
  def decode_value({:opaque, value}), do: value
  def decode_value({:null, _}), do: nil
  
  # SNMPv2c specific exception values
  def decode_value(:noSuchObject), do: :no_such_object
  def decode_value(:noSuchInstance), do: :no_such_instance
  def decode_value(:endOfMibView), do: :end_of_mib_view
  
  def decode_value(value), do: value

  @doc """
  Automatically infers the SNMP type from an Elixir value.

  ## Examples

      iex> SNMPMgr.Types.infer_type("hello")
      :string

      iex> SNMPMgr.Types.infer_type(42)
      :integer

      iex> SNMPMgr.Types.infer_type("192.168.1.1")
      :string  # Would need explicit :ipAddress type
  """
  def infer_type(value) when is_binary(value), do: :string
  def infer_type(value) when is_integer(value) and value >= 0, do: :unsigned32
  def infer_type(value) when is_integer(value), do: :integer
  def infer_type(value) when is_list(value) do
    # Could be an OID list
    if Enum.all?(value, &is_integer/1) do
      :objectId
    else
      :string
    end
  end
  def infer_type(nil), do: :null
  def infer_type(_), do: :opaque

  # Private functions

  defp infer_and_encode_type(value) do
    type = infer_type(value)
    encode_with_inferred_type(value, type)
  end

  defp encode_with_inferred_type(value, :string) when is_binary(value) do
    {:ok, {:string, String.to_charlist(value)}}
  end

  defp encode_with_inferred_type(value, :integer) when is_integer(value) do
    {:ok, {:integer, value}}
  end

  defp encode_with_inferred_type(value, :unsigned32) when is_integer(value) and value >= 0 do
    {:ok, {:unsigned32, value}}
  end

  defp encode_with_inferred_type(value, :objectId) when is_list(value) do
    if Enum.all?(value, &is_integer/1) do
      {:ok, {:objectId, value}}
    else
      {:ok, {:string, String.to_charlist(to_string(value))}}
    end
  end

  defp encode_with_inferred_type(nil, :null) do
    {:ok, {:null, :null}}
  end

  defp encode_with_inferred_type(value, :opaque) do
    {:ok, {:opaque, value}}
  end

  defp encode_with_explicit_type(value, :string) when is_binary(value) do
    {:ok, {:string, String.to_charlist(value)}}
  end

  defp encode_with_explicit_type(value, :integer) when is_integer(value) do
    {:ok, {:integer, value}}
  end

  defp encode_with_explicit_type(value, :gauge32) when is_integer(value) and value >= 0 do
    {:ok, {:gauge32, value}}
  end

  defp encode_with_explicit_type(value, :counter32) when is_integer(value) and value >= 0 do
    {:ok, {:counter32, value}}
  end

  defp encode_with_explicit_type(value, :counter64) when is_integer(value) and value >= 0 do
    {:ok, {:counter64, value}}
  end

  defp encode_with_explicit_type(value, :unsigned32) when is_integer(value) and value >= 0 do
    {:ok, {:unsigned32, value}}
  end

  defp encode_with_explicit_type(value, :timeticks) when is_integer(value) and value >= 0 do
    {:ok, {:timeticks, value}}
  end

  defp encode_with_explicit_type(value, :ipAddress) when is_binary(value) do
    case parse_ip_address(value) do
      {:ok, ip_tuple} -> {:ok, {:ipAddress, ip_tuple}}
      :error -> {:error, {:invalid_ip_address, value}}
    end
  end

  defp encode_with_explicit_type(value, :ipAddress) when is_tuple(value) and tuple_size(value) == 4 do
    {:ok, {:ipAddress, value}}
  end

  defp encode_with_explicit_type(value, :objectId) when is_binary(value) do
    case SNMPMgr.OID.string_to_list(value) do
      {:ok, oid_list} -> {:ok, {:objectId, oid_list}}
      {:error, _} -> {:error, {:invalid_oid, value}}
    end
  end

  defp encode_with_explicit_type(value, :objectId) when is_list(value) do
    if Enum.all?(value, &is_integer/1) do
      {:ok, {:objectId, value}}
    else
      {:error, {:invalid_oid, value}}
    end
  end

  defp encode_with_explicit_type(value, :opaque) do
    {:ok, {:opaque, value}}
  end

  defp encode_with_explicit_type(nil, :null) do
    {:ok, {:null, :null}}
  end

  defp encode_with_explicit_type(_value, :null) do
    {:ok, {:null, :null}}
  end

  defp encode_with_explicit_type(value, type) do
    {:error, {:unsupported_type_conversion, value, type}}
  end

  defp parse_ip_address(ip_string) do
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, _} -> :error
    end
  end
end