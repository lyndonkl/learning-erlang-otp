defmodule AgentFramework.OTPTest do
  use ExUnit.Case, async: false

  alias AgentFramework.{AgentServer, AgentSupervisor}

  # ============================================
  # AgentServer Tests
  # ============================================

  describe "AgentServer.start_link/2" do
    test "starts a GenServer process" do
      {:ok, pid} = AgentServer.start_link("Test-Agent")
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "initializes with correct state" do
      {:ok, pid} = AgentServer.start_link("Test-Agent")
      state = AgentServer.get_state(pid)

      assert state.name == "Test-Agent"
      assert state.status == :idle
      assert state.memory == %{}
      assert state.inbox == []
      assert state.processed_count == 0

      GenServer.stop(pid)
    end

    test "accepts initial memory" do
      {:ok, pid} = AgentServer.start_link("Test-Agent", memory: %{key: "value"})
      state = AgentServer.get_state(pid)

      assert state.memory == %{key: "value"}

      GenServer.stop(pid)
    end

    test "can start with a registered name" do
      {:ok, pid} = AgentServer.start_link("Named-Agent", name: :test_named_agent)
      assert Process.whereis(:test_named_agent) == pid
      GenServer.stop(pid)
    end
  end

  describe "AgentServer.get_status/1" do
    test "returns :idle for new agent" do
      {:ok, pid} = AgentServer.start_link("Status-Agent")
      assert AgentServer.get_status(pid) == :idle
      GenServer.stop(pid)
    end
  end

  describe "AgentServer memory operations" do
    setup do
      {:ok, pid} = AgentServer.start_link("Memory-Agent")
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)
      {:ok, server: pid}
    end

    test "remember and recall", %{server: pid} do
      :ok = AgentServer.remember(pid, :context, "researching")
      # Give cast time to process
      Process.sleep(10)
      assert AgentServer.recall(pid, :context) == "researching"
    end

    test "recall missing key returns nil", %{server: pid} do
      assert AgentServer.recall(pid, :missing) == nil
    end

    test "forget_all clears memory", %{server: pid} do
      AgentServer.remember(pid, :a, 1)
      AgentServer.remember(pid, :b, 2)
      Process.sleep(10)
      AgentServer.forget_all(pid)
      Process.sleep(10)

      state = AgentServer.get_state(pid)
      assert state.memory == %{}
    end

    test "multiple remember operations", %{server: pid} do
      AgentServer.remember(pid, :one, 1)
      AgentServer.remember(pid, :two, 2)
      AgentServer.remember(pid, :three, 3)
      Process.sleep(20)

      assert AgentServer.recall(pid, :one) == 1
      assert AgentServer.recall(pid, :two) == 2
      assert AgentServer.recall(pid, :three) == 3
    end
  end

  describe "AgentServer task operations" do
    setup do
      {:ok, pid} = AgentServer.start_link("Task-Agent")
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)
      {:ok, server: pid}
    end

    test "send_task adds to inbox", %{server: pid} do
      AgentServer.send_task(pid, :search, %{query: "test"})
      Process.sleep(10)
      assert AgentServer.inbox_count(pid) == 1
    end

    test "process_next processes a task", %{server: pid} do
      AgentServer.send_task(pid, :search, %{query: "OTP"})
      Process.sleep(10)

      {:ok, task, result} = AgentServer.process_next(pid)
      assert task.payload.action == :search
      assert result == {:ok, "Search results for: OTP"}
    end

    test "process_next on empty inbox returns :empty", %{server: pid} do
      assert AgentServer.process_next(pid) == {:empty, nil}
    end

    test "process_next increments processed_count", %{server: pid} do
      AgentServer.send_task(pid, :search, %{query: "test"})
      Process.sleep(10)
      AgentServer.process_next(pid)

      state = AgentServer.get_state(pid)
      assert state.processed_count == 1
    end

    test "multiple tasks are processed in order", %{server: pid} do
      AgentServer.send_task(pid, :search, %{query: "first"})
      AgentServer.send_task(pid, :search, %{query: "second"})
      AgentServer.send_task(pid, :search, %{query: "third"})
      Process.sleep(20)

      {:ok, task1, _} = AgentServer.process_next(pid)
      {:ok, task2, _} = AgentServer.process_next(pid)
      {:ok, task3, _} = AgentServer.process_next(pid)

      assert task1.payload.params.query == "first"
      assert task2.payload.params.query == "second"
      assert task3.payload.params.query == "third"
    end

    test "handles analyze task", %{server: pid} do
      AgentServer.send_task(pid, :analyze, %{data: "some data"})
      Process.sleep(10)

      {:ok, task, result} = AgentServer.process_next(pid)
      assert task.payload.action == :analyze
      assert result == {:ok, "Analysis of: some data"}
    end

    test "handles unknown action", %{server: pid} do
      AgentServer.send_task(pid, :unknown_action, %{})
      Process.sleep(10)

      {:ok, _task, result} = AgentServer.process_next(pid)
      assert result == {:error, {:unknown_action, :unknown_action}}
    end
  end

  describe "AgentServer.stop/1" do
    test "stops the agent gracefully" do
      {:ok, pid} = AgentServer.start_link("Stop-Agent")
      assert Process.alive?(pid)

      :ok = AgentServer.stop(pid)
      Process.sleep(10)

      refute Process.alive?(pid)
    end
  end

  # ============================================
  # AgentSupervisor Tests
  # ============================================

  describe "AgentSupervisor.start_link/1" do
    test "starts a DynamicSupervisor" do
      name = :"test_sup_#{System.unique_integer([:positive])}"
      {:ok, sup} = AgentSupervisor.start_link(name: name)
      assert Process.alive?(sup)
      Supervisor.stop(sup)
    end
  end

  describe "AgentSupervisor agent management" do
    setup do
      name = :"test_sup_#{System.unique_integer([:positive])}"
      {:ok, sup} = AgentSupervisor.start_link(name: name)
      on_exit(fn ->
        try do
          if Process.alive?(sup), do: Supervisor.stop(sup, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)
      {:ok, supervisor: name, sup_pid: sup}
    end

    test "starts agents", %{supervisor: sup} do
      {:ok, pid} = AgentSupervisor.start_agent(sup, "Worker-1", [])
      assert Process.alive?(pid)
    end

    test "starts multiple agents", %{supervisor: sup} do
      {:ok, pid1} = AgentSupervisor.start_agent(sup, "Worker-1", [])
      {:ok, pid2} = AgentSupervisor.start_agent(sup, "Worker-2", [])
      {:ok, pid3} = AgentSupervisor.start_agent(sup, "Worker-3", [])

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert Process.alive?(pid3)

      agents = AgentSupervisor.list_agents(sup)
      assert length(agents) == 3
    end

    test "list_agents returns all agent pids", %{supervisor: sup} do
      {:ok, pid1} = AgentSupervisor.start_agent(sup, "Worker-1", [])
      {:ok, pid2} = AgentSupervisor.start_agent(sup, "Worker-2", [])

      agents = AgentSupervisor.list_agents(sup)
      assert pid1 in agents
      assert pid2 in agents
    end

    test "count_agents returns correct counts", %{supervisor: sup} do
      AgentSupervisor.start_agent(sup, "Worker-1", [])
      AgentSupervisor.start_agent(sup, "Worker-2", [])

      counts = AgentSupervisor.count_agents(sup)
      assert counts.active == 2
      assert counts.workers == 2
    end

    test "stop_agent terminates the agent", %{supervisor: sup} do
      {:ok, pid} = AgentSupervisor.start_agent(sup, "Worker-1", [])
      assert Process.alive?(pid)

      :ok = AgentSupervisor.stop_agent(sup, pid)
      Process.sleep(50)

      refute Process.alive?(pid)
      assert AgentSupervisor.list_agents(sup) == []
    end

    test "restarts crashed agents", %{supervisor: sup} do
      {:ok, pid} = AgentSupervisor.start_agent(sup, "Crashy", [])
      original_pid = pid

      # Crash the agent
      Process.exit(pid, :kill)
      Process.sleep(100)

      # Check it was restarted
      agents = AgentSupervisor.list_agents(sup)
      assert length(agents) == 1

      [new_pid] = agents
      assert is_pid(new_pid)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end

    test "agent state is reset after crash", %{supervisor: sup} do
      {:ok, pid} = AgentSupervisor.start_agent(sup, "Stateful", [])

      # Add some state
      AgentServer.remember(pid, :data, "important")
      Process.sleep(10)
      assert AgentServer.recall(pid, :data) == "important"

      # Crash it
      Process.exit(pid, :kill)
      Process.sleep(100)

      # Get new pid and check state is reset
      [new_pid] = AgentSupervisor.list_agents(sup)
      assert AgentServer.recall(new_pid, :data) == nil
    end
  end

  # ============================================
  # Integration Tests
  # ============================================

  describe "OTP Integration" do
    setup do
      name = :"integration_sup_#{System.unique_integer([:positive])}"
      {:ok, sup} = AgentSupervisor.start_link(name: name)
      on_exit(fn ->
        if Process.alive?(sup), do: Supervisor.stop(sup)
      end)
      {:ok, supervisor: name}
    end

    test "full workflow with supervisor", %{supervisor: sup} do
      # Start agents
      {:ok, w1} = AgentSupervisor.start_agent(sup, "Worker-1", [])
      {:ok, w2} = AgentSupervisor.start_agent(sup, "Worker-2", [])

      # Use agents
      AgentServer.remember(w1, :task, "research")
      AgentServer.remember(w2, :task, "write")
      Process.sleep(20)

      assert AgentServer.recall(w1, :task) == "research"
      assert AgentServer.recall(w2, :task) == "write"

      # Send and process tasks
      AgentServer.send_task(w1, :search, %{query: "Elixir OTP"})
      Process.sleep(10)

      {:ok, task, result} = AgentServer.process_next(w1)
      assert task.payload.action == :search
      assert {:ok, _} = result

      # Verify counts
      counts = AgentSupervisor.count_agents(sup)
      assert counts.active == 2
    end

    test "crash recovery maintains other agents", %{supervisor: sup} do
      {:ok, w1} = AgentSupervisor.start_agent(sup, "Worker-1", [])
      {:ok, w2} = AgentSupervisor.start_agent(sup, "Worker-2", [])

      # Set state on both
      AgentServer.remember(w1, :id, 1)
      AgentServer.remember(w2, :id, 2)
      Process.sleep(20)

      # Crash w1
      Process.exit(w1, :kill)
      Process.sleep(100)

      # w2 should be unaffected
      assert AgentServer.recall(w2, :id) == 2

      # We should still have 2 agents
      assert AgentSupervisor.count_agents(sup).active == 2
    end
  end

  # ============================================
  # child_spec Tests
  # ============================================

  describe "AgentServer.child_spec/1" do
    test "accepts string name" do
      spec = AgentServer.child_spec("Worker-1")
      assert spec.id == {AgentServer, "Worker-1"}
      assert spec.start == {AgentServer, :start_link, ["Worker-1", []]}
      assert spec.restart == :permanent
    end

    test "accepts tuple with name and options" do
      spec = AgentServer.child_spec({"Worker-1", [memory: %{a: 1}]})
      assert spec.id == {AgentServer, "Worker-1"}
      assert spec.start == {AgentServer, :start_link, ["Worker-1", [memory: %{a: 1}]]}
    end
  end
end
