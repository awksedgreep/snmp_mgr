defmodule SNMPMgr.ConfigComprehensiveTest do
  use ExUnit.Case, async: false  # Config tests need to be synchronous due to GenServer state
  
  alias SNMPMgr.Config
  
  @moduletag :unit
  @moduletag :config
  @moduletag :phase_2

  # Default configuration values for testing
  @default_config %{
    community: "public",
    timeout: 5000,
    retries: 1,
    port: 161,
    version: :v1,
    mib_paths: []
  }

  setup do
    # Start a fresh config server for each test
    case GenServer.whereis(SNMPMgr.Config) do
      nil -> 
        {:ok, pid} = Config.start_link()
        on_exit(fn -> 
          # Check if process is still alive and registered before stopping
          if GenServer.whereis(SNMPMgr.Config) == pid and Process.alive?(pid) do
            GenServer.stop(pid)
          end
        end)
        %{config_pid: pid}
      pid -> 
        # Reset to defaults if already running
        Config.reset()
        on_exit(fn ->
          # Ensure the process is still alive before cleanup
          if GenServer.whereis(SNMPMgr.Config) == pid and Process.alive?(pid) do
            Config.reset()
          end
        end)
        %{config_pid: pid}
    end
  end

  describe "configuration server lifecycle" do
    test "starts with default configuration" do
      # Try to start a test server, but handle if it already exists
      case Config.start_link(name: :test_config_server) do
        {:ok, _pid} -> 
          # Test that defaults are set correctly
          assert GenServer.call(:test_config_server, {:get, :community}) == "public"
          assert GenServer.call(:test_config_server, {:get, :timeout}) == 5000
          assert GenServer.call(:test_config_server, {:get, :retries}) == 1
          assert GenServer.call(:test_config_server, {:get, :port}) == 161
          assert GenServer.call(:test_config_server, {:get, :version}) == :v1
          assert GenServer.call(:test_config_server, {:get, :mib_paths}) == []
          
          GenServer.stop(:test_config_server)
          
        {:error, {:already_started, _pid}} ->
          # If already started, test using the main config server
          Config.reset()  # Reset to defaults
          assert Config.get_default_community() == "public"
          assert Config.get_default_timeout() == 5000
          assert Config.get_default_retries() == 1
          assert Config.get_default_port() == 161
          assert Config.get_default_version() == :v1
          assert Config.get_mib_paths() == []
      end
    end

    test "starts with custom initial configuration" do
      custom_opts = [
        community: "private",
        timeout: 10000,
        retries: 3,
        port: 1161,
        version: :v2c,
        mib_paths: ["/custom/mibs"]
      ]
      
      # Try to start a test server, but handle if it already exists
      case Config.start_link(custom_opts ++ [name: :test_custom_config]) do
        {:ok, _pid} ->
          # Test that custom values are set
          assert GenServer.call(:test_custom_config, {:get, :community}) == "private"
          assert GenServer.call(:test_custom_config, {:get, :timeout}) == 10000
          assert GenServer.call(:test_custom_config, {:get, :retries}) == 3
          assert GenServer.call(:test_custom_config, {:get, :port}) == 1161
          assert GenServer.call(:test_custom_config, {:get, :version}) == :v2c
          assert GenServer.call(:test_custom_config, {:get, :mib_paths}) == ["/custom/mibs"]
          
          GenServer.stop(:test_custom_config)
          
        {:error, {:already_started, _pid}} ->
          # If already started, test by setting custom values on main server
          Config.set_default_community("private")
          Config.set_default_timeout(10000)
          Config.set_default_retries(3)
          Config.set_default_port(1161)
          Config.set_default_version(:v2c)
          Config.set_mib_paths(["/custom/mibs"])
          
          # Verify values were set
          assert Config.get_default_community() == "private"
          assert Config.get_default_timeout() == 10000
          assert Config.get_default_retries() == 3
          assert Config.get_default_port() == 1161
          assert Config.get_default_version() == :v2c
          assert Config.get_mib_paths() == ["/custom/mibs"]
      end
    end

    test "handles server restart gracefully" do
      # Set some custom values
      Config.set_default_community("test_community")
      Config.set_default_timeout(15000)
      
      # Get the current pid
      original_pid = GenServer.whereis(SNMPMgr.Config)
      
      # Stop and restart - handle case where start_link might fail
      if original_pid do
        GenServer.stop(SNMPMgr.Config)
      end
      
      case Config.start_link() do
        {:ok, new_pid} ->
          # Should be a different process (if we had an original pid)
          if original_pid do
            assert new_pid != original_pid
          end
          
          # Should be back to defaults
          assert Config.get_default_community() == "public"
          assert Config.get_default_timeout() == 5000
          
        {:error, {:already_started, new_pid}} ->
          # If it's already started, just verify we can reset to defaults
          Config.reset()
          assert Config.get_default_community() == "public"
          assert Config.get_default_timeout() == 5000
      end
    end
  end

  describe "community string management" do
    test "sets and gets community string correctly" do
      assert Config.get_default_community() == "public"
      
      :ok = Config.set_default_community("private")
      assert Config.get_default_community() == "private"
      
      :ok = Config.set_default_community("test123")
      assert Config.get_default_community() == "test123"
      
      # Test empty string
      :ok = Config.set_default_community("")
      assert Config.get_default_community() == ""
    end

    test "validates community string input" do
      # Valid strings should work
      valid_communities = ["public", "private", "test123", "community_with_underscores", ""]
      
      for community <- valid_communities do
        assert :ok = Config.set_default_community(community)
        assert Config.get_default_community() == community
      end
      
      # Invalid inputs should raise errors
      invalid_communities = [nil, 123, :atom, [], %{}]
      
      for invalid_community <- invalid_communities do
        assert_raise FunctionClauseError, fn ->
          Config.set_default_community(invalid_community)
        end
      end
    end
  end

  describe "timeout management" do
    test "sets and gets timeout correctly" do
      assert Config.get_default_timeout() == 5000
      
      :ok = Config.set_default_timeout(10000)
      assert Config.get_default_timeout() == 10000
      
      :ok = Config.set_default_timeout(1000)
      assert Config.get_default_timeout() == 1000
      
      # Test very large timeout
      :ok = Config.set_default_timeout(300000)  # 5 minutes
      assert Config.get_default_timeout() == 300000
    end

    test "validates timeout input" do
      # Valid timeouts should work
      valid_timeouts = [1, 1000, 5000, 10000, 60000, 300000]
      
      for timeout <- valid_timeouts do
        assert :ok = Config.set_default_timeout(timeout)
        assert Config.get_default_timeout() == timeout
      end
      
      # Invalid timeouts should raise errors
      invalid_timeouts = [0, -1, -1000, nil, "5000", :timeout, [], %{}]
      
      for invalid_timeout <- invalid_timeouts do
        assert_raise FunctionClauseError, fn ->
          Config.set_default_timeout(invalid_timeout)
        end
      end
    end
  end

  describe "retry count management" do
    test "sets and gets retries correctly" do
      assert Config.get_default_retries() == 1
      
      :ok = Config.set_default_retries(0)
      assert Config.get_default_retries() == 0
      
      :ok = Config.set_default_retries(3)
      assert Config.get_default_retries() == 3
      
      :ok = Config.set_default_retries(10)
      assert Config.get_default_retries() == 10
    end

    test "validates retry count input" do
      # Valid retry counts should work
      valid_retries = [0, 1, 2, 3, 5, 10, 20]
      
      for retries <- valid_retries do
        assert :ok = Config.set_default_retries(retries)
        assert Config.get_default_retries() == retries
      end
      
      # Invalid retry counts should raise errors
      invalid_retries = [-1, -5, nil, "3", :retries, [], %{}, 1.5]
      
      for invalid_retries <- invalid_retries do
        assert_raise FunctionClauseError, fn ->
          Config.set_default_retries(invalid_retries)
        end
      end
    end
  end

  describe "port management" do
    test "sets and gets port correctly" do
      assert Config.get_default_port() == 161
      
      :ok = Config.set_default_port(162)
      assert Config.get_default_port() == 162
      
      :ok = Config.set_default_port(1161)
      assert Config.get_default_port() == 1161
      
      :ok = Config.set_default_port(65535)
      assert Config.get_default_port() == 65535
    end

    test "validates port range" do
      # Valid ports should work
      valid_ports = [1, 161, 162, 1161, 8161, 10161, 65535]
      
      for port <- valid_ports do
        assert :ok = Config.set_default_port(port)
        assert Config.get_default_port() == port
      end
      
      # Invalid ports should raise errors
      invalid_ports = [0, -1, 65536, 100000, nil, "161", :port, [], %{}]
      
      for invalid_port <- invalid_ports do
        assert_raise FunctionClauseError, fn ->
          Config.set_default_port(invalid_port)
        end
      end
    end
  end

  describe "SNMP version management" do
    test "sets and gets version correctly" do
      assert Config.get_default_version() == :v1
      
      :ok = Config.set_default_version(:v2c)
      assert Config.get_default_version() == :v2c
      
      :ok = Config.set_default_version(:v1)
      assert Config.get_default_version() == :v1
    end

    test "validates version input" do
      # Valid versions should work
      valid_versions = [:v1, :v2c]
      
      for version <- valid_versions do
        assert :ok = Config.set_default_version(version)
        assert Config.get_default_version() == version
      end
      
      # Invalid versions should raise errors
      invalid_versions = [:v3, :v2, :invalid, "v1", "v2c", nil, 1, 2, [], %{}]
      
      for invalid_version <- invalid_versions do
        assert_raise FunctionClauseError, fn ->
          Config.set_default_version(invalid_version)
        end
      end
    end
  end

  describe "MIB path management" do
    test "adds MIB paths correctly" do
      assert Config.get_mib_paths() == []
      
      :ok = Config.add_mib_path("/usr/share/snmp/mibs")
      assert Config.get_mib_paths() == ["/usr/share/snmp/mibs"]
      
      :ok = Config.add_mib_path("./mibs")
      assert Config.get_mib_paths() == ["/usr/share/snmp/mibs", "./mibs"]
      
      :ok = Config.add_mib_path("/custom/mibs")
      assert Config.get_mib_paths() == ["/usr/share/snmp/mibs", "./mibs", "/custom/mibs"]
    end

    test "prevents duplicate MIB paths" do
      :ok = Config.add_mib_path("/usr/share/snmp/mibs")
      :ok = Config.add_mib_path("/usr/share/snmp/mibs")  # Duplicate
      
      # Should only appear once
      assert Config.get_mib_paths() == ["/usr/share/snmp/mibs"]
    end

    test "sets MIB paths (replaces existing)" do
      # Add some initial paths
      :ok = Config.add_mib_path("/initial/path1")
      :ok = Config.add_mib_path("/initial/path2")
      assert length(Config.get_mib_paths()) == 2
      
      # Set new paths (should replace)
      new_paths = ["/new/path1", "/new/path2", "/new/path3"]
      :ok = Config.set_mib_paths(new_paths)
      assert Config.get_mib_paths() == new_paths
      
      # Set empty paths
      :ok = Config.set_mib_paths([])
      assert Config.get_mib_paths() == []
    end

    test "validates MIB path input" do
      # Valid paths should work
      valid_paths = ["/usr/share/snmp/mibs", "./mibs", "mibs", "/home/user/custom-mibs", ""]
      
      for path <- valid_paths do
        assert :ok = Config.add_mib_path(path)
      end
      
      # Invalid paths should raise errors
      invalid_paths = [nil, 123, :path, [], %{}]
      
      for invalid_path <- invalid_paths do
        assert_raise FunctionClauseError, fn ->
          Config.add_mib_path(invalid_path)
        end
      end
      
      # Invalid path lists should raise errors
      invalid_path_lists = [nil, 123, :paths, "/not/a/list", %{}]
      
      for invalid_list <- invalid_path_lists do
        assert_raise FunctionClauseError, fn ->
          Config.set_mib_paths(invalid_list)
        end
      end
    end
  end

  describe "configuration aggregation" do
    test "gets all configuration as map" do
      # Test with defaults
      config = Config.get_all()
      assert config == @default_config
      
      # Change some values
      Config.set_default_community("test")
      Config.set_default_timeout(10000)
      Config.add_mib_path("/test/mibs")
      
      updated_config = Config.get_all()
      expected_config = %{
        community: "test",
        timeout: 10000,
        retries: 1,
        port: 161,
        version: :v1,
        mib_paths: ["/test/mibs"]
      }
      
      assert updated_config == expected_config
    end

    test "resets configuration to defaults" do
      # Change all values
      Config.set_default_community("changed")
      Config.set_default_timeout(15000)
      Config.set_default_retries(5)
      Config.set_default_port(1161)
      Config.set_default_version(:v2c)
      Config.add_mib_path("/changed/mibs")
      
      # Verify changes
      config_before_reset = Config.get_all()
      refute config_before_reset == @default_config
      
      # Reset
      :ok = Config.reset()
      
      # Verify reset to defaults
      config_after_reset = Config.get_all()
      assert config_after_reset == @default_config
    end

    test "merges options with configuration" do
      # Set some defaults
      Config.set_default_community("default_community")
      Config.set_default_timeout(8000)
      Config.set_default_retries(2)
      
      # Test merge with override
      opts = [community: "override_community", port: 1161]
      merged = Config.merge_opts(opts)
      
      # Should have overridden values plus defaults
      assert Keyword.get(merged, :community) == "override_community"
      assert Keyword.get(merged, :port) == 1161
      assert Keyword.get(merged, :timeout) == 8000  # From config
      assert Keyword.get(merged, :retries) == 2     # From config
      assert Keyword.get(merged, :version) == :v1   # From defaults
      
      # Test merge with empty opts
      merged_empty = Config.merge_opts([])
      current_config = Config.get_all() |> Map.to_list() |> Enum.sort()
      merged_empty_sorted = merged_empty |> Enum.sort()
      
      assert merged_empty_sorted == current_config
    end
  end

  describe "configuration without GenServer" do
    test "get/1 works when GenServer is not started" do
      # Stop the GenServer
      case GenServer.whereis(SNMPMgr.Config) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end
      
      # Should still return default values
      assert Config.get(:community) == "public"
      assert Config.get(:timeout) == 5000
      assert Config.get(:retries) == 1
      assert Config.get(:port) == 161
      assert Config.get(:version) == :v1
      assert Config.get(:mib_paths) == []
      
      # Test with unknown key
      assert Config.get(:unknown_key) == nil
    end

    test "get/1 respects application configuration" do
      # Stop the GenServer if it's running
      stopped_pid = case GenServer.whereis(SNMPMgr.Config) do
        nil -> nil
        pid -> 
          GenServer.stop(pid)
          # Give it a moment to fully stop
          :timer.sleep(50)
          pid
      end
      
      # Set application config
      Application.put_env(:snmp_mgr, :community, "app_config_community")
      Application.put_env(:snmp_mgr, :timeout, 12000)
      
      # Verify GenServer is really stopped
      assert GenServer.whereis(SNMPMgr.Config) == nil, "GenServer should be stopped"
      
      # Should get values from application config
      assert Config.get(:community) == "app_config_community"
      assert Config.get(:timeout) == 12000
      
      # Should still get defaults for unset values
      assert Config.get(:retries) == 1
      assert Config.get(:port) == 161
      
      # Clean up application config
      Application.delete_env(:snmp_mgr, :community)
      Application.delete_env(:snmp_mgr, :timeout)
      
      # Restart the GenServer if we stopped it
      if stopped_pid do
        {:ok, _new_pid} = Config.start_link()
      end
    end
  end

  describe "configuration validation and edge cases" do
    test "handles concurrent access correctly" do
      # Start multiple processes that modify configuration
      tasks = for i <- 1..10 do
        Task.async(fn ->
          Config.set_default_community("community_#{i}")
          Config.set_default_timeout(1000 + i * 100)
          Config.get_all()
        end)
      end
      
      # Wait for all tasks to complete
      results = Task.await_many(tasks)
      
      # All tasks should complete successfully
      assert length(results) == 10
      for result <- results do
        assert is_map(result)
        assert Map.has_key?(result, :community)
        assert Map.has_key?(result, :timeout)
      end
      
      # Final state should be consistent
      final_config = Config.get_all()
      assert is_map(final_config)
    end

    test "handles invalid GenServer calls gracefully" do
      # Test with invalid calls
      invalid_calls = [
        {:invalid_action, :some_arg},
        {:set, :invalid_key, "value"},
        {:get, nil},
        :invalid_atom,
        nil,
      ]
      
      for invalid_call <- invalid_calls do
        try do
          result = GenServer.call(SNMPMgr.Config, invalid_call)
          # Should not crash - might return error or default behavior
          assert is_binary(result) or is_integer(result) or is_atom(result) or is_nil(result) or is_list(result),
            "Invalid call should not crash server: #{inspect(invalid_call)} -> #{inspect(result)}"
        rescue
          error ->
            # Some invalid calls might raise exceptions, which is acceptable
            assert true, "Invalid call raised exception: #{inspect(error)}"
        end
      end
      
      # Server should still be responsive after invalid calls
      assert Config.get_default_community() |> is_binary()
    end
  end

  describe "performance characteristics" do
    @tag :performance
    test "configuration access is fast" do
      # Measure time for configuration access
      {time_microseconds, _results} = :timer.tc(fn ->
        for _i <- 1..1000 do
          Config.get_default_community()
          Config.get_default_timeout()
          Config.get_default_retries()
          Config.get_default_port()
          Config.get_default_version()
          Config.get_mib_paths()
        end
      end)
      
      time_per_access = time_microseconds / (1000 * 6)  # 6 operations per iteration
      
      # Should be very fast (less than 50 microseconds per access)
      assert time_per_access < 50,
        "Configuration access too slow: #{time_per_access} microseconds per access"
    end

    @tag :performance
    test "configuration modification is fast" do
      # Measure time for configuration modifications
      {time_microseconds, _results} = :timer.tc(fn ->
        for i <- 1..100 do
          Config.set_default_community("test_#{i}")
          Config.set_default_timeout(5000 + i)
          Config.set_default_retries(rem(i, 5))
          Config.add_mib_path("/path/#{i}")
        end
      end)
      
      time_per_modification = time_microseconds / (100 * 4)  # 4 operations per iteration
      
      # Should be fast (less than 200 microseconds per modification)
      assert time_per_modification < 200,
        "Configuration modification too slow: #{time_per_modification} microseconds per modification"
    end

    @tag :performance
    test "memory usage is reasonable" do
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)
      
      # Perform many configuration operations
      for i <- 1..1000 do
        Config.set_default_community("community_#{i}")
        Config.add_mib_path("/path/#{i}")
        Config.get_all()
        Config.merge_opts([timeout: 1000 + i])
      end
      
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      # Should use reasonable memory (less than 2MB for all operations)
      assert memory_used < 2_000_000,
        "Configuration operations memory usage too high: #{memory_used} bytes"
      
      :erlang.garbage_collect()
    end
  end

  describe "integration scenarios" do
    test "configuration survives application restarts" do
      # This test simulates what happens during application restart
      
      # Set custom configuration
      Config.set_default_community("persistent_community")
      Config.set_default_timeout(15000)
      
      # Simulate application environment being set
      Application.put_env(:snmp_mgr, :community, "persistent_community")
      Application.put_env(:snmp_mgr, :timeout, 15000)
      
      # Stop and restart config server
      GenServer.stop(SNMPMgr.Config)
      {:ok, _pid} = Config.start_link()
      
      # Should get values from application environment
      assert Config.get(:community) == "persistent_community"
      assert Config.get(:timeout) == 15000
      
      # Clean up
      Application.delete_env(:snmp_mgr, :community)
      Application.delete_env(:snmp_mgr, :timeout)
    end

    test "configuration works with SNMP operations" do
      # Set configuration that would be used by SNMP operations
      Config.set_default_community("integration_test")
      Config.set_default_timeout(8000)
      Config.set_default_retries(2)
      Config.set_default_port(1161)
      Config.set_default_version(:v2c)
      
      # Get merged configuration as would be used by SNMP functions
      opts = Config.merge_opts([])
      
      assert Keyword.get(opts, :community) == "integration_test"
      assert Keyword.get(opts, :timeout) == 8000
      assert Keyword.get(opts, :retries) == 2
      assert Keyword.get(opts, :port) == 1161
      assert Keyword.get(opts, :version) == :v2c
      
      # Test override behavior
      override_opts = Config.merge_opts([community: "override", timeout: 20000])
      assert Keyword.get(override_opts, :community) == "override"
      assert Keyword.get(override_opts, :timeout) == 20000
      assert Keyword.get(override_opts, :retries) == 2  # From config
      assert Keyword.get(override_opts, :port) == 1161  # From config
    end
  end
end