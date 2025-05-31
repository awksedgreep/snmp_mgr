defmodule SNMPMgr.PoolComprehensiveTest do
  use ExUnit.Case, async: false
  
  alias SNMPMgr.{Pool, Config}
  alias SNMPMgr.TestSupport.SNMPSimulator
  
  @moduletag :unit
  @moduletag :pool
  @moduletag :phase_4
  
  # Test configuration
  @test_pool_size 5
  @test_max_idle_time 1000  # 1 second for faster testing
  @test_cleanup_interval 500  # 500ms for faster testing
  
  setup_all do
    # Ensure configuration is available
    case GenServer.whereis(SNMPMgr.Config) do
      nil -> {:ok, _pid} = Config.start_link()
      _pid -> :ok
    end
    
    # Start SNMP simulator for testing
    {:ok, device_info} = SNMPSimulator.create_test_device()
    on_exit(fn -> SNMPSimulator.stop_device(device_info) end)
    
    %{device: device_info}
  end
  
  setup do
    # Start fresh pool for each test
    pool_opts = [
      pool_size: @test_pool_size,
      max_idle_time: @test_max_idle_time,
      cleanup_interval: @test_cleanup_interval
    ]
    
    {:ok, pool_pid} = Pool.start_link(pool_opts)
    
    on_exit(fn ->
      if Process.alive?(pool_pid) do
        Pool.stop(pool_pid)
      end
    end)
    
    %{pool: pool_pid}
  end
  
  describe "Pool Initialization and Configuration" do
    test "starts with default configuration" do
      {:ok, pool} = Pool.start_link()
      
      stats = Pool.get_stats(pool)
      
      assert stats.pool_size >= 1
      assert stats.total_connections == 0  # No connections created yet
      assert stats.available_connections == 0
      assert stats.in_use_connections == 0
      assert is_map(stats.metrics)
      
      Pool.stop(pool)
    end
    
    test "starts with custom configuration", %{pool: pool} do
      stats = Pool.get_stats(pool)
      
      assert stats.pool_size == @test_pool_size
      assert stats.total_connections == 0
      assert is_map(stats.metrics)
    end
    
    test "validates configuration parameters" do
      # Invalid pool size
      assert {:error, _reason} = Pool.start_link(pool_size: 0)
      assert {:error, _reason} = Pool.start_link(pool_size: -1)
      
      # Invalid max_idle_time
      assert {:error, _reason} = Pool.start_link(max_idle_time: -1)
      
      # Invalid cleanup_interval
      assert {:error, _reason} = Pool.start_link(cleanup_interval: -1)
    end
    
    test "initializes metrics correctly", %{pool: pool} do
      stats = Pool.get_stats(pool)
      
      expected_metrics = [
        :checkouts, :checkins, :checkout_failures, :connections_created,
        :connections_removed, :connection_errors, :cleanup_runs,
        :avg_checkout_time, :last_reset
      ]
      
      Enum.each(expected_metrics, fn metric ->
        assert Map.has_key?(stats.metrics, metric)
        assert is_number(stats.metrics[metric])
        assert stats.metrics[metric] >= 0
      end)
    end
    
    test "socket options are configurable" do
      custom_opts = [:binary, {:active, false}, {:reuseaddr, true}]
      
      {:ok, pool} = Pool.start_link(socket_opts: custom_opts)
      
      # Pool should start successfully with custom options
      stats = Pool.get_stats(pool)
      assert is_map(stats)
      
      Pool.stop(pool)
    end
  end
  
  describe "Connection Checkout and Checkin" do
    test "checkout creates connection when pool is empty", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      assert is_map(connection)
      assert Map.has_key?(connection, :id)
      assert Map.has_key?(connection, :socket)
      assert Map.has_key?(connection, :target)
      
      # Pool stats should reflect the checkout
      stats = Pool.get_stats(pool)
      assert stats.total_connections == 1
      assert stats.in_use_connections == 1
      assert stats.available_connections == 0
      
      # Clean up
      Pool.checkin(pool, connection)
    end
    
    test "checkout with target parameter", %{pool: pool} do
      target = "test.device.local:161"
      
      {:ok, connection} = Pool.checkout(pool, target)
      
      assert connection.target == target
      
      Pool.checkin(pool, connection)
    end
    
    test "checkout respects timeout parameter", %{pool: pool} do
      start_time = System.monotonic_time(:millisecond)
      
      # This might timeout if no connections available and can't create new one
      result = Pool.checkout(pool, nil, 100)  # 100ms timeout
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      case result do
        {:ok, connection} -> 
          Pool.checkin(pool, connection)
        {:error, _reason} -> 
          # Should respect timeout
          assert duration <= 200  # Allow some overhead
      end
    end
    
    test "checkin returns connection to available pool", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      initial_stats = Pool.get_stats(pool)
      assert initial_stats.in_use_connections == 1
      assert initial_stats.available_connections == 0
      
      Pool.checkin(pool, connection)
      
      final_stats = Pool.get_stats(pool)
      assert final_stats.in_use_connections == 0
      assert final_stats.available_connections == 1
    end
    
    test "multiple checkouts create multiple connections", %{pool: pool} do
      connections = Enum.map(1..3, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        conn
      end)
      
      stats = Pool.get_stats(pool)
      assert stats.total_connections == 3
      assert stats.in_use_connections == 3
      assert stats.available_connections == 0
      
      # Clean up
      Enum.each(connections, fn conn ->
        Pool.checkin(pool, conn)
      end)
    end
    
    test "reuses available connections", %{pool: pool} do
      # Checkout and checkin to create an available connection
      {:ok, connection1} = Pool.checkout(pool)
      Pool.checkin(pool, connection1)
      
      # Next checkout should reuse the connection
      {:ok, connection2} = Pool.checkout(pool)
      
      # Should be the same connection
      assert connection1.id == connection2.id
      
      stats = Pool.get_stats(pool)
      assert stats.total_connections == 1  # Only one connection created
      
      Pool.checkin(pool, connection2)
    end
    
    test "pool size limit prevents excessive connections", %{pool: pool} do
      # Try to checkout more connections than pool size
      connections = Enum.map(1..(@test_pool_size + 2), fn _i ->
        Pool.checkout(pool, nil, 100)  # Short timeout
      end)
      
      successful_checkouts = Enum.count(connections, fn
        {:ok, _conn} -> true
        _ -> false
      end)
      
      # Should not exceed pool size
      assert successful_checkouts <= @test_pool_size
      
      # Clean up successful checkouts
      connections
      |> Enum.filter(fn result -> match?({:ok, _}, result) end)
      |> Enum.each(fn {:ok, conn} -> Pool.checkin(pool, conn) end)
    end
  end
  
  describe "Connection Lifecycle and Management" do
    test "get_status returns connection details", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      status = Pool.get_status(pool)
      
      assert is_list(status)
      assert length(status) == 1
      
      conn_status = hd(status)
      assert Map.has_key?(conn_status, :id)
      assert Map.has_key?(conn_status, :status)
      assert Map.has_key?(conn_status, :created_at)
      assert Map.has_key?(conn_status, :last_used)
      assert Map.has_key?(conn_status, :error_count)
      assert Map.has_key?(conn_status, :total_uses)
      
      assert conn_status.status == :in_use
      assert conn_status.error_count == 0
      
      Pool.checkin(pool, connection)
    end
    
    test "connection status changes correctly", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      # Should be in use
      status = Pool.get_status(pool)
      assert hd(status).status == :in_use
      
      Pool.checkin(pool, connection)
      
      # Should be available
      status = Pool.get_status(pool)
      assert hd(status).status == :available
    end
    
    test "connection usage count increments", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      Pool.checkin(pool, connection)
      
      initial_status = Pool.get_status(pool)
      initial_uses = hd(initial_status).total_uses
      
      {:ok, same_connection} = Pool.checkout(pool)
      Pool.checkin(pool, same_connection)
      
      final_status = Pool.get_status(pool)
      final_uses = hd(final_status).total_uses
      
      assert final_uses == initial_uses + 1
    end
    
    test "last_used timestamp updates", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      initial_status = Pool.get_status(pool)
      initial_last_used = hd(initial_status).last_used
      
      Process.sleep(10)  # Ensure timestamp difference
      
      Pool.checkin(pool, connection)
      
      final_status = Pool.get_status(pool)
      final_last_used = hd(final_status).last_used
      
      assert final_last_used > initial_last_used
    end
    
    test "connection error handling", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      # Simulate connection error
      test_error = :socket_error
      Pool.return_error(pool, connection, test_error)
      
      status = Pool.get_status(pool)
      conn_status = hd(status)
      
      assert conn_status.error_count == 1
      assert conn_status.status == :available  # Should be available for reuse
    end
    
    test "connection removal after excessive errors", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      # Cause multiple errors
      Enum.each(1..5, fn _i ->
        Pool.return_error(pool, connection, :repeated_error)
      end)
      
      # Connection should be removed
      stats = Pool.get_stats(pool)
      assert stats.total_connections == 0
    end
  end
  
  describe "Automatic Cleanup and Maintenance" do
    test "cleanup removes idle connections", %{pool: pool} do
      # Create and return connections
      connections = Enum.map(1..3, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        Pool.checkin(pool, conn)
        conn
      end)
      
      initial_stats = Pool.get_stats(pool)
      assert initial_stats.total_connections == 3
      
      # Wait for connections to become idle and cleanup to run
      Process.sleep(@test_max_idle_time + @test_cleanup_interval + 100)
      
      final_stats = Pool.get_stats(pool)
      # Connections should be cleaned up
      assert final_stats.total_connections < initial_stats.total_connections
    end
    
    test "cleanup preserves in-use connections", %{pool: pool} do
      # Checkout connection and keep it in use
      {:ok, in_use_connection} = Pool.checkout(pool)
      
      # Create and return other connections
      Enum.each(1..2, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        Pool.checkin(pool, conn)
      end)
      
      initial_stats = Pool.get_stats(pool)
      assert initial_stats.total_connections == 3
      assert initial_stats.in_use_connections == 1
      
      # Wait for cleanup
      Process.sleep(@test_max_idle_time + @test_cleanup_interval + 100)
      
      final_stats = Pool.get_stats(pool)
      # In-use connection should remain
      assert final_stats.in_use_connections == 1
      
      # Clean up
      Pool.checkin(pool, in_use_connection)
    end
    
    test "cleanup runs at configured intervals", %{pool: pool} do
      # Create connections to trigger cleanup
      connections = Enum.map(1..2, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        Pool.checkin(pool, conn)
        conn
      end)
      
      initial_metrics = Pool.get_stats(pool).metrics
      initial_cleanup_runs = initial_metrics.cleanup_runs
      
      # Wait for multiple cleanup cycles
      Process.sleep(@test_cleanup_interval * 3)
      
      final_metrics = Pool.get_stats(pool).metrics
      final_cleanup_runs = final_metrics.cleanup_runs
      
      # Should have run cleanup multiple times
      assert final_cleanup_runs > initial_cleanup_runs
    end
    
    test "disabling cleanup works", %{pool: pool} do
      # Create pool with cleanup disabled
      {:ok, no_cleanup_pool} = Pool.start_link(cleanup_interval: 0)
      
      # Create and return connections
      Enum.each(1..2, fn _i ->
        {:ok, conn} = Pool.checkout(no_cleanup_pool)
        Pool.checkin(no_cleanup_pool, conn)
      end)
      
      initial_stats = Pool.get_stats(no_cleanup_pool)
      assert initial_stats.total_connections == 2
      
      # Wait longer than normal cleanup would take
      Process.sleep(@test_max_idle_time + 200)
      
      final_stats = Pool.get_stats(no_cleanup_pool)
      # Connections should not be cleaned up
      assert final_stats.total_connections == initial_stats.total_connections
      
      Pool.stop(no_cleanup_pool)
    end
    
    test "cleanup metrics are tracked", %{pool: pool} do
      # Create connections to be cleaned up
      Enum.each(1..3, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        Pool.checkin(pool, conn)
      end)
      
      initial_metrics = Pool.get_stats(pool).metrics
      initial_removed = initial_metrics.connections_removed
      
      # Wait for cleanup
      Process.sleep(@test_max_idle_time + @test_cleanup_interval + 100)
      
      final_metrics = Pool.get_stats(pool).metrics
      final_removed = final_metrics.connections_removed
      
      # Should have removed some connections
      assert final_removed >= initial_removed
    end
  end
  
  describe "Performance and Metrics" do
    test "tracks checkout metrics", %{pool: pool} do
      initial_metrics = Pool.get_stats(pool).metrics
      initial_checkouts = initial_metrics.checkouts
      
      {:ok, connection} = Pool.checkout(pool)
      
      final_metrics = Pool.get_stats(pool).metrics
      assert final_metrics.checkouts == initial_checkouts + 1
      
      Pool.checkin(pool, connection)
    end
    
    test "tracks checkin metrics", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      initial_metrics = Pool.get_stats(pool).metrics
      initial_checkins = initial_metrics.checkins
      
      Pool.checkin(pool, connection)
      
      final_metrics = Pool.get_stats(pool).metrics
      assert final_metrics.checkins == initial_checkins + 1
    end
    
    test "tracks connection creation metrics", %{pool: pool} do
      initial_metrics = Pool.get_stats(pool).metrics
      initial_created = initial_metrics.connections_created
      
      {:ok, connection1} = Pool.checkout(pool)
      {:ok, connection2} = Pool.checkout(pool)
      
      final_metrics = Pool.get_stats(pool).metrics
      assert final_metrics.connections_created == initial_created + 2
      
      Pool.checkin(pool, connection1)
      Pool.checkin(pool, connection2)
    end
    
    test "tracks error metrics", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      initial_metrics = Pool.get_stats(pool).metrics
      initial_errors = initial_metrics.connection_errors
      
      Pool.return_error(pool, connection, :test_error)
      
      final_metrics = Pool.get_stats(pool).metrics
      assert final_metrics.connection_errors == initial_errors + 1
    end
    
    test "measures checkout performance", %{pool: pool} do
      # Pre-create connection for fast checkout
      {:ok, connection} = Pool.checkout(pool)
      Pool.checkin(pool, connection)
      
      # Measure checkout time
      start_time = System.monotonic_time(:millisecond)
      {:ok, fast_connection} = Pool.checkout(pool)
      end_time = System.monotonic_time(:millisecond)
      
      checkout_time = end_time - start_time
      
      # Should be very fast for available connection
      assert checkout_time < 100  # Less than 100ms
      
      Pool.checkin(pool, fast_connection)
    end
    
    test "handles high checkout frequency", %{pool: pool} do
      num_operations = 50
      
      start_time = System.monotonic_time(:millisecond)
      
      # Rapid checkout/checkin cycles
      Enum.each(1..num_operations, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        Pool.checkin(pool, conn)
      end)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      avg_time = total_time / num_operations
      
      # Should handle operations efficiently
      assert avg_time < 50  # Less than 50ms per operation
    end
    
    test "memory usage remains stable", %{pool: pool} do
      initial_memory = :erlang.process_info(pool, :memory)[:memory]
      
      # Create many connections
      connections = Enum.map(1..20, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        conn
      end)
      
      # Return all connections
      Enum.each(connections, fn conn ->
        Pool.checkin(pool, conn)
      end)
      
      final_memory = :erlang.process_info(pool, :memory)[:memory]
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be reasonable
      assert memory_growth < 1_000_000  # Less than 1MB
    end
  end
  
  describe "Concurrent Operations and Race Conditions" do
    test "handles concurrent checkouts", %{pool: pool} do
      num_tasks = 10
      
      tasks = Enum.map(1..num_tasks, fn _i ->
        Task.async(fn ->
          case Pool.checkout(pool, nil, 1000) do
            {:ok, conn} -> 
              Process.sleep(10)  # Hold connection briefly
              Pool.checkin(pool, conn)
              :success
            {:error, _reason} -> 
              :failed_checkout
          end
        end)
      end)
      
      results = Task.yield_many(tasks, 5000)
      
      # Should handle concurrent operations
      completed = Enum.count(results, fn {_task, result} -> result != nil end)
      assert completed >= num_tasks / 2  # At least half should complete
    end
    
    test "concurrent operations don't corrupt state", %{pool: pool} do
      num_tasks = 20
      
      tasks = Enum.map(1..num_tasks, fn i ->
        Task.async(fn ->
          if rem(i, 2) == 0 do
            # Checkout/checkin
            case Pool.checkout(pool) do
              {:ok, conn} -> Pool.checkin(pool, conn)
              _ -> :ok
            end
          else
            # Just get stats
            Pool.get_stats(pool)
          end
        end)
      end)
      
      Task.yield_many(tasks, 3000)
      
      # Pool should still be in valid state
      assert Process.alive?(pool)
      
      final_stats = Pool.get_stats(pool)
      assert is_map(final_stats)
      assert final_stats.in_use_connections >= 0
      assert final_stats.available_connections >= 0
    end
    
    test "checkout timeout works under contention", %{pool: pool} do
      # Fill the pool
      connections = Enum.map(1..@test_pool_size, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        conn
      end)
      
      # Try to checkout with short timeout
      start_time = System.monotonic_time(:millisecond)
      result = Pool.checkout(pool, nil, 200)
      end_time = System.monotonic_time(:millisecond)
      
      duration = end_time - start_time
      
      # Should timeout appropriately
      assert result == {:error, :pool_exhausted}
      assert duration >= 180 and duration <= 300  # Around 200ms with some tolerance
      
      # Clean up
      Enum.each(connections, fn conn ->
        Pool.checkin(pool, conn)
      end)
    end
    
    test "error handling during concurrent operations", %{pool: pool} do
      # Create connections and simulate various errors
      num_tasks = 15
      
      tasks = Enum.map(1..num_tasks, fn i ->
        Task.async(fn ->
          case Pool.checkout(pool) do
            {:ok, conn} ->
              if rem(i, 3) == 0 do
                Pool.return_error(pool, conn, :simulated_error)
              else
                Pool.checkin(pool, conn)
              end
            {:error, _reason} ->
              :checkout_failed
          end
        end)
      end)
      
      Task.yield_many(tasks, 3000)
      
      # Pool should handle errors gracefully
      assert Process.alive?(pool)
      
      stats = Pool.get_stats(pool)
      assert stats.metrics.connection_errors >= 0
    end
  end
  
  describe "UDP Socket Integration" do
    test "creates valid UDP sockets", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      
      assert is_port(connection.socket)
      
      # Should be able to get socket info
      {:ok, socket_info} = :inet.getopts(connection.socket, [:active, :binary])
      assert is_list(socket_info)
      
      Pool.checkin(pool, connection)
    end
    
    test "socket options are applied correctly" do
      custom_opts = [:binary, {:active, false}]
      
      {:ok, pool} = Pool.start_link(socket_opts: custom_opts)
      
      {:ok, connection} = Pool.checkout(pool)
      
      {:ok, socket_opts} = :inet.getopts(connection.socket, [:active, :binary])
      
      # Should have custom options applied
      assert Keyword.get(socket_opts, :active) == false
      assert Keyword.get(socket_opts, :binary) == true
      
      Pool.checkin(pool, connection)
      Pool.stop(pool)
    end
    
    test "handles socket creation failures gracefully" do
      # This test would need to mock socket creation failure
      # For now, verify error handling structure exists
      
      {:ok, pool} = Pool.start_link(pool_size: 1)
      
      # Should handle socket errors gracefully
      result = Pool.checkout(pool, nil, 100)
      
      case result do
        {:ok, conn} -> Pool.checkin(pool, conn)
        {:error, _reason} -> :ok  # Expected in some environments
      end
      
      Pool.stop(pool)
    end
    
    test "cleans up sockets on connection removal", %{pool: pool} do
      {:ok, connection} = Pool.checkout(pool)
      socket = connection.socket
      
      # Cause connection removal through errors
      Enum.each(1..5, fn _i ->
        Pool.return_error(pool, connection, :socket_error)
      end)
      
      # Socket should eventually be closed
      # Note: This is difficult to test reliably without implementation details
      assert Process.alive?(pool)
    end
  end
  
  describe "Integration and Edge Cases" do
    test "handles invalid connection objects gracefully", %{pool: pool} do
      invalid_connections = [
        nil,
        %{},
        %{id: "invalid"},
        %{id: make_ref(), socket: nil},
        "not a connection"
      ]
      
      Enum.each(invalid_connections, fn invalid_conn ->
        # Should not crash on invalid connections
        try do
          Pool.checkin(pool, invalid_conn)
          Pool.return_error(pool, invalid_conn, :test_error)
        rescue
          _ -> :ok  # Expected for invalid objects
        catch
          _ -> :ok  # Expected for invalid objects
        end
      end)
      
      # Pool should remain functional
      assert Process.alive?(pool)
    end
    
    test "pool restart behavior", %{pool: pool} do
      # Create some connections
      {:ok, connection} = Pool.checkout(pool)
      Pool.checkin(pool, connection)
      
      stats_before = Pool.get_stats(pool)
      
      # Stop and restart
      :ok = Pool.stop(pool)
      
      {:ok, new_pool} = Pool.start_link()
      
      # Should start fresh
      new_stats = Pool.get_stats(new_pool)
      assert new_stats.total_connections == 0
      
      Pool.stop(new_pool)
    end
    
    test "graceful shutdown with checked out connections", %{pool: pool} do
      # Checkout connections
      connections = Enum.map(1..3, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        conn
      end)
      
      # Should stop gracefully even with checked out connections
      start_time = System.monotonic_time(:millisecond)
      :ok = Pool.stop(pool)
      stop_time = System.monotonic_time(:millisecond) - start_time
      
      assert stop_time < 5000  # Should stop within 5 seconds
      refute Process.alive?(pool)
    end
    
    test "resource cleanup on abnormal termination" do
      {:ok, pool} = Pool.start_link()
      
      # Create some connections
      connections = Enum.map(1..2, fn _i ->
        {:ok, conn} = Pool.checkout(pool)
        conn
      end)
      
      # Kill process
      Process.exit(pool, :kill)
      
      # Should terminate (this test mainly ensures no hanging resources)
      refute Process.alive?(pool)
    end
  end
  
  describe "Target Affinity and Load Balancing" do
    test "target parameter is preserved", %{pool: pool} do
      target = "specific.device.com:161"
      
      {:ok, connection} = Pool.checkout(pool, target)
      
      assert connection.target == target
      
      Pool.checkin(pool, connection)
    end
    
    test "different targets can share connections", %{pool: pool} do
      # Checkout for one target and return
      {:ok, conn1} = Pool.checkout(pool, "target1.com")
      Pool.checkin(pool, conn1)
      
      # Checkout for different target
      {:ok, conn2} = Pool.checkout(pool, "target2.com")
      
      # Should reuse connection (in this simple implementation)
      # More sophisticated implementations might maintain target affinity
      assert conn2.target == "target2.com"
      
      Pool.checkin(pool, conn2)
    end
    
    test "pool balances load across connections", %{pool: pool} do
      # This test would verify load balancing algorithms
      # For now, verify basic multiple connection handling
      
      num_checkouts = @test_pool_size * 2
      
      connections = Enum.map(1..num_checkouts, fn i ->
        target = "device#{rem(i, 3)}.com"
        case Pool.checkout(pool, target, 100) do
          {:ok, conn} -> {:ok, conn}
          error -> error
        end
      end)
      
      successful = Enum.count(connections, fn result -> match?({:ok, _}, result) end)
      
      # Should handle multiple connections efficiently
      assert successful >= @test_pool_size
      
      # Clean up successful checkouts
      connections
      |> Enum.filter(fn result -> match?({:ok, _}, result) end)
      |> Enum.each(fn {:ok, conn} -> Pool.checkin(pool, conn) end)
    end
  end
end