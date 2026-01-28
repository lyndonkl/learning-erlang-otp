defmodule AgentFramework.MessageTest do
  use ExUnit.Case
  alias AgentFramework.Message

  describe "new/3" do
    test "creates message with required fields" do
      msg = Message.new(:task, "001", %{data: "test"})

      assert msg.type == :task
      assert msg.id == "001"
      assert msg.payload == %{data: "test"}
      assert %DateTime{} = msg.timestamp
    end

    test "payload defaults to nil" do
      msg = Message.new(:task, "001")
      assert msg.payload == nil
    end
  end

  describe "task/3" do
    test "creates task message with action and params" do
      msg = Message.task("001", :search, %{query: "Elixir"})

      assert msg.type == :task
      assert msg.id == "001"
      assert msg.payload == %{action: :search, params: %{query: "Elixir"}}
    end

    test "params default to empty map" do
      msg = Message.task("001", :analyze)

      assert msg.payload == %{action: :analyze, params: %{}}
    end
  end

  describe "response/2" do
    test "creates response message" do
      msg = Message.response("001", {:ok, "completed"})

      assert msg.type == :response
      assert msg.id == "001"
      assert msg.payload == {:ok, "completed"}
    end
  end

  describe "error/2" do
    test "creates error message" do
      msg = Message.error("001", :timeout)

      assert msg.type == :error
      assert msg.id == "001"
      assert msg.payload == :timeout
    end
  end
end
