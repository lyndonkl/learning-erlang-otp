defmodule AgentFramework.AgentTest do
  use ExUnit.Case
  alias AgentFramework.{Agent, Message}

  describe "new/1" do
    test "creates agent with name" do
      agent = Agent.new("Worker-1")

      assert agent.name == "Worker-1"
    end

    test "initializes with idle state" do
      agent = Agent.new("Worker")

      assert agent.state == :idle
    end

    test "initializes with empty inbox" do
      agent = Agent.new("Worker")

      assert agent.inbox == []
    end

    test "initializes with empty memory" do
      agent = Agent.new("Worker")

      assert agent.memory == %{}
    end

    test "initializes processed_count to 0" do
      agent = Agent.new("Worker")

      assert agent.processed_count == 0
    end
  end

  describe "state transitions" do
    setup do
      {:ok, agent: Agent.new("Worker")}
    end

    test "set_busy/1 changes state to busy", %{agent: agent} do
      agent = Agent.set_busy(agent)
      assert agent.state == :busy
    end

    test "set_idle/1 changes state to idle", %{agent: agent} do
      agent = agent |> Agent.set_busy() |> Agent.set_idle()
      assert agent.state == :idle
    end

    test "set_waiting/1 changes state to waiting", %{agent: agent} do
      agent = Agent.set_waiting(agent)
      assert agent.state == :waiting
    end

    test "idle?/1 returns true when idle", %{agent: agent} do
      assert Agent.idle?(agent) == true
    end

    test "idle?/1 returns false when not idle", %{agent: agent} do
      agent = Agent.set_busy(agent)
      assert Agent.idle?(agent) == false
    end

    test "busy?/1 returns true when busy", %{agent: agent} do
      agent = Agent.set_busy(agent)
      assert Agent.busy?(agent) == true
    end
  end

  describe "inbox operations" do
    setup do
      agent = Agent.new("Worker")
      msg = Message.task("001", :search)
      {:ok, agent: agent, msg: msg}
    end

    test "receive_message/2 adds message to inbox", %{agent: agent, msg: msg} do
      agent = Agent.receive_message(agent, msg)

      assert length(agent.inbox) == 1
      assert hd(agent.inbox) == msg
    end

    test "receive_message/2 appends to end of inbox", %{agent: agent} do
      msg1 = Message.task("001", :first)
      msg2 = Message.task("002", :second)

      agent =
        agent
        |> Agent.receive_message(msg1)
        |> Agent.receive_message(msg2)

      [first, second] = agent.inbox
      assert first.payload.action == :first
      assert second.payload.action == :second
    end

    test "peek_message/1 returns nil for empty inbox", %{agent: agent} do
      assert Agent.peek_message(agent) == nil
    end

    test "peek_message/1 returns first message without removing", %{agent: agent, msg: msg} do
      agent = Agent.receive_message(agent, msg)

      assert Agent.peek_message(agent) == msg
      assert length(agent.inbox) == 1
    end

    test "pop_message/1 returns nil for empty inbox", %{agent: agent} do
      {msg, _agent} = Agent.pop_message(agent)
      assert msg == nil
    end

    test "pop_message/1 removes and returns first message", %{agent: agent, msg: msg} do
      agent = Agent.receive_message(agent, msg)
      {popped, agent} = Agent.pop_message(agent)

      assert popped == msg
      assert agent.inbox == []
    end

    test "inbox_count/1 returns number of messages", %{agent: agent} do
      assert Agent.inbox_count(agent) == 0

      agent =
        agent
        |> Agent.receive_message(Message.task("001", :a))
        |> Agent.receive_message(Message.task("002", :b))

      assert Agent.inbox_count(agent) == 2
    end
  end

  describe "memory operations" do
    setup do
      {:ok, agent: Agent.new("Worker")}
    end

    test "remember/3 stores value in memory", %{agent: agent} do
      agent = Agent.remember(agent, :fact, "Elixir is great")

      assert agent.memory[:fact] == "Elixir is great"
    end

    test "recall/3 retrieves value from memory", %{agent: agent} do
      agent = Agent.remember(agent, :key, "value")

      assert Agent.recall(agent, :key) == "value"
    end

    test "recall/3 returns default for missing key", %{agent: agent} do
      assert Agent.recall(agent, :missing, "default") == "default"
    end

    test "recall/3 returns nil by default for missing key", %{agent: agent} do
      assert Agent.recall(agent, :missing) == nil
    end

    test "forget_all/1 clears memory", %{agent: agent} do
      agent =
        agent
        |> Agent.remember(:a, 1)
        |> Agent.remember(:b, 2)
        |> Agent.forget_all()

      assert agent.memory == %{}
    end
  end

  describe "process_next/1" do
    setup do
      {:ok, agent: Agent.new("Worker")}
    end

    test "returns {:empty, agent} for empty inbox", %{agent: agent} do
      assert {:empty, ^agent} = Agent.process_next(agent)
    end

    test "processes task message", %{agent: agent} do
      msg = Message.task("001", :search)
      agent = Agent.receive_message(agent, msg)

      {:processed, agent, processed_msg} = Agent.process_next(agent)

      assert processed_msg == msg
      assert agent.inbox == []
      assert agent.processed_count == 1
      assert Agent.recall(agent, :last_action) == :search
    end

    test "processes response message", %{agent: agent} do
      msg = Message.response("001", {:ok, "result"})
      agent = Agent.receive_message(agent, msg)

      {:processed, agent, _msg} = Agent.process_next(agent)

      assert Agent.recall(agent, :last_response) == {:ok, "result"}
    end

    test "processes error message", %{agent: agent} do
      msg = Message.error("001", :timeout)
      agent = Agent.receive_message(agent, msg)

      {:processed, agent, _msg} = Agent.process_next(agent)

      assert Agent.recall(agent, :last_error) == :timeout
    end

    test "increments processed_count", %{agent: agent} do
      agent =
        agent
        |> Agent.receive_message(Message.task("001", :a))
        |> Agent.receive_message(Message.task("002", :b))

      {:processed, agent, _} = Agent.process_next(agent)
      assert agent.processed_count == 1

      {:processed, agent, _} = Agent.process_next(agent)
      assert agent.processed_count == 2
    end

    test "returns to idle state after processing", %{agent: agent} do
      agent = Agent.receive_message(agent, Message.task("001", :test))

      {:processed, agent, _} = Agent.process_next(agent)

      assert agent.state == :idle
    end
  end
end
