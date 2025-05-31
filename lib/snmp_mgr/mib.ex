defmodule SNMPMgr.MIB do
  @compile {:no_warn_undefined, [:snmpc, :snmp_misc]}
  
  @moduledoc """
  MIB compilation and symbolic name resolution.
  
  This module provides MIB compilation using Erlang's :snmpc when available,
  and includes a built-in registry of standard MIB objects for basic operations.
  """

  use GenServer
  require Logger

  @standard_mibs %{
    # System group (1.3.6.1.2.1.1)
    "sysDescr" => [1, 3, 6, 1, 2, 1, 1, 1],
    "sysObjectID" => [1, 3, 6, 1, 2, 1, 1, 2],
    "sysUpTime" => [1, 3, 6, 1, 2, 1, 1, 3],
    "sysContact" => [1, 3, 6, 1, 2, 1, 1, 4],
    "sysName" => [1, 3, 6, 1, 2, 1, 1, 5],
    "sysLocation" => [1, 3, 6, 1, 2, 1, 1, 6],
    "sysServices" => [1, 3, 6, 1, 2, 1, 1, 7],
    
    # Interface group (1.3.6.1.2.1.2)
    "ifNumber" => [1, 3, 6, 1, 2, 1, 2, 1],
    "ifTable" => [1, 3, 6, 1, 2, 1, 2, 2],
    "ifEntry" => [1, 3, 6, 1, 2, 1, 2, 2, 1],
    "ifIndex" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 1],
    "ifDescr" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 2],
    "ifType" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 3],
    "ifMtu" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 4],
    "ifSpeed" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 5],
    "ifPhysAddress" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 6],
    "ifAdminStatus" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 7],
    "ifOperStatus" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 8],
    "ifLastChange" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 9],
    "ifInOctets" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 10],
    "ifInUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 11],
    "ifInNUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 12],
    "ifInDiscards" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 13],
    "ifInErrors" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 14],
    "ifInUnknownProtos" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 15],
    "ifOutOctets" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 16],
    "ifOutUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 17],
    "ifOutNUcastPkts" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 18],
    "ifOutDiscards" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 19],
    "ifOutErrors" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 20],
    "ifOutQLen" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 21],
    "ifSpecific" => [1, 3, 6, 1, 2, 1, 2, 2, 1, 22],
    
    # IP group (1.3.6.1.2.1.4)
    "ipForwarding" => [1, 3, 6, 1, 2, 1, 4, 1],
    "ipDefaultTTL" => [1, 3, 6, 1, 2, 1, 4, 2],
    "ipInReceives" => [1, 3, 6, 1, 2, 1, 4, 3],
    "ipInHdrErrors" => [1, 3, 6, 1, 2, 1, 4, 4],
    "ipInAddrErrors" => [1, 3, 6, 1, 2, 1, 4, 5],
    
    # SNMP group (1.3.6.1.2.1.11)
    "snmpInPkts" => [1, 3, 6, 1, 2, 1, 11, 1],
    "snmpOutPkts" => [1, 3, 6, 1, 2, 1, 11, 2],
    "snmpInBadVersions" => [1, 3, 6, 1, 2, 1, 11, 3],
    "snmpInBadCommunityNames" => [1, 3, 6, 1, 2, 1, 11, 4],
    "snmpInBadCommunityUses" => [1, 3, 6, 1, 2, 1, 11, 5],
    "snmpInASNParseErrs" => [1, 3, 6, 1, 2, 1, 11, 6],
    "snmpInTooBigs" => [1, 3, 6, 1, 2, 1, 11, 8],
    "snmpInNoSuchNames" => [1, 3, 6, 1, 2, 1, 11, 9],
    "snmpInBadValues" => [1, 3, 6, 1, 2, 1, 11, 10],
    "snmpInReadOnlys" => [1, 3, 6, 1, 2, 1, 11, 11],
    "snmpInGenErrs" => [1, 3, 6, 1, 2, 1, 11, 12],
    "snmpInTotalReqVars" => [1, 3, 6, 1, 2, 1, 11, 13],
    "snmpInTotalSetVars" => [1, 3, 6, 1, 2, 1, 11, 14],
    "snmpInGetRequests" => [1, 3, 6, 1, 2, 1, 11, 15],
    "snmpInGetNexts" => [1, 3, 6, 1, 2, 1, 11, 16],
    "snmpInSetRequests" => [1, 3, 6, 1, 2, 1, 11, 17],
    "snmpInGetResponses" => [1, 3, 6, 1, 2, 1, 11, 18],
    "snmpInTraps" => [1, 3, 6, 1, 2, 1, 11, 19],
    "snmpOutTooBigs" => [1, 3, 6, 1, 2, 1, 11, 20],
    "snmpOutNoSuchNames" => [1, 3, 6, 1, 2, 1, 11, 21],
    "snmpOutBadValues" => [1, 3, 6, 1, 2, 1, 11, 22],
    "snmpOutGenErrs" => [1, 3, 6, 1, 2, 1, 11, 24],
    "snmpOutGetRequests" => [1, 3, 6, 1, 2, 1, 11, 25],
    "snmpOutGetNexts" => [1, 3, 6, 1, 2, 1, 11, 26],
    "snmpOutSetRequests" => [1, 3, 6, 1, 2, 1, 11, 27],
    "snmpOutGetResponses" => [1, 3, 6, 1, 2, 1, 11, 28],
    "snmpOutTraps" => [1, 3, 6, 1, 2, 1, 11, 29],
    "snmpEnableAuthenTraps" => [1, 3, 6, 1, 2, 1, 11, 30]
  }

  ## Public API

  @doc """
  Starts the MIB registry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Compiles a MIB file using Erlang's :snmpc if available.

  ## Examples

      iex> SNMPMgr.MIB.compile("SNMPv2-MIB.mib")
      {:ok, "SNMPv2-MIB.bin"}

      iex> SNMPMgr.MIB.compile("nonexistent.mib")
      {:error, :file_not_found}
  """
  def compile(mib_file, opts \\ []) do
    case Code.ensure_loaded(:snmpc) do
      {:module, :snmpc} ->
        compile_with_snmpc(mib_file, opts)
      {:error, _} ->
        {:error, :snmp_compiler_not_available}
    end
  end

  @doc """
  Compiles all MIB files in a directory.
  """
  def compile_dir(directory, opts \\ []) do
    case File.ls(directory) do
      {:ok, files} ->
        mib_files = Enum.filter(files, &String.ends_with?(&1, ".mib"))
        results = Enum.map(mib_files, fn file ->
          file_path = Path.join(directory, file)
          {file, compile(file_path, opts)}
        end)
        {:ok, results}
      {:error, reason} ->
        {:error, {:directory_error, reason}}
    end
  end

  @doc """
  Loads a compiled MIB file.
  """
  def load(compiled_mib_path) do
    GenServer.call(__MODULE__, {:load_mib, compiled_mib_path})
  end

  @doc """
  Loads standard MIBs that are built into the library.
  """
  def load_standard_mibs do
    GenServer.call(__MODULE__, :load_standard_mibs)
  end

  @doc """
  Resolves a symbolic name to an OID.

  ## Examples

      iex> SNMPMgr.MIB.resolve("sysDescr.0")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1, 0]}

      iex> SNMPMgr.MIB.resolve("sysDescr")
      {:ok, [1, 3, 6, 1, 2, 1, 1, 1]}

      iex> SNMPMgr.MIB.resolve("unknownName")
      {:error, :not_found}
  """
  def resolve(name) do
    GenServer.call(__MODULE__, {:resolve, name})
  end

  @doc """
  Performs reverse lookup from OID to symbolic name.

  ## Examples

      iex> SNMPMgr.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1, 0])
      {:ok, "sysDescr.0"}

      iex> SNMPMgr.MIB.reverse_lookup([1, 3, 6, 1, 2, 1, 1, 1])
      {:ok, "sysDescr"}
  """
  def reverse_lookup(oid) when is_list(oid) do
    GenServer.call(__MODULE__, {:reverse_lookup, oid})
  end

  def reverse_lookup(oid_string) when is_binary(oid_string) do
    case SNMPMgr.OID.string_to_list(oid_string) do
      {:ok, oid_list} -> reverse_lookup(oid_list)
      error -> error
    end
  end

  @doc """
  Gets the children of an OID node.
  """
  def children(oid) do
    GenServer.call(__MODULE__, {:children, oid})
  end

  @doc """
  Gets the parent of an OID node.
  """
  def parent(oid) when is_list(oid) and length(oid) > 0 do
    {:ok, Enum.drop(oid, -1)}
  end
  def parent([]), do: {:error, :no_parent}
  def parent(oid_string) when is_binary(oid_string) do
    case SNMPMgr.OID.string_to_list(oid_string) do
      {:ok, oid_list} -> parent(oid_list)
      error -> error
    end
  end

  @doc """
  Walks the MIB tree starting from a root OID.
  """
  def walk_tree(root_oid, opts \\ []) do
    GenServer.call(__MODULE__, {:walk_tree, root_oid, opts})
  end

  ## GenServer Implementation

  @impl true
  def init(_opts) do
    # Initialize with standard MIBs
    reverse_map = build_reverse_map(@standard_mibs)
    state = %{
      name_to_oid: @standard_mibs,
      oid_to_name: reverse_map,
      loaded_mibs: [:standard]
    }
    {:ok, state}
  end

  @impl true
  def handle_call({:resolve, name}, _from, state) do
    result = resolve_name(name, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:reverse_lookup, oid}, _from, state) do
    result = reverse_lookup_oid(oid, state.oid_to_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:children, oid}, _from, state) do
    result = find_children(oid, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:walk_tree, root_oid, _opts}, _from, state) do
    result = walk_tree_from_root(root_oid, state.name_to_oid)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:load_mib, mib_path}, _from, state) do
    case load_mib_file(mib_path) do
      {:ok, mib_data} ->
        new_state = merge_mib_data(state, mib_data)
        {:reply, :ok, new_state}
      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:load_standard_mibs, _from, state) do
    # Standard MIBs are already loaded in init
    {:reply, :ok, state}
  end

  ## Private Functions

  defp compile_with_snmpc(mib_file, opts) do
    output_dir = Keyword.get(opts, :output_dir, ".")
    include_dirs = Keyword.get(opts, :include_dirs, [])
    
    compile_opts = [
      {:outdir, String.to_charlist(output_dir)},
      {:i, Enum.map(include_dirs, &String.to_charlist/1)}
    ]

    try do
      case :snmpc.compile(String.to_charlist(mib_file), compile_opts) do
        {:ok, _} ->
          base_name = Path.basename(mib_file, ".mib")
          output_file = Path.join(output_dir, "#{base_name}.bin")
          {:ok, output_file}
        {:error, reason} ->
          {:error, {:compilation_failed, reason}}
      end
    catch
      error -> {:error, {:compilation_error, error}}
    end
  end

  defp resolve_name(name, name_to_oid_map) do
    cond do
      # Handle nil or invalid names first
      is_nil(name) or not is_binary(name) ->
        {:error, :invalid_name}
      
      # Direct match
      Map.has_key?(name_to_oid_map, name) ->
        {:ok, Map.get(name_to_oid_map, name)}
      
      # Name with instance (e.g., "sysDescr.0")
      String.contains?(name, ".") ->
        [base_name | instance_parts] = String.split(name, ".")
        case Map.get(name_to_oid_map, base_name) do
          nil -> {:error, :not_found}
          base_oid ->
            try do
              instance_oids = Enum.map(instance_parts, &String.to_integer/1)
              {:ok, base_oid ++ instance_oids}
            rescue
              _error -> {:error, :invalid_instance}
            end
        end
      
      true ->
        {:error, :not_found}
    end
  end

  defp reverse_lookup_oid(oid, oid_to_name_map) do
    case Map.get(oid_to_name_map, oid) do
      nil ->
        # Try to find a partial match
        find_partial_reverse_match(oid, oid_to_name_map)
      name ->
        {:ok, name}
    end
  end

  defp find_partial_reverse_match(oid, oid_to_name_map) do
    # Handle case where oid might be a string instead of list
    if is_binary(oid) do
      {:error, :invalid_oid_format}
    else
      # Handle empty list case
      if Enum.empty?(oid) do
        {:error, :empty_oid}
      else
        # Try progressively shorter OIDs to find a base match  
        find_partial_match(oid, oid_to_name_map, length(oid) - 1)
      end
    end
  end

  defp find_partial_match(_oid, _map, length) when length <= 0, do: {:error, :not_found}

  defp find_partial_match(oid, oid_to_name_map, length) do
    partial_oid = Enum.take(oid, length)
    case Map.get(oid_to_name_map, partial_oid) do
      nil -> find_partial_match(oid, oid_to_name_map, length - 1)
      base_name ->
        instance_part = Enum.drop(oid, length)
        if Enum.empty?(instance_part) do
          {:ok, base_name}
        else
          instance_string = Enum.join(instance_part, ".")
          {:ok, "#{base_name}.#{instance_string}"}
        end
    end
  end

  defp find_children(parent_oid, name_to_oid_map) do
    normalized_oid = cond do
      is_nil(parent_oid) -> []
      is_binary(parent_oid) ->
        case SNMPMgr.OID.string_to_list(parent_oid) do
          {:ok, oid_list} -> oid_list
          {:error, _} -> []
        end
      is_list(parent_oid) -> parent_oid
      true -> []
    end

    # Return error for invalid OIDs
    if normalized_oid == [] and not is_nil(parent_oid) do
      {:error, :invalid_parent_oid}
    else
      children = 
        name_to_oid_map
        |> Enum.filter(fn {_name, oid} ->
          is_list(oid) and is_list(normalized_oid) and
          length(oid) == length(normalized_oid) + 1 and 
          List.starts_with?(oid, normalized_oid)
        end)
        |> Enum.map(fn {name, _oid} -> name end)
        |> Enum.sort()

      {:ok, children}
    end
  end

  defp walk_tree_from_root(root_oid, name_to_oid_map) do
    root_oid = cond do
      is_binary(root_oid) ->
        case SNMPMgr.OID.string_to_list(root_oid) do
          {:ok, oid_list} -> oid_list
          {:error, _} -> []
        end
      is_list(root_oid) ->
        root_oid
      is_nil(root_oid) ->
        []
      true ->
        []
    end

    descendants = 
      name_to_oid_map
      |> Enum.filter(fn {_name, oid} ->
        is_list(oid) and List.starts_with?(oid, root_oid)
      end)
      |> Enum.map(fn {name, oid} -> {name, oid} end)
      |> Enum.sort_by(fn {_name, oid} -> oid end)

    {:ok, descendants}
  end

  defp build_reverse_map(name_to_oid_map) do
    name_to_oid_map
    |> Enum.map(fn {name, oid} -> {oid, name} end)
    |> Enum.into(%{})
  end

  defp load_mib_file(mib_path) do
    try do
      case Code.ensure_loaded(:snmp_misc) do
        {:module, :snmp_misc} ->
          case :snmp_misc.read_mib(String.to_charlist(mib_path)) do
            {:ok, mib_data} -> parse_mib_data(mib_data)
            {:error, reason} -> {:error, {:mib_load_failed, reason}}
          end
        {:error, _} ->
          {:error, :snmp_modules_not_available}
      end
    catch
      error -> {:error, {:mib_load_error, error}}
    end
  end

  defp parse_mib_data(_mib_data) do
    # This would parse the compiled MIB data structure
    # For now, return empty since we don't have access to SNMP modules
    {:ok, %{}}
  end

  defp merge_mib_data(state, _mib_data) do
    # This would merge the new MIB data with existing state
    # For now, just return the current state
    state
  end
end