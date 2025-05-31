defmodule SNMPMgr.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern implementation for SNMP device failure protection.
  
  This module implements the circuit breaker pattern to prevent cascading failures
  when SNMP devices become unresponsive. It provides automatic failure detection,
  recovery attempts, and configurable thresholds for different failure scenarios.
  """
  
  use GenServer
  require Logger
  
  @default_failure_threshold 5
  @default_recovery_timeout 30_000  # 30 seconds
  @default_timeout_threshold 10_000  # 10 seconds
  @default_half_open_max_calls 3
  
  defstruct [
    :name,
    :failure_threshold,
    :recovery_timeout,
    :timeout_threshold,
    :half_open_max_calls,
    :breakers,
    :metrics
  ]
  
  @doc """
  Starts the circuit breaker manager.
  
  ## Options
  - `:failure_threshold` - Number of failures before opening circuit (default: 5)
  - `:recovery_timeout` - Time to wait before attempting recovery in ms (default: 30000)
  - `:timeout_threshold` - Request timeout threshold in ms (default: 10000)
  - `:half_open_max_calls` - Max calls in half-open state (default: 3)
  
  ## Examples
  
      {:ok, cb} = SNMPMgr.CircuitBreaker.start_link(
        failure_threshold: 10,
        recovery_timeout: 60_000
      )
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Executes a function with circuit breaker protection.
  
  ## Parameters
  - `cb` - Circuit breaker PID or name
  - `target` - Target identifier (device address/name)
  - `fun` - Function to execute
  - `timeout` - Operation timeout in ms
  
  ## Examples
  
      result = SNMPMgr.CircuitBreaker.call(cb, "192.168.1.1", fn ->
        SNMPMgr.get("192.168.1.1", "sysDescr.0")
      end, 5000)
  """
  def call(cb, target, fun, timeout \\ 5000) do
    GenServer.call(cb, {:call, target, fun, timeout})
  end
  
  @doc """
  Records a successful operation for a target.
  """
  def record_success(cb, target) do
    GenServer.cast(cb, {:record_success, target})
  end
  
  @doc """
  Records a failure for a target.
  """
  def record_failure(cb, target, reason) do
    GenServer.cast(cb, {:record_failure, target, reason})
  end
  
  @doc """
  Gets the current state of a circuit breaker for a target.
  """
  def get_state(cb, target) do
    GenServer.call(cb, {:get_state, target})
  end
  
  @doc """
  Gets statistics for all circuit breakers.
  """
  def get_stats(cb) do
    GenServer.call(cb, :get_stats)
  end
  
  @doc """
  Manually opens a circuit breaker for a target.
  """
  def open_circuit(cb, target) do
    GenServer.cast(cb, {:open_circuit, target})
  end
  
  @doc """
  Manually closes a circuit breaker for a target.
  """
  def close_circuit(cb, target) do
    GenServer.cast(cb, {:close_circuit, target})
  end
  
  @doc """
  Resets all circuit breakers.
  """
  def reset_all(cb) do
    GenServer.cast(cb, :reset_all)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__),
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      recovery_timeout: Keyword.get(opts, :recovery_timeout, @default_recovery_timeout),
      timeout_threshold: Keyword.get(opts, :timeout_threshold, @default_timeout_threshold),
      half_open_max_calls: Keyword.get(opts, :half_open_max_calls, @default_half_open_max_calls),
      breakers: %{},
      metrics: initialize_metrics()
    }
    
    Logger.info("SNMPMgr CircuitBreaker started")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:call, target, fun, timeout}, _from, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    
    case breaker.state do
      :closed ->
        execute_with_breaker(state, target, breaker, fun, timeout)
      
      :open ->
        if should_attempt_reset?(breaker, state.recovery_timeout) do
          # Transition to half-open
          new_breaker = %{breaker | 
            state: :half_open,
            half_open_calls: 0,
            last_failure_time: System.monotonic_time(:millisecond)
          }
          
          new_breakers = Map.put(state.breakers, target, new_breaker)
          new_state = %{state | breakers: new_breakers}
          
          execute_with_breaker(new_state, target, new_breaker, fun, timeout)
        else
          # Circuit is open, fail fast
          metrics = update_metrics(state.metrics, :fast_failures, 1)
          new_state = %{state | metrics: metrics}
          {:reply, {:error, :circuit_breaker_open}, new_state}
        end
      
      :half_open ->
        if breaker.half_open_calls < state.half_open_max_calls do
          execute_with_breaker(state, target, breaker, fun, timeout)
        else
          # Too many calls in half-open, stay open
          new_breaker = %{breaker | state: :open}
          new_breakers = Map.put(state.breakers, target, new_breaker)
          new_state = %{state | breakers: new_breakers}
          
          metrics = update_metrics(new_state.metrics, :fast_failures, 1)
          new_state = %{new_state | metrics: metrics}
          
          {:reply, {:error, :circuit_breaker_open}, new_state}
        end
    end
  end
  
  @impl true
  def handle_call({:get_state, target}, _from, state) do
    breaker = Map.get(state.breakers, target)
    
    if breaker do
      breaker_info = %{
        state: breaker.state,
        failure_count: breaker.failure_count,
        success_count: breaker.success_count,
        last_failure_time: breaker.last_failure_time,
        last_success_time: breaker.last_success_time,
        half_open_calls: breaker.half_open_calls
      }
      {:reply, {:ok, breaker_info}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_breakers: map_size(state.breakers),
      breaker_states: get_breaker_states(state.breakers),
      metrics: state.metrics
    }
    {:reply, stats, state}
  end
  
  @impl true
  def handle_cast({:record_success, target}, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    
    new_breaker = case breaker.state do
      :half_open ->
        # Successful call in half-open, increment success count
        updated = %{breaker | 
          success_count: breaker.success_count + 1,
          last_success_time: System.monotonic_time(:millisecond),
          half_open_calls: breaker.half_open_calls + 1
        }
        
        # If enough successes, close the circuit
        if updated.success_count >= 3 do
          %{updated | 
            state: :closed,
            failure_count: 0,
            half_open_calls: 0
          }
        else
          updated
        end
      
      _ ->
        # Normal success
        %{breaker | 
          success_count: breaker.success_count + 1,
          last_success_time: System.monotonic_time(:millisecond)
        }
    end
    
    new_breakers = Map.put(state.breakers, target, new_breaker)
    metrics = update_metrics(state.metrics, :successes, 1)
    
    new_state = %{state | breakers: new_breakers, metrics: metrics}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_failure, target, reason}, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    
    new_breaker = %{breaker | 
      failure_count: breaker.failure_count + 1,
      last_failure_time: System.monotonic_time(:millisecond),
      last_failure_reason: reason
    }
    
    # Check if we should open the circuit
    new_breaker = if new_breaker.failure_count >= state.failure_threshold do
      Logger.warning("Opening circuit breaker for #{target} due to #{new_breaker.failure_count} failures")
      %{new_breaker | state: :open}
    else
      new_breaker
    end
    
    new_breakers = Map.put(state.breakers, target, new_breaker)
    metrics = update_metrics(state.metrics, :failures, 1)
    
    new_state = %{state | breakers: new_breakers, metrics: metrics}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:open_circuit, target}, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    new_breaker = %{breaker | state: :open}
    new_breakers = Map.put(state.breakers, target, new_breaker)
    
    Logger.info("Manually opened circuit breaker for #{target}")
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:close_circuit, target}, state) do
    breaker = get_or_create_breaker(state.breakers, target, state)
    new_breaker = %{breaker | 
      state: :closed,
      failure_count: 0,
      half_open_calls: 0
    }
    new_breakers = Map.put(state.breakers, target, new_breaker)
    
    Logger.info("Manually closed circuit breaker for #{target}")
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast(:reset_all, state) do
    Logger.info("Resetting all circuit breakers")
    
    new_breakers = 
      Enum.map(state.breakers, fn {target, _breaker} ->
        {target, create_breaker()}
      end)
      |> Enum.into(%{})
    
    new_state = %{state | breakers: new_breakers}
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp initialize_metrics() do
    %{
      successes: 0,
      failures: 0,
      fast_failures: 0,
      timeouts: 0,
      circuit_opens: 0,
      circuit_closes: 0,
      last_reset: System.monotonic_time(:second)
    }
  end
  
  defp get_or_create_breaker(breakers, target, _state) do
    Map.get(breakers, target, create_breaker())
  end
  
  defp create_breaker() do
    %{
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      last_success_time: nil,
      last_failure_reason: nil,
      half_open_calls: 0,
      created_at: System.monotonic_time(:millisecond)
    }
  end
  
  defp execute_with_breaker(state, target, breaker, fun, timeout) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Execute with timeout
      task = Task.async(fun)
      
      case Task.yield(task, timeout) do
        {:ok, result} ->
          end_time = System.monotonic_time(:millisecond)
          _execution_time = end_time - start_time
          
          # Record success
          new_breaker = case breaker.state do
            :half_open ->
              updated = %{breaker | 
                success_count: breaker.success_count + 1,
                last_success_time: end_time,
                half_open_calls: breaker.half_open_calls + 1
              }
              
              # If enough successes in half-open, close circuit
              if updated.success_count >= 3 do
                Logger.info("Closing circuit breaker for #{target} after successful recovery")
                %{updated | 
                  state: :closed,
                  failure_count: 0,
                  half_open_calls: 0
                }
              else
                updated
              end
            
            _ ->
              %{breaker | 
                success_count: breaker.success_count + 1,
                last_success_time: end_time
              }
          end
          
          new_breakers = Map.put(state.breakers, target, new_breaker)
          metrics = update_metrics(state.metrics, :successes, 1)
          
          new_state = %{state | breakers: new_breakers, metrics: metrics}
          
          {:reply, {:ok, result}, new_state}
        
        nil ->
          # Timeout
          Task.shutdown(task)
          
          new_breaker = %{breaker | 
            failure_count: breaker.failure_count + 1,
            last_failure_time: System.monotonic_time(:millisecond),
            last_failure_reason: :timeout
          }
          
          # Check if we should open circuit
          new_breaker = if new_breaker.failure_count >= state.failure_threshold do
            Logger.warning("Opening circuit breaker for #{target} due to timeout")
            %{new_breaker | state: :open}
          else
            new_breaker
          end
          
          new_breakers = Map.put(state.breakers, target, new_breaker)
          metrics = update_metrics(state.metrics, :timeouts, 1)
          metrics = update_metrics(metrics, :failures, 1)
          
          new_state = %{state | breakers: new_breakers, metrics: metrics}
          
          {:reply, {:error, :timeout}, new_state}
      end
    catch
      :exit, reason ->
        # Function crashed
        new_breaker = %{breaker | 
          failure_count: breaker.failure_count + 1,
          last_failure_time: System.monotonic_time(:millisecond),
          last_failure_reason: reason
        }
        
        # Check if we should open circuit
        new_breaker = if new_breaker.failure_count >= state.failure_threshold do
          Logger.warning("Opening circuit breaker for #{target} due to crash: #{inspect(reason)}")
          %{new_breaker | state: :open}
        else
          new_breaker
        end
        
        new_breakers = Map.put(state.breakers, target, new_breaker)
        metrics = update_metrics(state.metrics, :failures, 1)
        
        new_state = %{state | breakers: new_breakers, metrics: metrics}
        
        {:reply, {:error, reason}, new_state}
      
      kind, reason ->
        # Other error
        new_breaker = %{breaker | 
          failure_count: breaker.failure_count + 1,
          last_failure_time: System.monotonic_time(:millisecond),
          last_failure_reason: {kind, reason}
        }
        
        # Check if we should open circuit
        new_breaker = if new_breaker.failure_count >= state.failure_threshold do
          Logger.warning("Opening circuit breaker for #{target} due to error: #{inspect({kind, reason})}")
          %{new_breaker | state: :open}
        else
          new_breaker
        end
        
        new_breakers = Map.put(state.breakers, target, new_breaker)
        metrics = update_metrics(state.metrics, :failures, 1)
        
        new_state = %{state | breakers: new_breakers, metrics: metrics}
        
        {:reply, {:error, {kind, reason}}, new_state}
    end
  end
  
  defp should_attempt_reset?(breaker, recovery_timeout) do
    if breaker.last_failure_time do
      current_time = System.monotonic_time(:millisecond)
      (current_time - breaker.last_failure_time) >= recovery_timeout
    else
      true
    end
  end
  
  defp get_breaker_states(breakers) do
    breakers
    |> Enum.group_by(fn {_target, breaker} -> breaker.state end)
    |> Enum.map(fn {state, breakers_list} -> {state, length(breakers_list)} end)
    |> Enum.into(%{})
  end
  
  defp update_metrics(metrics, key, value) do
    Map.update(metrics, key, value, fn current -> current + value end)
  end
end