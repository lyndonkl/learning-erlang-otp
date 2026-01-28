defmodule AgentFrameworkTest do
  use ExUnit.Case
  doctest AgentFramework
  doctest AgentFramework.Agent
  doctest AgentFramework.Message

  describe "public API" do
    test "new_agent/1 creates an agent" do
      agent = AgentFramework.new_agent("Worker")
      assert agent.name == "Worker"
    end

    test "task/3 creates a task message" do
      msg = AgentFramework.task("001", :search, %{query: "test"})
      assert msg.type == :task
      assert msg.payload.action == :search
    end

    test "response/2 creates a response message" do
      msg = AgentFramework.response("001", {:ok, "done"})
      assert msg.type == :response
    end

    test "send_message/2 adds message to agent inbox" do
      agent = AgentFramework.new_agent("Worker")
      msg = AgentFramework.task("001", :search)
      agent = AgentFramework.send_message(agent, msg)

      assert length(agent.inbox) == 1
    end

    test "process/1 processes next message" do
      agent = AgentFramework.new_agent("Worker")
      msg = AgentFramework.task("001", :search)
      agent = AgentFramework.send_message(agent, msg)

      {:processed, agent, _msg} = AgentFramework.process(agent)

      assert agent.processed_count == 1
      assert agent.inbox == []
    end

    test "has_messages?/1 returns false for empty inbox" do
      agent = AgentFramework.new_agent("Worker")
      refute AgentFramework.has_messages?(agent)
    end

    test "has_messages?/1 returns true when inbox has messages" do
      agent = AgentFramework.new_agent("Worker")
      msg = AgentFramework.task("001", :search)
      agent = AgentFramework.send_message(agent, msg)

      assert AgentFramework.has_messages?(agent)
    end
  end

  describe "integration" do
    test "full workflow: create agent, send messages, process all" do
      # Create agent
      agent = AgentFramework.new_agent("Integration-Worker")

      # Send multiple messages
      agent =
        agent
        |> AgentFramework.send_message(AgentFramework.task("t-001", :search, %{query: "Elixir"}))
        |> AgentFramework.send_message(AgentFramework.task("t-002", :analyze, %{data: [1, 2, 3]}))
        |> AgentFramework.send_message(AgentFramework.task("t-003", :summarize))

      assert AgentFramework.has_messages?(agent)
      assert length(agent.inbox) == 3

      # Process all messages
      {:processed, agent, msg1} = AgentFramework.process(agent)
      assert msg1.id == "t-001"

      {:processed, agent, msg2} = AgentFramework.process(agent)
      assert msg2.id == "t-002"

      {:processed, agent, msg3} = AgentFramework.process(agent)
      assert msg3.id == "t-003"

      # Verify final state
      refute AgentFramework.has_messages?(agent)
      assert agent.processed_count == 3
      assert agent.state == :idle
    end
  end
end
