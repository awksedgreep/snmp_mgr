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
    # Empty OID lists are invalid in SNMP
    length(oid_list) > 0 and Enum.all?(oid_list, &valid_component?/1)
  end
  
  # OID components must be non-negative integers within 32-bit range
  defp valid_component?(component) when is_integer(component) do
    component >= 0 and component <= 4294967295  # 2^32 - 1
  end
  
  defp valid_component?(_), do: false

  def valid?(_), do: false

  @doc """
  Compares two OIDs lexicographically.
  
  Returns:
  - `:equal` if OIDs are identical
  - `:less` if first OID is lexicographically smaller
  - `:greater` if first OID is lexicographically larger
  
  ## Examples
  
      iex> SNMPMgr.OID.compare([1, 3, 6, 1], [1, 3, 6, 1])
      :equal
      
      iex> SNMPMgr.OID.compare([1, 3, 6], [1, 3, 6, 1])
      :less
      
      iex> SNMPMgr.OID.compare([1, 3, 6, 2], [1, 3, 6, 1])
      :greater
  """
  def compare(oid1, oid2) when is_list(oid1) and is_list(oid2) do
    case {oid1, oid2} do
      {[], []} -> :equal
      {[], _} -> :less
      {_, []} -> :greater
      {[h1 | t1], [h2 | t2]} when h1 < h2 -> :less
      {[h1 | t1], [h2 | t2]} when h1 > h2 -> :greater
      {[h1 | t1], [h2 | t2]} when h1 == h2 -> compare(t1, t2)
    end
  end
  
  def compare(oid1, oid2) when is_binary(oid1) and is_binary(oid2) do
    with {:ok, list1} <- string_to_list(oid1),
         {:ok, list2} <- string_to_list(oid2) do
      compare(list1, list2)
    else
      _ -> {:error, :invalid_oid}
    end
  end
  
  def compare(_, _), do: {:error, :invalid_oid}

  @doc """
  Checks if the first OID is a prefix of the second OID.
  
  ## Examples
  
      iex> SNMPMgr.OID.is_prefix?([1, 3, 6], [1, 3, 6, 1, 2, 1])
      true
      
      iex> SNMPMgr.OID.is_prefix?([1, 3, 6, 2], [1, 3, 6, 1, 2, 1])
      false
      
      iex> SNMPMgr.OID.is_prefix?([1, 3, 6, 1, 2, 1], [1, 3, 6])
      false
  """
  def is_prefix?(prefix, oid) when is_list(prefix) and is_list(oid) do
    case {prefix, oid} do
      {[], _} -> true
      {_, []} -> false
      {[h | t1], [h | t2]} -> is_prefix?(t1, t2)
      _ -> false
    end
  end
  
  def is_prefix?(prefix, oid) when is_binary(prefix) and is_binary(oid) do
    with {:ok, prefix_list} <- string_to_list(prefix),
         {:ok, oid_list} <- string_to_list(oid) do
      is_prefix?(prefix_list, oid_list)
    else
      _ -> {:error, :invalid_oid}
    end
  end
  
  def is_prefix?(_, _), do: {:error, :invalid_oid}

  @doc """
  Appends two OIDs together.
  
  ## Examples
  
      iex> SNMPMgr.OID.append([1, 3, 6], [1, 2, 1])
      [1, 3, 6, 1, 2, 1]
      
      iex> SNMPMgr.OID.append("1.3.6", "1.2.1")
      "1.3.6.1.2.1"
  """
  def append(oid1, oid2) when is_list(oid1) and is_list(oid2) do
    oid1 ++ oid2
  end
  
  def append(oid1, oid2) when is_binary(oid1) and is_binary(oid2) do
    with {:ok, list1} <- string_to_list(oid1),
         {:ok, list2} <- string_to_list(oid2) do
      result_list = append(list1, list2)
      list_to_string(result_list)
    else
      _ -> {:error, :invalid_oid}
    end
  end
  
  def append(_, _), do: {:error, :invalid_oid}

  @doc """
  Gets the parent OID by removing the last element.
  
  ## Examples
  
      iex> SNMPMgr.OID.parent([1, 3, 6, 1, 2, 1])
      [1, 3, 6, 1, 2]
      
      iex> SNMPMgr.OID.parent([1])
      []
      
      iex> SNMPMgr.OID.parent([])
      {:error, :empty_oid}
  """
  def parent([]), do: {:error, :empty_oid}
  def parent([_]), do: []
  def parent(oid) when is_list(oid) do
    {_, [_]} = Enum.split(oid, length(oid) - 1)
    Enum.slice(oid, 0, length(oid) - 1)
  end
  
  def parent(oid) when is_binary(oid) do
    with {:ok, oid_list} <- string_to_list(oid) do
      case parent(oid_list) do
        {:error, reason} -> {:error, reason}
        parent_list -> list_to_string(parent_list)
      end
    else
      _ -> {:error, :invalid_oid}
    end
  end
  
  def parent(_), do: {:error, :invalid_oid}

  @doc """
  Creates a child OID by appending a single element.
  
  ## Examples
  
      iex> SNMPMgr.OID.child([1, 3, 6, 1, 2], 1)
      [1, 3, 6, 1, 2, 1]
      
      iex> SNMPMgr.OID.child("1.3.6.1.2", 1)
      "1.3.6.1.2.1"
  """
  def child(oid, element) when is_list(oid) and is_integer(element) do
    oid ++ [element]
  end
  
  def child(oid, element) when is_binary(oid) and is_integer(element) do
    with {:ok, oid_list} <- string_to_list(oid) do
      result_list = child(oid_list, element)
      list_to_string(result_list)
    else
      _ -> {:error, :invalid_oid}
    end
  end
  
  def child(_, _), do: {:error, :invalid_oid}
end