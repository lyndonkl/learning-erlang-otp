defmodule AgentFramework.Agent do
  @moduledoc """
  Core agent struct and operations.

  An agent has:
  - name: identifier
  - state: :idle | :busy | :waiting
  - inbox: list of pending messages
  - memory: map for storing context
  - processed_count: number of messages processed
  """

  alias AgentFramework.Message

  @enforce_keys [:name]
  defstruct [
    :name,
    state: :idle,
    inbox: [],
    memory: %{},
    processed_count: 0
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          state: :idle | :busy | :waiting,
          inbox: [Message.t()],
          memory: map(),
          processed_count: non_neg_integer()
        }

  # ============================================
  # Constructor
  # ============================================

  @doc """
  Create a new agent with the given name.

  ## Examples

      iex> agent = AgentFramework.Agent.new("Worker-1")
      iex> agent.name
      "Worker-1"
      iex> agent.state
      :idle
  """
  def new(name) when is_binary(name) do
    %__MODULE__{name: name}
  end

  # ============================================
  # State Transitions
  # ============================================

  @doc "Set agent state to idle"
  def set_idle(agent), do: %{agent | state: :idle}

  @doc "Set agent state to busy"
  def set_busy(agent), do: %{agent | state: :busy}

  @doc "Set agent state to waiting"
  def set_waiting(agent), do: %{agent | state: :waiting}

  @doc "Check if agent is idle"
  def idle?(%__MODULE__{state: :idle}), do: true
  def idle?(_), do: false

  @doc "Check if agent is busy"
  def busy?(%__MODULE__{state: :busy}), do: true
  def busy?(_), do: false

  # ============================================
  # Inbox Operations
  # ============================================

  @doc """
  Add a message to the agent's inbox.

  ## Examples

      iex> agent = AgentFramework.Agent.new("Worker")
      iex> msg = AgentFramework.Message.task("001", :search)
      iex> agent = AgentFramework.Agent.receive_message(agent, msg)
      iex> length(agent.inbox)
      1
  """
  def receive_message(%__MODULE__{inbox: inbox} = agent, %Message{} = msg) do
    %{agent | inbox: inbox ++ [msg]}
  end

  @doc "Get the next message without removing it"
  def peek_message(%__MODULE__{inbox: []}), do: nil
  def peek_message(%__MODULE__{inbox: [msg | _]}), do: msg

  @doc """
  Remove and return the next message.

  Returns {message, updated_agent} or {nil, agent} if inbox is empty.
  """
  def pop_message(%__MODULE__{inbox: []} = agent) do
    {nil, agent}
  end

  def pop_message(%__MODULE__{inbox: [msg | rest]} = agent) do
    {msg, %{agent | inbox: rest}}
  end

  @doc "Count pending messages in inbox"
  def inbox_count(%__MODULE__{inbox: inbox}), do: length(inbox)

  # ============================================
  # Memory Operations
  # ============================================

  @doc """
  Store a value in agent memory.

  ## Examples

      iex> agent = AgentFramework.Agent.new("Worker")
      iex> agent = AgentFramework.Agent.remember(agent, :context, "researching")
      iex> agent.memory[:context]
      "researching"
  """
  def remember(%__MODULE__{memory: mem} = agent, key, value) do
    %{agent | memory: Map.put(mem, key, value)}
  end

  @doc """
  Retrieve a value from agent memory.

  ## Examples

      iex> agent = AgentFramework.Agent.new("Worker")
      iex> agent = AgentFramework.Agent.remember(agent, :fact, "Elixir is great")
      iex> AgentFramework.Agent.recall(agent, :fact)
      "Elixir is great"
      iex> AgentFramework.Agent.recall(agent, :missing, "default")
      "default"
  """
  def recall(%__MODULE__{memory: mem}, key, default \\ nil) do
    Map.get(mem, key, default)
  end

  @doc "Clear all memory"
  def forget_all(%__MODULE__{} = agent) do
    %{agent | memory: %{}}
  end

  # ============================================
  # Message Processing
  # ============================================

  @doc """
  Process the next message in the inbox.

  Returns:
  - {:empty, agent} if inbox is empty
  - {:processed, agent, message} after processing

  ## Examples

      iex> agent = AgentFramework.Agent.new("Worker")
      iex> msg = AgentFramework.Message.task("001", :search)
      iex> agent = AgentFramework.Agent.receive_message(agent, msg)
      iex> {:processed, agent, _msg} = AgentFramework.Agent.process_next(agent)
      iex> agent.processed_count
      1
  """
  def process_next(%__MODULE__{inbox: []} = agent) do
    {:empty, agent}
  end

  def process_next(%__MODULE__{} = agent) do
    {msg, agent} = pop_message(agent)

    agent =
      agent
      |> set_busy()
      |> handle_message(msg)
      |> increment_processed()
      |> set_idle()

    {:processed, agent, msg}
  end

  # Pattern matching on message type
  defp handle_message(agent, %Message{type: :task, payload: %{action: action}}) do
    remember(agent, :last_action, action)
  end

  defp handle_message(agent, %Message{type: :response, payload: result}) do
    remember(agent, :last_response, result)
  end

  defp handle_message(agent, %Message{type: :error, payload: reason}) do
    remember(agent, :last_error, reason)
  end

  defp handle_message(agent, _msg), do: agent

  defp increment_processed(%__MODULE__{processed_count: n} = agent) do
    %{agent | processed_count: n + 1}
  end
end
