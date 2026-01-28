defmodule AgentFramework do
  @moduledoc """
  AgentFramework - A multi-agent framework in Elixir.

  ## Phase 1: Struct-based Agents

  For simple, synchronous agent manipulation:

      # Create an agent struct
      agent = AgentFramework.new_agent("Worker-1")

      # Create and send messages
      msg = AgentFramework.task("t-001", :search, %{query: "Elixir"})
      agent = AgentFramework.send_message(agent, msg)

      # Process messages
      {:processed, agent, _msg} = AgentFramework.process(agent)

  ## Phase 2: Process-based Agents

  For real concurrent agents with fault tolerance:

      # Start the registry (once at app startup)
      AgentFramework.start_registry()

      # Start a supervised agent monitor
      {:ok, monitor} = AgentFramework.start_monitor()

      # Start an agent process
      {:ok, pid} = AgentFramework.start_agent(monitor, "Worker-1")

      # Send tasks and process them
      AgentFramework.send_process_task(pid, :search, %{query: "OTP"})
      {:ok, task, result} = AgentFramework.process_next_task(pid)

      # Agents auto-restart on crash
      AgentFramework.list_monitored_agents(monitor)

  """

  alias AgentFramework.{Agent, Message, ProcessAgent, AgentRegistry, AgentMonitor}

  @doc """
  Create a new agent with the given name.

  ## Examples

      iex> agent = AgentFramework.new_agent("Worker")
      iex> agent.name
      "Worker"
  """
  def new_agent(name) do
    Agent.new(name)
  end

  @doc """
  Create a task message.

  ## Examples

      iex> msg = AgentFramework.task("001", :search, %{query: "test"})
      iex> msg.type
      :task
  """
  def task(id, action, params \\ %{}) do
    Message.task(id, action, params)
  end

  @doc """
  Create a response message.

  ## Examples

      iex> msg = AgentFramework.response("001", {:ok, "done"})
      iex> msg.type
      :response
  """
  def response(id, result) do
    Message.response(id, result)
  end

  @doc """
  Send a message to an agent.

  ## Examples

      iex> agent = AgentFramework.new_agent("Worker")
      iex> msg = AgentFramework.task("001", :search)
      iex> agent = AgentFramework.send_message(agent, msg)
      iex> length(agent.inbox)
      1
  """
  def send_message(agent, message) do
    Agent.receive_message(agent, message)
  end

  @doc """
  Process the next message in the agent's inbox.

  ## Examples

      iex> agent = AgentFramework.new_agent("Worker")
      iex> msg = AgentFramework.task("001", :search)
      iex> agent = AgentFramework.send_message(agent, msg)
      iex> {:processed, agent, _} = AgentFramework.process(agent)
      iex> agent.processed_count
      1
  """
  def process(agent) do
    Agent.process_next(agent)
  end

  @doc """
  Check if agent has pending messages.

  ## Examples

      iex> agent = AgentFramework.new_agent("Worker")
      iex> AgentFramework.has_messages?(agent)
      false
  """
  def has_messages?(agent) do
    Agent.inbox_count(agent) > 0
  end

  # ============================================
  # Phase 2: Process-based Agent API
  # ============================================

  @doc """
  Start the agent registry.

  Must be called before using named agents.
  Typically called once at application startup.

  ## Examples

      {:ok, _pid} = AgentFramework.start_registry()
  """
  def start_registry do
    AgentRegistry.start_link()
  end

  @doc """
  Start an agent monitor for fault-tolerant agents.

  ## Options
  - `:restart_policy` - `:always`, `:never`, or `:transient` (default: `:always`)
  - `:max_restarts` - Maximum restarts per agent (default: 5)

  ## Examples

      {:ok, monitor} = AgentFramework.start_monitor()
      {:ok, monitor} = AgentFramework.start_monitor(restart_policy: :transient)
  """
  def start_monitor(opts \\ []) do
    AgentMonitor.start_link(opts)
  end

  @doc """
  Start a monitored agent process.

  The agent will be automatically restarted if it crashes.

  ## Examples

      {:ok, monitor} = AgentFramework.start_monitor()
      {:ok, pid} = AgentFramework.start_agent(monitor, "Worker-1")
  """
  def start_agent(monitor, name, opts \\ []) do
    AgentMonitor.start_agent(monitor, name, opts)
  end

  @doc """
  Start an unmonitored agent process.

  Use this for agents that don't need automatic restart.

  ## Examples

      {:ok, pid} = AgentFramework.start_process_agent("Worker-1")
  """
  def start_process_agent(name, opts \\ []) do
    ProcessAgent.start(name, opts)
  end

  @doc """
  Stop an agent process.

  ## Examples

      AgentFramework.stop_agent(pid)
  """
  def stop_agent(pid) when is_pid(pid) do
    ProcessAgent.stop(pid)
  end

  @doc """
  Get the state of an agent process.

  ## Examples

      {:ok, state} = AgentFramework.get_agent_state(pid)
  """
  def get_agent_state(pid) do
    ProcessAgent.get_state(pid)
  end

  @doc """
  Send a task to an agent process.

  ## Examples

      AgentFramework.send_process_task(pid, :search, %{query: "OTP"})
  """
  def send_process_task(pid, action, params \\ %{}) do
    ProcessAgent.send_task(pid, action, params)
  end

  @doc """
  Process the next task in an agent's inbox.

  ## Examples

      {:ok, task, result} = AgentFramework.process_next_task(pid)
      {:empty, nil} = AgentFramework.process_next_task(pid)  # when inbox empty
  """
  def process_next_task(pid) do
    ProcessAgent.process_next(pid)
  end

  @doc """
  Store a value in an agent's memory.

  ## Examples

      AgentFramework.remember(pid, :context, "researching")
  """
  def remember(pid, key, value) do
    ProcessAgent.remember(pid, key, value)
  end

  @doc """
  Recall a value from an agent's memory.

  ## Examples

      {:ok, "researching"} = AgentFramework.recall(pid, :context)
  """
  def recall(pid, key) do
    ProcessAgent.recall(pid, key)
  end

  @doc """
  List all agents monitored by a monitor.

  ## Examples

      [{"Worker-1", pid1}, {"Worker-2", pid2}] = AgentFramework.list_monitored_agents(monitor)
  """
  def list_monitored_agents(monitor) do
    AgentMonitor.list_agents(monitor)
  end

  @doc """
  Look up an agent by name (requires registry to be started).

  ## Examples

      {:ok, pid} = AgentFramework.lookup_agent("Worker-1")
      :error = AgentFramework.lookup_agent("NonExistent")
  """
  def lookup_agent(name) do
    AgentRegistry.lookup(name)
  end

  # ============================================
  # Phase 3: OTP-based Agent API
  # ============================================

  alias AgentFramework.{AgentServer, AgentSupervisor}

  @doc """
  Start a supervised OTP agent.

  The agent will be automatically restarted if it crashes.
  The Application must be running (which happens automatically
  when using `iex -S mix` or `mix run`).

  ## Options
  - `:memory` - Initial memory map (default: %{})

  ## Examples

      {:ok, pid} = AgentFramework.start_otp_agent("Worker-1")
      {:ok, pid} = AgentFramework.start_otp_agent("Worker-2", memory: %{key: "val"})

  """
  def start_otp_agent(name, opts \\ []) do
    AgentSupervisor.start_agent(name, opts)
  end

  @doc """
  Stop a supervised OTP agent.

  ## Examples

      :ok = AgentFramework.stop_otp_agent(pid)

  """
  def stop_otp_agent(pid) when is_pid(pid) do
    AgentSupervisor.stop_agent(pid)
  end

  @doc """
  List all supervised OTP agents.

  ## Examples

      [pid1, pid2] = AgentFramework.list_otp_agents()

  """
  def list_otp_agents do
    AgentSupervisor.list_agents()
  end

  @doc """
  Count supervised OTP agents.

  ## Examples

      %{active: 3, ...} = AgentFramework.count_otp_agents()

  """
  def count_otp_agents do
    AgentSupervisor.count_agents()
  end

  # Delegated functions for AgentServer operations

  @doc """
  Get the state of an OTP agent.

  ## Examples

      state = AgentFramework.otp_get_state(agent)
      state.name
      # => "Worker-1"

  """
  defdelegate otp_get_state(server), to: AgentServer, as: :get_state

  @doc """
  Store a value in an OTP agent's memory.

  ## Examples

      :ok = AgentFramework.otp_remember(agent, :key, "value")

  """
  defdelegate otp_remember(server, key, value), to: AgentServer, as: :remember

  @doc """
  Recall a value from an OTP agent's memory.

  ## Examples

      "value" = AgentFramework.otp_recall(agent, :key)

  """
  defdelegate otp_recall(server, key), to: AgentServer, as: :recall

  @doc """
  Send a task to an OTP agent.

  ## Examples

      :ok = AgentFramework.otp_send_task(agent, :search, %{query: "OTP"})

  """
  defdelegate otp_send_task(server, action, params \\ %{}), to: AgentServer, as: :send_task

  @doc """
  Process the next task in an OTP agent's inbox.

  ## Examples

      {:ok, task, result} = AgentFramework.otp_process_next(agent)
      {:empty, nil} = AgentFramework.otp_process_next(agent)

  """
  defdelegate otp_process_next(server), to: AgentServer, as: :process_next

  @doc """
  Get the inbox count for an OTP agent.

  ## Examples

      3 = AgentFramework.otp_inbox_count(agent)

  """
  defdelegate otp_inbox_count(server), to: AgentServer, as: :inbox_count
end
