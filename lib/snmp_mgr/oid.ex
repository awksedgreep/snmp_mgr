defmodule SNMPMgr.OID do
  @moduledoc """
  OID (Object Identifier) utility functions.
  
  Provides string to OID list conversion and vice versa.
  """

  @doc """
  Converts an OID string to a list of integers.

  ## Examples

      iex> SNMPMgr.OID.string_to_list("1.3.6.1.2.1.1.1.0")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}

      iex> SNMPMgr.OID.string_to_list("invalid")
      {:error, :invalid_oid}
  """
  def string_to_list(oid_string) when is_binary(oid_string) do
    try do
      oid_list = 
        oid_string
        |> String.split(".")
        |> Enum.map(&String.to_integer/1)
      
      if Enum.all?(oid_list, &(&1 >= 0)) do
        {:ok, oid_list}
      else
        {:error, :invalid_oid}
      end
    rescue
      _error -> {:error, :invalid_oid}
    end
  end

  def string_to_list(_), do: {:error, :invalid_oid}

  @doc """
  Converts an OID list to a string.

  ## Examples

      iex> SNMPMgr.OID.list_to_string([1, 3, 6, 1, 2, 1, 1, 1, 0])
      "1.3.6.1.2.1.1.1.0"
  """
  def list_to_string(oid_list) when is_list(oid_list) do
    if Enum.all?(oid_list, &is_integer/1) do
      Enum.join(oid_list, ".")
    else
      {:error, :invalid_oid_list}
    end
  end

  def list_to_string(_), do: {:error, :invalid_oid_list}

  @doc """
  Validates that an OID is properly formatted.
  """
  def valid?(oid_string) when is_binary(oid_string) do
    case string_to_list(oid_string) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def valid?(oid_list) when is_list(oid_list) do
    Enum.all?(oid_list, &(is_integer(&1) and &1 >= 0))
  end

  def valid?(_), do: false
end