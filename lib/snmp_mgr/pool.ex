defmodule SNMPMgr.Pool do
  @moduledoc """
  High-performance UDP socket connection pool for SNMP operations.
  
  This module manages a pool of UDP sockets with intelligent connection reuse,
  automatic cleanup, and performance monitoring. It provides efficient socket
  management for high-throughput SNMP operations.
  """
  
  use GenServer
  require Logger
  
  @default_pool_size 10
  @default_max_idle_time 300_000  # 5 minutes
  @default_cleanup_interval 60_000  # 1 minute
  @default_socket_opts [:binary, {:active, true}, {:reuseaddr, true}]
  
  defstruct [
    :name,
    :pool_size,
    :max_idle_time,
    :cleanup_interval,
    :socket_opts,
    :connections,
    :available,
    :metrics,
    :cleanup_timer
  ]
  
  @doc """
  Starts the connection pool.
  
  ## Options
  - `:pool_size` - Maximum number of connections (default: 10)
  - `:max_idle_time` - Max idle time before connection cleanup in ms (default: 300000)
  - `:cleanup_interval` - Cleanup check interval in ms (default: 60000)
  - `:socket_opts` - UDP socket options
  
  ## Examples
  
      {:ok, pool} = SNMPMgr.Pool.start_link(
        pool_size: 20,
        max_idle_time: 600_000
      )
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Checks out a connection from the pool.
  
  ## Parameters
  - `pool` - Pool PID or name
  - `target` - Target specification for connection affinity
  - `timeout` - Checkout timeout in ms (default: 5000)
  
  ## Examples
  
      {:ok, conn} = SNMPMgr.Pool.checkout(pool, "192.168.1.1:161")
      # Use connection...
      SNMPMgr.Pool.checkin(pool, conn)
  """
  def checkout(pool, target \\ nil, timeout \\ 5000) do
    GenServer.call(pool, {:checkout, target}, timeout)
  end
  
  @doc """
  Checks in a connection back to the pool.
  
  ## Parameters
  - `pool` - Pool PID or name
  - `connection` - Connection to return
  
  ## Examples
  
      {:ok, conn} = SNMPMgr.Pool.checkout(pool)
      result = send_request(conn, request)
      SNMPMgr.Pool.checkin(pool, conn)
  """
  def checkin(pool, connection) do
    GenServer.cast(pool, {:checkin, connection})
  end
  
  @doc """
  Returns a connection with error status for cleanup.
  
  ## Parameters
  - `pool` - Pool PID or name
  - `connection` - Connection that encountered an error
  - `error` - Error information
  """
  def return_error(pool, connection, error) do
    GenServer.cast(pool, {:return_error, connection, error})
  end
  
  @doc """
  Gets pool statistics and health information.
  """
  def get_stats(pool) do
    GenServer.call(pool, :get_stats)
  end
  
  @doc """
  Gets current pool status.
  """
  def get_status(pool) do
    GenServer.call(pool, :get_status)
  end
  
  @doc """
  Gracefully shuts down the pool and all connections.
  """
  def stop(pool) do
    GenServer.call(pool, :stop)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    max_idle_time = Keyword.get(opts, :max_idle_time, @default_max_idle_time)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)
    socket_opts = Keyword.get(opts, :socket_opts, @default_socket_opts)
    
    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__),
      pool_size: pool_size,
      max_idle_time: max_idle_time,
      cleanup_interval: cleanup_interval,
      socket_opts: socket_opts,
      connections: %{},
      available: :queue.new(),
      metrics: initialize_metrics(),
      cleanup_timer: nil
    }
    
    # Start cleanup timer
    cleanup_timer = if cleanup_interval > 0 do
      Process.send_after(self(), :cleanup, cleanup_interval)
    end
    
    state = %{state | cleanup_timer: cleanup_timer}
    
    Logger.info("SNMPMgr Pool started with pool_size=#{pool_size}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:checkout, target}, from, state) do
    case get_available_connection(state, target) do
      {:ok, conn_id, connection} ->
        # Mark connection as in use
        updated_connection = %{connection | 
          status: :in_use,
          checked_out_at: System.monotonic_time(:millisecond),
          checked_out_by: from,
          last_used: System.monotonic_time(:millisecond)
        }
        
        new_connections = Map.put(state.connections, conn_id, updated_connection)
        new_available = remove_from_available(state.available, conn_id)
        
        # Update metrics
        metrics = update_metrics(state.metrics, :checkouts, 1)
        
        new_state = %{state | 
          connections: new_connections,
          available: new_available,
          metrics: metrics
        }
        
        {:reply, {:ok, %{id: conn_id, socket: connection.socket, target: target}}, new_state}
      
      {:error, :pool_exhausted} ->
        # Try to create new connection if under limit
        if map_size(state.connections) < state.pool_size do
          case create_connection(state, target) do
            {:ok, conn_id, connection} ->
              # Mark as in use immediately
              updated_connection = %{connection | 
                status: :in_use,
                checked_out_at: System.monotonic_time(:millisecond),
                checked_out_by: from,
                last_used: System.monotonic_time(:millisecond)
              }
              
              new_connections = Map.put(state.connections, conn_id, updated_connection)
              
              # Update metrics
              metrics = update_metrics(state.metrics, :checkouts, 1)
              metrics = update_metrics(metrics, :connections_created, 1)
              
              new_state = %{state | 
                connections: new_connections,
                metrics: metrics
              }
              
              {:reply, {:ok, %{id: conn_id, socket: connection.socket, target: target}}, new_state}
            
            {:error, reason} ->
              metrics = update_metrics(state.metrics, :checkout_failures, 1)
              new_state = %{state | metrics: metrics}
              {:reply, {:error, reason}, new_state}
          end
        else
          metrics = update_metrics(state.metrics, :checkout_failures, 1)
          new_state = %{state | metrics: metrics}
          {:reply, {:error, :pool_exhausted}, new_state}
        end
      
      {:error, reason} ->
        metrics = update_metrics(state.metrics, :checkout_failures, 1)
        new_state = %{state | metrics: metrics}
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      pool_size: state.pool_size,
      total_connections: map_size(state.connections),
      available_connections: :queue.len(state.available),
      in_use_connections: count_in_use_connections(state.connections),
      metrics: state.metrics
    }
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = 
      state.connections
      |> Enum.map(fn {id, conn} ->
        %{
          id: id,
          status: conn.status,
          created_at: conn.created_at,
          last_used: conn.last_used,
          error_count: conn.error_count,
          total_uses: conn.total_uses
        }
      end)
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call(:stop, _from, state) do
    # Close all connections
    Enum.each(state.connections, fn {_id, conn} ->
      if conn.socket do
        :gen_udp.close(conn.socket)
      end
    end)
    
    # Cancel cleanup timer
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end
    
    {:stop, :normal, :ok, state}
  end
  
  @impl true
  def handle_cast({:checkin, %{id: conn_id}}, state) do
    case Map.get(state.connections, conn_id) do
      nil ->
        Logger.warning("Attempted to checkin unknown connection: #{inspect(conn_id)}")
        {:noreply, state}
      
      connection ->
        # Mark connection as available
        updated_connection = %{connection | 
          status: :available,
          checked_out_at: nil,
          checked_out_by: nil,
          last_used: System.monotonic_time(:millisecond),
          total_uses: connection.total_uses + 1
        }
        
        new_connections = Map.put(state.connections, conn_id, updated_connection)
        new_available = :queue.in(conn_id, state.available)
        
        # Update metrics
        metrics = update_metrics(state.metrics, :checkins, 1)
        
        new_state = %{state | 
          connections: new_connections,
          available: new_available,
          metrics: metrics
        }
        
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_cast({:return_error, %{id: conn_id}, error}, state) do
    case Map.get(state.connections, conn_id) do
      nil ->
        Logger.warning("Attempted to return error for unknown connection: #{inspect(conn_id)}")
        {:noreply, state}
      
      connection ->
        Logger.warning("Connection #{inspect(conn_id)} returned with error: #{inspect(error)}")
        
        # Increment error count and potentially remove connection
        updated_connection = %{connection | 
          error_count: connection.error_count + 1,
          last_error: error,
          last_used: System.monotonic_time(:millisecond)
        }
        
        # If too many errors, remove connection
        if updated_connection.error_count >= 5 do
          if connection.socket do
            :gen_udp.close(connection.socket)
          end
          
          new_connections = Map.delete(state.connections, conn_id)
          new_available = remove_from_available(state.available, conn_id)
          
          # Update metrics
          metrics = update_metrics(state.metrics, :connections_removed, 1)
          metrics = update_metrics(metrics, :connection_errors, 1)
          
          new_state = %{state | 
            connections: new_connections,
            available: new_available,
            metrics: metrics
          }
          
          Logger.info("Removed connection #{inspect(conn_id)} due to excessive errors")
          {:noreply, new_state}
        else
          # Keep connection but mark as available with error
          updated_connection = %{updated_connection | 
            status: :available,
            checked_out_at: nil,
            checked_out_by: nil
          }
          
          new_connections = Map.put(state.connections, conn_id, updated_connection)
          new_available = :queue.in(conn_id, state.available)
          
          # Update metrics
          metrics = update_metrics(state.metrics, :connection_errors, 1)
          
          new_state = %{state | 
            connections: new_connections,
            available: new_available,
            metrics: metrics
          }
          
          {:noreply, new_state}
        end
    end
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    new_state = perform_cleanup(state)
    
    # Schedule next cleanup
    cleanup_timer = if state.cleanup_interval > 0 do
      Process.send_after(self(), :cleanup, state.cleanup_interval)
    end
    
    new_state = %{new_state | cleanup_timer: cleanup_timer}
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:udp, socket, _ip, _port, _data}, state) do
    # Forward UDP messages to the appropriate handler
    # This is handled by the Engine that owns the request
    Logger.debug("Received UDP data on pooled socket #{inspect(socket)}")
    {:noreply, state}
  end
  
  # Private functions
  
  defp initialize_metrics() do
    %{
      checkouts: 0,
      checkins: 0,
      checkout_failures: 0,
      connections_created: 0,
      connections_removed: 0,
      connection_errors: 0,
      cleanup_runs: 0,
      avg_checkout_time: 0,
      last_reset: System.monotonic_time(:second)
    }
  end
  
  defp get_available_connection(state, _target) do
    # Simple FIFO selection from available queue
    case :queue.out(state.available) do
      {{:value, conn_id}, _new_queue} ->
        case Map.get(state.connections, conn_id) do
          nil -> {:error, :connection_not_found}
          connection -> {:ok, conn_id, connection}
        end
      {:empty, _queue} ->
        {:error, :pool_exhausted}
    end
  end
  
  defp create_connection(state, _target) do
    conn_id = make_ref()
    
    case :gen_udp.open(0, state.socket_opts) do
      {:ok, socket} ->
        connection = %{
          id: conn_id,
          socket: socket,
          status: :available,
          created_at: System.monotonic_time(:millisecond),
          last_used: System.monotonic_time(:millisecond),
          checked_out_at: nil,
          checked_out_by: nil,
          error_count: 0,
          last_error: nil,
          total_uses: 0
        }
        
        Logger.debug("Created new connection #{inspect(conn_id)}")
        {:ok, conn_id, connection}
      
      {:error, reason} ->
        Logger.error("Failed to create UDP socket: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp remove_from_available(queue, conn_id) do
    # Remove specific connection ID from queue
    queue
    |> :queue.to_list()
    |> List.delete(conn_id)
    |> :queue.from_list()
  end
  
  defp count_in_use_connections(connections) do
    Enum.count(connections, fn {_id, conn} -> conn.status == :in_use end)
  end
  
  defp perform_cleanup(state) do
    current_time = System.monotonic_time(:millisecond)
    
    # Find idle connections to clean up
    {to_remove, to_keep} = 
      Enum.split_with(state.connections, fn {_id, conn} ->
        conn.status == :available and 
        (current_time - conn.last_used) > state.max_idle_time
      end)
    
    # Close sockets for removed connections
    Enum.each(to_remove, fn {_id, conn} ->
      if conn.socket do
        :gen_udp.close(conn.socket)
      end
    end)
    
    # Update state
    removed_ids = Enum.map(to_remove, fn {id, _conn} -> id end)
    new_connections = Enum.into(to_keep, %{})
    
    # Clean available queue
    new_available = 
      state.available
      |> :queue.to_list()
      |> Enum.reject(fn id -> id in removed_ids end)
      |> :queue.from_list()
    
    # Update metrics
    metrics = update_metrics(state.metrics, :cleanup_runs, 1)
    metrics = update_metrics(metrics, :connections_removed, length(to_remove))
    
    if length(to_remove) > 0 do
      Logger.info("Cleaned up #{length(to_remove)} idle connections")
    end
    
    %{state | 
      connections: new_connections,
      available: new_available,
      metrics: metrics
    }
  end
  
  defp update_metrics(metrics, key, value) do
    Map.update(metrics, key, value, fn current -> current + value end)
  end
end