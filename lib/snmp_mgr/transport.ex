defmodule SNMPMgr.Transport do
  @moduledoc """
  Transport layer for SNMP operations, providing UDP socket management
  and connection pooling capabilities.
  """

  require Logger
  
  # Default socket options for SNMP UDP sockets
  @default_socket_opts [
    :binary,
    {:active, false},
    {:reuseaddr, true}
  ]

  @doc """
  Creates a UDP socket for SNMP communication.
  
  Options:
  - :port - Port number to bind to (default: 0 for auto-assignment)
  - :socket_opts - Additional socket options (merged with defaults)
  """
  def create_socket(opts \\ []) do
    port = Keyword.get(opts, :port, 0)
    socket_opts = Keyword.get(opts, :socket_opts, [])
    
    # Validate port range
    if port < 0 or port > 65535 do
      {:error, :invalid_port}
    else
      final_opts = Keyword.merge(@default_socket_opts, socket_opts)
      
      try do
        case :gen_udp.open(port, final_opts) do
          {:ok, socket} ->
            Logger.debug("Created UDP socket #{inspect(socket)} on port #{port}")
            {:ok, socket}
            
          {:error, reason} ->
            Logger.warning("Failed to create UDP socket on port #{port}: #{inspect(reason)}")
            {:error, reason}
        end
      rescue
        ArgumentError ->
          {:error, :invalid_port}
        e ->
          Logger.error("Exception creating socket: #{inspect(e)}")
          {:error, {:socket_creation_exception, e}}
      end
    end
  end

  @doc """
  Gets information about a UDP socket.
  """
  def get_socket_info(socket) do
    try do
      case :inet.getopts(socket, [:port, :active, :binary]) do
        {:ok, opts} ->
          case :inet.sockname(socket) do
            {:ok, {ip, port}} ->
              {:ok, %{
                socket: socket,
                port: port,
                local_address: ip,
                options: opts
              }}
            {:error, reason} ->
              {:error, {:sockname_failed, reason}}
          end
          
        {:error, reason} ->
          {:error, {:getopts_failed, reason}}
      end
    rescue
      e ->
        {:error, {:socket_info_error, e}}
    end
  end

  @doc """
  Closes a UDP socket.
  """
  def close_socket(socket) do
    try do
      case :gen_udp.close(socket) do
        :ok ->
          Logger.debug("Closed UDP socket #{inspect(socket)}")
          :ok
        {:error, reason} ->
          Logger.warning("Failed to close socket #{inspect(socket)}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception closing socket #{inspect(socket)}: #{inspect(e)}")
        {:error, {:close_exception, e}}
    end
  end

  @doc """
  Sends a message via UDP socket.
  """
  def send_message(socket, message, {destination, port}) when is_binary(message) do
    # Convert string addresses to charlists for gen_udp
    resolved_destination = case destination do
      dest when is_binary(dest) -> String.to_charlist(dest)
      dest when is_list(dest) -> dest
      dest when is_tuple(dest) -> dest
      dest -> dest
    end
    
    try do
      case :gen_udp.send(socket, resolved_destination, port, message) do
        :ok ->
          dest_str = case destination do
            dest when is_binary(dest) -> dest
            dest when is_tuple(dest) -> :inet.ntoa(dest) |> to_string()
            dest -> inspect(dest)
          end
          Logger.debug("Sent #{byte_size(message)} bytes to #{dest_str}:#{port}")
          :ok
        {:error, reason} ->
          dest_str = case destination do
            dest when is_binary(dest) -> dest
            dest when is_tuple(dest) -> :inet.ntoa(dest) |> to_string()
            dest -> inspect(dest)
          end
          Logger.warning("Failed to send message to #{dest_str}:#{port}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception sending message: #{inspect(e)}")
        {:error, {:send_exception, e}}
    end
  end

  # 4-argument version for backward compatibility
  def send_message(socket, destination, port, message) when is_binary(message) do
    send_message(socket, message, {destination, port})
  end

  @doc """
  Receives a message from UDP socket with timeout.
  """
  def receive_message(socket, opts \\ []) do
    timeout = case opts do
      timeout when is_integer(timeout) -> timeout
      opts when is_list(opts) -> Keyword.get(opts, :timeout, 5000)
      _ -> 5000
    end
    
    try do
      case :gen_udp.recv(socket, 0, timeout) do
        {:ok, {address, port, packet}} ->
          Logger.debug("Received #{byte_size(packet)} bytes from #{inspect(address)}:#{port}")
          # Return format expected by tests: {message, sender_info}
          {:ok, {packet, %{address: address, port: port}}}
          
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception receiving message: #{inspect(e)}")
        {:error, {:receive_exception, e}}
    end
  end

  ## Connection Pool Functions

  @doc """
  Creates a connection pool for managing multiple UDP sockets.
  """
  def create_connection_pool(opts \\ []) do
    pool_size = Keyword.get(opts, :pool_size, 5)
    socket_opts = Keyword.get(opts, :socket_opts, [])
    
    try do
      connections = for i <- 1..pool_size do
        case create_socket(socket_opts: socket_opts) do
          {:ok, socket} ->
            %{
              id: make_ref(),
              socket: socket,
              available: true,
              created_at: System.monotonic_time(:millisecond),
              last_used: System.monotonic_time(:millisecond),
              usage_count: 0
            }
          {:error, reason} ->
            Logger.warning("Failed to create socket #{i} in pool: #{inspect(reason)}")
            nil
        end
      end
      
      valid_connections = Enum.filter(connections, & &1 != nil)
      
      if length(valid_connections) > 0 do
        pool = %{
          connections: valid_connections,
          pool_size: pool_size,
          created_at: System.monotonic_time(:millisecond),
          stats: %{
            checkouts: 0,
            checkins: 0,
            created: length(valid_connections),
            errors: pool_size - length(valid_connections)
          }
        }
        
        Logger.info("Created connection pool with #{length(valid_connections)}/#{pool_size} connections")
        {:ok, pool}
      else
        {:error, :no_connections_created}
      end
    rescue
      e ->
        Logger.error("Exception creating connection pool: #{inspect(e)}")
        {:error, {:pool_creation_exception, e}}
    end
  end

  @doc """
  Checks out an available connection from the pool.
  """
  def checkout_connection(pool) do
    available_connections = Enum.filter(pool.connections, & &1.available)
    
    case available_connections do
      [connection | _] ->
        updated_connection = %{connection | 
          available: false,
          last_used: System.monotonic_time(:millisecond),
          usage_count: connection.usage_count + 1
        }
        
        updated_connections = Enum.map(pool.connections, fn conn ->
          if conn.id == connection.id, do: updated_connection, else: conn
        end)
        
        updated_pool = %{pool | 
          connections: updated_connections,
          stats: %{pool.stats | checkouts: pool.stats.checkouts + 1}
        }
        
        {:ok, connection.socket, updated_pool}
        
      [] ->
        {:error, :no_available_connections}
    end
  end

  @doc """
  Checks out an available connection from the pool with timeout.
  """
  def checkout_connection(pool, opts) when is_list(opts) do
    _timeout = Keyword.get(opts, :timeout, 5000)
    # For now, just delegate to the basic version
    # In a real implementation, this might wait for connections to become available
    checkout_connection(pool)
  end

  @doc """
  Checks in a connection back to the pool.
  """
  def checkin_connection(pool, socket) do
    case Enum.find(pool.connections, fn conn -> conn.socket == socket end) do
      nil ->
        {:error, :connection_not_found}
        
      connection ->
        updated_connection = %{connection | 
          available: true,
          last_used: System.monotonic_time(:millisecond)
        }
        
        updated_connections = Enum.map(pool.connections, fn conn ->
          if conn.id == connection.id, do: updated_connection, else: conn
        end)
        
        updated_pool = %{pool | 
          connections: updated_connections,
          stats: %{pool.stats | checkins: pool.stats.checkins + 1}
        }
        
        {:ok, updated_pool}
    end
  end

  @doc """
  Gets statistics for the connection pool.
  """
  def get_pool_stats(pool) do
    available = Enum.count(pool.connections, & &1.available)
    in_use = length(pool.connections) - available
    
    stats = %{
      total_connections: length(pool.connections),
      available_connections: available,
      in_use_connections: in_use,
      pool_size: pool.pool_size,
      created_at: pool.created_at,
      stats: pool.stats
    }
    
    {:ok, stats}
  end

  @doc """
  Closes the connection pool and all its sockets.
  """
  def close_connection_pool(pool) do
    results = for connection <- pool.connections do
      close_socket(connection.socket)
    end
    
    errors = Enum.count(results, fn result -> match?({:error, _}, result) end)
    
    if errors == 0 do
      Logger.info("Closed connection pool with #{length(pool.connections)} connections")
      :ok
    else
      Logger.warning("Closed connection pool with #{errors} errors")
      {:ok, %{errors: errors, total: length(pool.connections)}}
    end
  end
end