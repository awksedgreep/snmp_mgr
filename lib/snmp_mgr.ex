defmodule SNMPMgr do
  @moduledoc """
  Lightweight SNMP client library for Elixir.
  
  This library provides a simple, stateless interface for SNMP operations
  without requiring heavyweight management processes or configurations.
  """

  @doc """
  Performs an SNMP GET request.

  ## Parameters
  - `target` - The target device (e.g., "192.168.1.1:161" or "device.local")
  - `oid` - The OID to retrieve (string format)
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: Phase 1 requires Erlang SNMP modules
      iex> SNMPMgr.get("192.168.1.1:161", "1.3.6.1.2.1.1.1.0", community: "public")
      {:error, :snmp_modules_not_available}

      iex> SNMPMgr.get("device.local", "1.3.6.1.2.1.1.1.0")
      {:error, :snmp_modules_not_available}
  """
  def get(target, oid, opts \\ []) do
    merged_opts = SNMPMgr.Config.merge_opts(opts)
    SNMPMgr.Core.send_get_request(target, oid, merged_opts)
  end

  @doc """
  Performs an SNMP GETNEXT request.

  ## Parameters
  - `target` - The target device
  - `oid` - The starting OID
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: Phase 1 requires Erlang SNMP modules
      iex> SNMPMgr.get_next("192.168.1.1", "1.3.6.1.2.1.1")
      {:error, :snmp_modules_not_available}
  """
  def get_next(target, oid, opts \\ []) do
    merged_opts = SNMPMgr.Config.merge_opts(opts)
    SNMPMgr.Core.send_get_next_request(target, oid, merged_opts)
  end

  @doc """
  Performs an SNMP SET request.

  ## Parameters
  - `target` - The target device
  - `oid` - The OID to set
  - `value` - The value to set
  - `opts` - Options including :community, :timeout, :retries

  ## Examples

      # Note: Phase 1 requires Erlang SNMP modules
      iex> SNMPMgr.set("device.local", "1.3.6.1.2.1.1.6.0", "New Location")
      {:error, :snmp_modules_not_available}
  """
  def set(target, oid, value, opts \\ []) do
    merged_opts = SNMPMgr.Config.merge_opts(opts)
    SNMPMgr.Core.send_set_request(target, oid, value, merged_opts)
  end

  @doc """
  Performs an asynchronous SNMP GET request.

  Returns immediately with a reference. The caller will receive a message
  with the result.

  ## Examples

      ref = SNMPMgr.get_async("192.168.1.1", "1.3.6.1.2.1.1.1.0")
      receive do
        {^ref, result} -> result
      after
        5000 -> {:error, :timeout}
      end
  """
  def get_async(target, oid, opts \\ []) do
    merged_opts = SNMPMgr.Config.merge_opts(opts)
    SNMPMgr.Core.send_get_request_async(target, oid, merged_opts)
  end

  @doc """
  Performs an SNMP GETBULK request (SNMPv2c only).

  GETBULK is more efficient than multiple GETNEXT requests for retrieving
  large amounts of data. It can retrieve multiple variables in a single request.

  ## Parameters
  - `target` - The target device
  - `oid` - The starting OID
  - `opts` - Options including :non_repeaters, :max_repetitions, :community, :timeout

  ## Examples

      # Note: Phase 1-2 requires Erlang SNMP modules
      iex> SNMPMgr.get_bulk("192.168.1.1", "1.3.6.1.2.1.2.2", max_repetitions: 10)
      {:error, :snmp_modules_not_available}
  """
  def get_bulk(target, oid, opts \\ []) do
    # Force version to v2c for GETBULK
    merged_opts = 
      opts
      |> Keyword.put(:version, :v2c)
      |> (&SNMPMgr.Config.merge_opts/1).()
    
    SNMPMgr.Core.send_get_bulk_request(target, oid, merged_opts)
  end

  @doc """
  Performs an asynchronous SNMP GETBULK request.

  Returns immediately with a reference. The caller will receive a message
  with the result.
  """
  def get_bulk_async(target, oid, opts \\ []) do
    # Force version to v2c for GETBULK
    merged_opts = 
      opts
      |> Keyword.put(:version, :v2c)
      |> (&SNMPMgr.Config.merge_opts/1).()
    
    SNMPMgr.Core.send_get_bulk_request_async(target, oid, merged_opts)
  end

  @doc """
  Performs an SNMP walk operation using iterative GETNEXT requests.

  Walks the SNMP tree starting from the given OID and returns all OID/value
  pairs found under that subtree.

  ## Parameters
  - `target` - The target device
  - `root_oid` - The starting OID for the walk
  - `opts` - Options including :community, :timeout, :max_repetitions

  ## Examples

      # Note: Phase 1 requires Erlang SNMP modules
      iex> SNMPMgr.walk("192.168.1.1", "1.3.6.1.2.1.1")
      {:error, :snmp_modules_not_available}
  """
  def walk(target, root_oid, opts \\ []) do
    SNMPMgr.Walk.walk(target, root_oid, opts)
  end

  @doc """
  Walks an SNMP table and returns all entries.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to walk
  - `opts` - Options including :community, :timeout

  ## Examples

      # Note: Phase 1 requires Erlang SNMP modules
      iex> SNMPMgr.walk_table("192.168.1.1", "1.3.6.1.2.1.2.2")
      {:error, :snmp_modules_not_available}
  """
  def walk_table(target, table_oid, opts \\ []) do
    SNMPMgr.Walk.walk_table(target, table_oid, opts)
  end

  @doc """
  Gets all entries from an SNMP table and formats them as a structured table.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID
  - `opts` - Options including :community, :timeout

  ## Examples

      # Note: Phase 1 requires Erlang SNMP modules
      iex> SNMPMgr.get_table("192.168.1.1", "ifTable")
      {:error, :snmp_modules_not_available}
  """
  def get_table(target, table_oid, opts \\ []) do
    case resolve_oid_if_needed(table_oid) do
      {:ok, resolved_oid} ->
        case walk_table(target, resolved_oid, opts) do
          {:ok, entries} -> SNMPMgr.Table.to_table(entries, resolved_oid)
          error -> error
        end
      error -> error
    end
  end

  @doc """
  Gets a specific column from an SNMP table.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID
  - `column` - The column number or name
  - `opts` - Options including :community, :timeout
  """
  def get_column(target, table_oid, column, opts \\ []) do
    case resolve_oid_if_needed(table_oid) do
      {:ok, resolved_table_oid} ->
        column_oid = if is_integer(column) do
          resolved_table_oid ++ [1, column]
        else
          case SNMPMgr.MIB.resolve(column) do
            {:ok, oid} -> oid
            error -> error
          end
        end
        walk(target, column_oid, opts)
      error -> error
    end
  end

  @doc """
  Performs concurrent GET operations against multiple targets.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} tuples
  - `opts` - Options applied to all requests

  ## Examples

      # Note: Phase 1-3 requires Erlang SNMP modules for actual operations
      iex> SNMPMgr.get_multi([{"device1", [1,3,6,1,2,1,1,1,0]}, {"device2", [1,3,6,1,2,1,1,3,0]}])
      [{:error, :snmp_modules_not_available}, {:error, :snmp_modules_not_available}]
  """
  def get_multi(targets_and_oids, opts \\ []) do
    merged_opts = SNMPMgr.Config.merge_opts(opts)
    SNMPMgr.Multi.get_multi(targets_and_oids, merged_opts)
  end

  @doc """
  Performs concurrent GETBULK operations against multiple targets.

  ## Parameters
  - `targets_and_oids` - List of {target, oid} tuples
  - `opts` - Options applied to all requests including :max_repetitions
  """
  def get_bulk_multi(targets_and_oids, opts \\ []) do
    merged_opts = 
      opts
      |> Keyword.put(:version, :v2c)
      |> (&SNMPMgr.Config.merge_opts/1).()
    
    SNMPMgr.Multi.get_bulk_multi(targets_and_oids, merged_opts)
  end

  @doc """
  Performs concurrent walk operations against multiple targets.

  ## Parameters
  - `targets_and_oids` - List of {target, root_oid} tuples
  - `opts` - Options applied to all requests
  """
  def walk_multi(targets_and_oids, opts \\ []) do
    merged_opts = SNMPMgr.Config.merge_opts(opts)
    SNMPMgr.Multi.walk_multi(targets_and_oids, merged_opts)
  end

  @doc """
  Performs an adaptive bulk walk that automatically optimizes parameters.

  Uses intelligent parameter tuning based on device response characteristics
  for optimal performance.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :adaptive_tuning, :max_entries

  ## Examples

      iex> SNMPMgr.adaptive_walk("switch.local", "ifTable")
      {:error, :snmp_modules_not_available}
  """
  def adaptive_walk(target, root_oid, opts \\ []) do
    SNMPMgr.AdaptiveWalk.bulk_walk(target, root_oid, opts)
  end

  @doc """
  Creates a stream for memory-efficient processing of large SNMP data.

  ## Parameters
  - `target` - The target device
  - `root_oid` - Starting OID for the walk
  - `opts` - Options including :chunk_size, :adaptive

  ## Examples

      # Note: Requires Erlang SNMP modules for actual operation
      stream = SNMPMgr.walk_stream("device.local", "ifTable")
      # Process stream lazily...
  """
  def walk_stream(target, root_oid, opts \\ []) do
    SNMPMgr.Stream.walk_stream(target, root_oid, opts)
  end

  @doc """
  Creates a stream for processing large SNMP tables.

  ## Parameters
  - `target` - The target device
  - `table_oid` - The table OID to stream
  - `opts` - Options including :chunk_size, :columns

  ## Examples

      # Note: Requires Erlang SNMP modules for actual operation
      stream = SNMPMgr.table_stream("switch.local", "ifTable")
      # Process table stream...
  """
  def table_stream(target, table_oid, opts \\ []) do
    SNMPMgr.Stream.table_stream(target, table_oid, opts)
  end

  @doc """
  Analyzes table structure and returns detailed metadata.

  ## Parameters
  - `table_data` - Table data as returned by get_table/3
  - `opts` - Analysis options

  ## Examples

      {:ok, table} = SNMPMgr.get_table("device.local", "ifTable")
      {:ok, analysis} = SNMPMgr.analyze_table(table)
      IO.inspect(analysis.completeness)  # Shows data completeness ratio
  """
  def analyze_table(table_data, opts \\ []) do
    SNMPMgr.Table.analyze(table_data, opts)
  end

  @doc """
  Benchmarks a device to determine optimal bulk parameters.

  ## Parameters
  - `target` - The target device to benchmark
  - `test_oid` - OID to use for testing
  - `opts` - Benchmark options

  ## Examples

      {:ok, results} = SNMPMgr.benchmark_device("switch.local", "ifTable")
      optimal_size = results.optimal_bulk_size
  """
  def benchmark_device(target, test_oid, opts \\ []) do
    SNMPMgr.AdaptiveWalk.benchmark_device(target, test_oid, opts)
  end

  @doc """
  Starts the streaming PDU engine infrastructure.

  Initializes all Phase 5 components including engines, routers, connection pools,
  circuit breakers, and metrics collection for high-performance SNMP operations.

  ## Options
  - `:engine` - Engine configuration options
  - `:router` - Router configuration options  
  - `:pool` - Connection pool options
  - `:circuit_breaker` - Circuit breaker options
  - `:metrics` - Metrics collection options

  ## Examples

      {:ok, _pid} = SNMPMgr.start_engine(
        engine: [pool_size: 20, max_rps: 500],
        router: [strategy: :least_connections],
        pool: [pool_size: 50],
        metrics: [window_size: 120]
      )
  """
  def start_engine(opts \\ []) do
    SNMPMgr.Supervisor.start_link(opts)
  end

  @doc """
  Submits a request through the streaming engine.

  Routes the request through the high-performance engine infrastructure
  with automatic load balancing, circuit breaking, and metrics collection.

  ## Parameters
  - `request` - Request specification map
  - `opts` - Request options

  ## Examples

      request = %{
        type: :get,
        target: "192.168.1.1",
        oid: "sysDescr.0",
        community: "public"
      }
      
      {:ok, result} = SNMPMgr.engine_request(request)
  """
  def engine_request(request, opts \\ []) do
    router = Keyword.get(opts, :router, SNMPMgr.Router)
    SNMPMgr.Router.route_request(router, request, opts)
  end

  @doc """
  Submits multiple requests as a batch through the streaming engine.

  ## Parameters
  - `requests` - List of request specification maps
  - `opts` - Batch options

  ## Examples

      requests = [
        %{type: :get, target: "device1", oid: "sysDescr.0"},
        %{type: :get, target: "device2", oid: "sysUpTime.0"}
      ]
      
      {:ok, results} = SNMPMgr.engine_batch(requests)
  """
  def engine_batch(requests, opts \\ []) do
    router = Keyword.get(opts, :router, SNMPMgr.Router)
    SNMPMgr.Router.route_batch(router, requests, opts)
  end

  @doc """
  Gets comprehensive system metrics and statistics.

  ## Parameters
  - `opts` - Options including which components to include

  ## Examples

      {:ok, stats} = SNMPMgr.get_engine_stats()
      IO.inspect(stats.router.requests_routed)
      IO.inspect(stats.metrics.current_metrics)
  """
  def get_engine_stats(opts \\ []) do
    components = Keyword.get(opts, :components, [:router, :pool, :circuit_breaker, :metrics])
    
    stats = %{}
    
    stats = if :router in components do
      Map.put(stats, :router, SNMPMgr.Router.get_stats(SNMPMgr.Router))
    else
      stats
    end
    
    stats = if :pool in components do
      Map.put(stats, :pool, SNMPMgr.Pool.get_stats(SNMPMgr.Pool))
    else
      stats
    end
    
    stats = if :circuit_breaker in components do
      Map.put(stats, :circuit_breaker, SNMPMgr.CircuitBreaker.get_stats(SNMPMgr.CircuitBreaker))
    else
      stats
    end
    
    stats = if :metrics in components do
      Map.put(stats, :metrics, SNMPMgr.Metrics.get_summary(SNMPMgr.Metrics))
    else
      stats
    end
    
    {:ok, stats}
  end

  @doc """
  Executes a function with circuit breaker protection.

  ## Parameters
  - `target` - Target device identifier
  - `fun` - Function to execute with protection
  - `opts` - Circuit breaker options

  ## Examples

      result = SNMPMgr.with_circuit_breaker("device1", fn ->
        SNMPMgr.get("device1", "sysDescr.0")
      end)
  """
  def with_circuit_breaker(target, fun, opts \\ []) do
    circuit_breaker = Keyword.get(opts, :circuit_breaker, SNMPMgr.CircuitBreaker)
    timeout = Keyword.get(opts, :timeout, 5000)
    SNMPMgr.CircuitBreaker.call(circuit_breaker, target, fun, timeout)
  end

  @doc """
  Records a custom metric.

  ## Parameters
  - `metric_type` - Type of metric (:counter, :gauge, :histogram)
  - `metric_name` - Name of the metric
  - `value` - Value to record
  - `tags` - Optional tags

  ## Examples

      SNMPMgr.record_metric(:counter, :custom_requests, 1, %{device: "switch1"})
      SNMPMgr.record_metric(:histogram, :custom_latency, 150, %{operation: "bulk"})
  """
  def record_metric(metric_type, metric_name, value, tags \\ %{}) do
    metrics = SNMPMgr.Metrics
    
    case metric_type do
      :counter -> SNMPMgr.Metrics.counter(metrics, metric_name, value, tags)
      :gauge -> SNMPMgr.Metrics.gauge(metrics, metric_name, value, tags)
      :histogram -> SNMPMgr.Metrics.histogram(metrics, metric_name, value, tags)
    end
  end

  # Private helper function
  defp resolve_oid_if_needed(oid) when is_binary(oid) do
    case SNMPMgr.OID.string_to_list(oid) do
      {:ok, oid_list} -> {:ok, oid_list}
      {:error, _} ->
        # Try resolving as symbolic name
        SNMPMgr.MIB.resolve(oid)
    end
  end
  defp resolve_oid_if_needed(oid) when is_list(oid), do: {:ok, oid}
  defp resolve_oid_if_needed(_), do: {:error, :invalid_oid_format}
end
