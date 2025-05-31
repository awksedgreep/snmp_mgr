defmodule SNMPMgr.Errors do
  @moduledoc """
  SNMP error handling and error code translation.
  
  Provides functions to handle both SNMPv1 and SNMPv2c error conditions
  and translate error codes to human-readable messages.
  """

  # SNMPv1 and SNMPv2c error codes
  @error_codes %{
    0 => :no_error,
    1 => :too_big,
    2 => :no_such_name,
    3 => :bad_value,
    4 => :read_only,
    5 => :gen_err,
    
    # SNMPv2c additional error codes
    6 => :no_access,
    7 => :wrong_type,
    8 => :wrong_length,
    9 => :wrong_encoding,
    10 => :wrong_value,
    11 => :no_creation,
    12 => :inconsistent_value,
    13 => :resource_unavailable,
    14 => :commit_failed,
    15 => :undo_failed,
    16 => :authorization_error,
    17 => :not_writable,
    18 => :inconsistent_name
  }

  @error_descriptions %{
    :no_error => "No error occurred",
    :too_big => "Response too big to fit in message",
    :no_such_name => "Variable name not found",
    :bad_value => "Invalid value for variable",
    :read_only => "Variable is read-only",
    :gen_err => "General error",
    
    # SNMPv2c additional errors
    :no_access => "Access denied",
    :wrong_type => "Wrong data type",
    :wrong_length => "Wrong data length",
    :wrong_encoding => "Wrong encoding",
    :wrong_value => "Wrong value",
    :no_creation => "Cannot create variable",
    :inconsistent_value => "Inconsistent value",
    :resource_unavailable => "Resource unavailable",
    :commit_failed => "Commit failed",
    :undo_failed => "Undo failed",
    :authorization_error => "Authorization failed",
    :not_writable => "Variable not writable",
    :inconsistent_name => "Inconsistent name"
  }

  @doc """
  Translates an SNMP error code to an atom.

  ## Examples

      iex> SNMPMgr.Errors.code_to_atom(2)
      :no_such_name

      iex> SNMPMgr.Errors.code_to_atom(0)
      :no_error

      iex> SNMPMgr.Errors.code_to_atom(999)
      :unknown_error
  """
  def code_to_atom(error_code) when is_integer(error_code) do
    Map.get(@error_codes, error_code, :unknown_error)
  end

  @doc """
  Translates an SNMP error atom to a human-readable description.

  ## Examples

      iex> SNMPMgr.Errors.description(:no_such_name)
      "Variable name not found"

      iex> SNMPMgr.Errors.description(:too_big)
      "Response too big to fit in message"

      iex> SNMPMgr.Errors.description(:unknown_error)
      "Unknown error"
  """
  def description(error_atom) when is_atom(error_atom) do
    Map.get(@error_descriptions, error_atom, "Unknown error")
  end

  @doc """
  Translates an error code directly to a description.

  ## Examples

      iex> SNMPMgr.Errors.code_to_description(2)
      "Variable name not found"

      iex> SNMPMgr.Errors.code_to_description(18)
      "Inconsistent name"
  """
  def code_to_description(error_code) when is_integer(error_code) do
    error_code
    |> code_to_atom()
    |> description()
  end

  @doc """
  Determines if an error is version-specific.

  ## Examples

      iex> SNMPMgr.Errors.is_v2c_error?(:no_access)
      true

      iex> SNMPMgr.Errors.is_v2c_error?(:no_such_name)
      false
  """
  def is_v2c_error?(error_atom) do
    v2c_errors = [
      :no_access, :wrong_type, :wrong_length, :wrong_encoding,
      :wrong_value, :no_creation, :inconsistent_value, :resource_unavailable,
      :commit_failed, :undo_failed, :authorization_error, :not_writable,
      :inconsistent_name
    ]
    
    error_atom in v2c_errors
  end

  @doc """
  Formats an SNMP error for display.

  ## Examples

      iex> SNMPMgr.Errors.format_error({:snmp_error, 2})
      "SNMP Error (2): Variable name not found"

      iex> SNMPMgr.Errors.format_error({:snmp_error, :no_such_name})
      "SNMP Error: Variable name not found"

      iex> SNMPMgr.Errors.format_error({:v2c_error, :no_access, oid: "1.2.3.4"})
      "SNMPv2c Error: Access denied (OID: 1.2.3.4)"
  """
  def format_error({:snmp_error, error_code}) when is_integer(error_code) do
    error_atom = code_to_atom(error_code)
    desc = description(error_atom)
    "SNMP Error (#{error_code}): #{desc}"
  end

  def format_error({:snmp_error, error_atom}) when is_atom(error_atom) do
    desc = description(error_atom)
    "SNMP Error: #{desc}"
  end

  def format_error({:v2c_error, error_atom}) when is_atom(error_atom) do
    desc = description(error_atom)
    "SNMPv2c Error: #{desc}"
  end

  def format_error({:v2c_error, error_atom, details}) when is_atom(error_atom) do
    desc = description(error_atom)
    detail_str = format_error_details(details)
    "SNMPv2c Error: #{desc}#{detail_str}"
  end

  def format_error({:network_error, reason}) do
    "Network Error: #{inspect(reason)}"
  end

  def format_error({:timeout, _}) do
    "Request timed out"
  end

  def format_error({:encoding_error, reason}) do
    "Encoding Error: #{inspect(reason)}"
  end

  def format_error({:decoding_error, reason}) do
    "Decoding Error: #{inspect(reason)}"
  end

  def format_error(error) do
    "Unknown Error: #{inspect(error)}"
  end

  @doc """
  Checks if an error is recoverable (can be retried).

  ## Examples

      iex> SNMPMgr.Errors.recoverable?({:network_error, :host_unreachable})
      false

      iex> SNMPMgr.Errors.recoverable?({:snmp_error, :too_big})
      true

      iex> SNMPMgr.Errors.recoverable?(:timeout)
      true
  """
  def recoverable?({:network_error, :host_unreachable}), do: false
  def recoverable?({:network_error, :network_unreachable}), do: false
  def recoverable?({:snmp_error, :no_such_name}), do: false
  def recoverable?({:snmp_error, :bad_value}), do: false
  def recoverable?({:snmp_error, :read_only}), do: false
  def recoverable?({:v2c_error, :no_access}), do: false
  def recoverable?({:v2c_error, :not_writable}), do: false
  def recoverable?({:v2c_error, :wrong_type}), do: false
  def recoverable?(:timeout), do: true
  def recoverable?({:snmp_error, :too_big}), do: true
  def recoverable?({:snmp_error, :gen_err}), do: true
  def recoverable?(_), do: false

  # Private functions

  defp format_error_details(details) when is_list(details) do
    formatted = 
      details
      |> Enum.map(fn
        {:oid, oid} -> "OID: #{oid}"
        {:index, index} -> "Index: #{index}"
        {:value, value} -> "Value: #{inspect(value)}"
        {key, value} -> "#{key}: #{value}"
      end)
      |> Enum.join(", ")
    
    if formatted != "", do: " (#{formatted})", else: ""
  end

  defp format_error_details(_), do: ""
end