defmodule AgentFramework.ProcessTest do
  use ExUnit.Case, async: false

  alias AgentFramework.{ProcessAgent, AgentRegistry, AgentMonitor}

  # ============================================
  # ProcessAgent Tests
  # ============================================

  describe "ProcessAgent.start/2" do
    test "starts an agent process" do
      {:ok, pid} = ProcessAgent.start("Test-Agent")
      assert Process.alive?(pid)
      ProcessAgent.stop(pid)
    end

    test "agent has correct initial state" do
      {:ok, pid} = ProcessAgent.start("Test-Agent")
      {:ok, state} = ProcessAgent.get_state(pid)

      assert state.name == "Test-Agent"
      assert state.status == :idle
      assert state.memory == %{}
      assert state.inbox == []
      assert state.processed_count == 0

      ProcessAgent.stop(pid)
    end

    test "accepts initial memory" do
      {:ok, pid} = ProcessAgent.start("Test-Agent", memory: %{key: "value"})
      {:ok, state} = ProcessAgent.get_state(pid)

      assert state.memory == %{key: "value"}

      ProcessAgent.stop(pid)
    end
  end

  describe "ProcessAgent memory operations" do
    setup do
      {:ok, pid} = ProcessAgent.start("Memory-Agent")
      on_exit(fn -> ProcessAgent.stop(pid) end)
      {:ok, pid: pid}
    end

    test "remember stores values", %{pid: pid} do
      :ok = ProcessAgent.remember(pid, :context, "researching")
      {:ok, value} = ProcessAgent.recall(pid, :context)
      assert value == "researching"
    end

    test "recall returns nil for missing keys", %{pid: pid} do
      {:ok, value} = ProcessAgent.recall(pid, :missing)
      assert value == nil
    end

    test "forget_all clears memory", %{pid: pid} do
      ProcessAgent.remember(pid, :a, 1)
      ProcessAgent.remember(pid, :b, 2)
      :ok = ProcessAgent.forget_all(pid)

      {:ok, state} = ProcessAgent.get_state(pid)
      assert state.memory == %{}
    end
  end

  describe "ProcessAgent task operations" do
    setup do
      {:ok, pid} = ProcessAgent.start("Task-Agent")
      on_exit(fn -> ProcessAgent.stop(pid) end)
      {:ok, pid: pid}
    end

    test "send_task adds to inbox", %{pid: pid} do
      ProcessAgent.send_task(pid, :search, %{query: "test"})
      {:ok, count} = ProcessAgent.inbox_count(pid)
      assert count == 1
    end

    test "process_next processes a task", %{pid: pid} do
      ProcessAgent.send_task(pid, :search, %{query: "OTP"})
      {:ok, task, result} = ProcessAgent.process_next(pid)

      assert task.payload.action == :search
      assert result == {:ok, "Search results for: OTP"}
    end

    test "process_next returns empty when inbox empty", %{pid: pid} do
      result = ProcessAgent.process_next(pid)
      assert result == {:empty, nil}
    end

    test "process_next increments processed_count", %{pid: pid} do
      ProcessAgent.send_task(pid, :search, %{query: "test"})
      ProcessAgent.process_next(pid)

      {:ok, state} = ProcessAgent.get_state(pid)
      assert state.processed_count == 1
    end

    test "multiple tasks are processed in order", %{pid: pid} do
      ProcessAgent.send_task(pid, :search, %{query: "first"})
      ProcessAgent.send_task(pid, :search, %{query: "second"})

      {:ok, task1, _} = ProcessAgent.process_next(pid)
      {:ok, task2, _} = ProcessAgent.process_next(pid)

      assert task1.payload.params.query == "first"
      assert task2.payload.params.query == "second"
    end
  end

  describe "ProcessAgent status" do
    test "get_status returns current status" do
      {:ok, pid} = ProcessAgent.start("Status-Agent")
      {:ok, status} = ProcessAgent.get_status(pid)
      assert status == :idle
      ProcessAgent.stop(pid)
    end
  end

  # ============================================
  # AgentRegistry Tests
  # ============================================

  describe "AgentRegistry" do
    setup do
      # Generate a unique registry name for each test
      registry_name = :"test_registry_#{System.unique_integer([:positive])}"

      # Start a fresh registry for each test
      {:ok, registry_pid} = Registry.start_link(keys: :unique, name: registry_name)

      on_exit(fn ->
        try do
          if Process.alive?(registry_pid) do
            GenServer.stop(registry_pid, :normal, 100)
          end
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, registry: registry_name}
    end

    test "register and lookup", %{registry: registry_name} do
      # Register in a spawned process
      test_pid = self()

      spawn(fn ->
        Registry.register(registry_name, "Worker-1", %{})
        send(test_pid, {:registered, self()})

        receive do
          :stop -> :ok
        end
      end)

      pid = receive do
        {:registered, pid} -> pid
      end

      Process.sleep(50)

      case Registry.lookup(registry_name, "Worker-1") do
        [{found_pid, _}] -> assert found_pid == pid
        [] -> flunk("Worker-1 not found in registry")
      end

      send(pid, :stop)
    end

    test "lookup returns empty for nonexistent agent", %{registry: registry_name} do
      assert [] == Registry.lookup(registry_name, "NonExistent")
    end

    test "list returns all registered agents", %{registry: registry_name} do
      test_pid = self()

      pids = for name <- ["Agent-A", "Agent-B", "Agent-C"] do
        spawn(fn ->
          Registry.register(registry_name, name, %{})
          send(test_pid, :registered)

          receive do
            :stop -> :ok
          end
        end)
      end

      # Wait for all registrations
      for _ <- 1..3, do: receive do: (:registered -> :ok)
      Process.sleep(50)

      names = Registry.select(registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
      assert length(names) == 3
      assert "Agent-A" in names
      assert "Agent-B" in names
      assert "Agent-C" in names

      # Cleanup
      Enum.each(pids, &send(&1, :stop))
    end

    test "automatic cleanup when process dies", %{registry: registry_name} do
      test_pid = self()

      pid = spawn(fn ->
        Registry.register(registry_name, "Temp-Agent", %{})
        send(test_pid, :registered)
        # Process exits immediately after registration
      end)

      receive do: (:registered -> :ok)

      # Wait for process to die and registry to clean up
      Process.sleep(100)
      refute Process.alive?(pid)

      assert [] == Registry.lookup(registry_name, "Temp-Agent")
    end
  end

  # ============================================
  # AgentMonitor Tests
  # ============================================

  describe "AgentMonitor" do
    test "start_link creates monitor" do
      {:ok, monitor} = AgentMonitor.start_link()
      assert Process.alive?(monitor)
      AgentMonitor.stop(monitor)
    end

    test "start_agent starts monitored agent" do
      {:ok, monitor} = AgentMonitor.start_link()
      {:ok, agent_pid} = AgentMonitor.start_agent(monitor, "Monitored-Agent")

      assert Process.alive?(agent_pid)

      agents = AgentMonitor.list_agents(monitor)
      assert {"Monitored-Agent", agent_pid} in agents

      AgentMonitor.stop(monitor)
    end

    test "monitors multiple agents" do
      {:ok, monitor} = AgentMonitor.start_link()

      {:ok, pid1} = AgentMonitor.start_agent(monitor, "Agent-1")
      {:ok, pid2} = AgentMonitor.start_agent(monitor, "Agent-2")
      {:ok, pid3} = AgentMonitor.start_agent(monitor, "Agent-3")

      agents = AgentMonitor.list_agents(monitor)
      assert length(agents) == 3
      assert {"Agent-1", pid1} in agents
      assert {"Agent-2", pid2} in agents
      assert {"Agent-3", pid3} in agents

      AgentMonitor.stop(monitor)
    end

    test "returns error for duplicate agent name" do
      {:ok, monitor} = AgentMonitor.start_link()
      {:ok, _} = AgentMonitor.start_agent(monitor, "Duplicate-Agent")

      result = AgentMonitor.start_agent(monitor, "Duplicate-Agent")
      assert result == {:error, :already_exists}

      AgentMonitor.stop(monitor)
    end

    test "restarts crashed agent with restart_policy :always" do
      {:ok, monitor} = AgentMonitor.start_link(restart_policy: :always)
      {:ok, original_pid} = AgentMonitor.start_agent(monitor, "Crash-Agent")

      # Crash the agent
      send(original_pid, {:crash, :test_crash})
      Process.sleep(300)

      # Should have been restarted
      agents = AgentMonitor.list_agents(monitor)
      assert length(agents) == 1
      [{name, new_pid}] = agents
      assert name == "Crash-Agent"
      assert new_pid != original_pid
      assert Process.alive?(new_pid)

      AgentMonitor.stop(monitor)
    end

    test "does not restart with restart_policy :never" do
      {:ok, monitor} = AgentMonitor.start_link(restart_policy: :never)
      {:ok, pid} = AgentMonitor.start_agent(monitor, "No-Restart-Agent")

      # Crash the agent
      send(pid, {:crash, :test_crash})
      Process.sleep(300)

      # Should NOT have been restarted
      agents = AgentMonitor.list_agents(monitor)
      assert agents == []

      AgentMonitor.stop(monitor)
    end

    test "does not restart normal exits with :transient policy" do
      {:ok, monitor} = AgentMonitor.start_link(restart_policy: :transient)
      {:ok, pid} = AgentMonitor.start_agent(monitor, "Transient-Agent")

      # Normal exit (stop)
      ProcessAgent.stop(pid)
      Process.sleep(300)

      # Should NOT have been restarted for normal exit
      agents = AgentMonitor.list_agents(monitor)
      assert agents == []

      AgentMonitor.stop(monitor)
    end

    test "status returns monitor info" do
      {:ok, monitor} = AgentMonitor.start_link(restart_policy: :always, max_restarts: 10)
      {:ok, _} = AgentMonitor.start_agent(monitor, "Status-Agent")

      status = AgentMonitor.status(monitor)
      assert status.agent_count == 1
      assert status.restart_policy == :always
      assert status.max_restarts == 10
      assert Map.has_key?(status.agents, "Status-Agent")

      AgentMonitor.stop(monitor)
    end

    test "respects max_restarts limit" do
      {:ok, monitor} = AgentMonitor.start_link(restart_policy: :always, max_restarts: 2)
      {:ok, pid} = AgentMonitor.start_agent(monitor, "Limited-Agent")

      # Crash multiple times
      send(pid, {:crash, :crash_1})
      Process.sleep(200)

      [{_, pid2}] = AgentMonitor.list_agents(monitor)
      send(pid2, {:crash, :crash_2})
      Process.sleep(200)

      [{_, pid3}] = AgentMonitor.list_agents(monitor)
      send(pid3, {:crash, :crash_3})
      Process.sleep(200)

      # Should have stopped restarting after max_restarts
      agents = AgentMonitor.list_agents(monitor)
      assert agents == []

      AgentMonitor.stop(monitor)
    end
  end

  # ============================================
  # Integration Tests
  # ============================================

  describe "Integration: Full workflow" do
    test "complete agent workflow" do
      # Start monitor
      {:ok, monitor} = AgentMonitor.start_link()

      # Start agents
      {:ok, worker1} = AgentMonitor.start_agent(monitor, "Worker-1")
      {:ok, worker2} = AgentMonitor.start_agent(monitor, "Worker-2")

      # Store memory
      ProcessAgent.remember(worker1, :task_type, :research)
      ProcessAgent.remember(worker2, :task_type, :analysis)

      # Verify memory
      {:ok, type1} = ProcessAgent.recall(worker1, :task_type)
      {:ok, type2} = ProcessAgent.recall(worker2, :task_type)
      assert type1 == :research
      assert type2 == :analysis

      # Send and process tasks
      ProcessAgent.send_task(worker1, :search, %{query: "Elixir OTP"})
      {:ok, task, result} = ProcessAgent.process_next(worker1)
      assert task.payload.action == :search
      assert {:ok, _} = result

      # Crash and restart
      send(worker1, {:crash, :test})
      Process.sleep(300)

      # Worker should be restarted
      agents = AgentMonitor.list_agents(monitor)
      assert length(agents) == 2
      assert Enum.any?(agents, fn {name, _} -> name == "Worker-1" end)

      # Cleanup
      AgentMonitor.stop(monitor)
    end
  end
end
