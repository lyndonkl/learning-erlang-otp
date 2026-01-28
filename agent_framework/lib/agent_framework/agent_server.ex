defmodule AgentFramework.AgentServer do
  @moduledoc """
  GenServer-based agent that processes tasks and maintains memory.

  This is the OTP version of Phase 2's ProcessAgent. It provides the same
  functionality but with proper OTP patterns:
  - Supervised by DynamicSupervisor
  - Automatic restart on crash
  - Built-in debugging support
  - Hot code upgrade capability

  ## Example

      # Start an agent (usually via AgentSupervisor)
      {:ok, agent} = AgentServer.start_link("Worker-1")

      # Store memory
      AgentServer.remember(agent, :context, "researching")
      "researching" = AgentServer.recall(agent, :context)

      # Send and process tasks
      AgentServer.send_task(agent, :search, %{query: "OTP"})
      {:ok, task, result} = AgentServer.process_next(agent)

  """
  use GenServer

  alias AgentFramework.Message

  # ============================================
  # Type Definitions
  # ============================================

  @type state :: %{
          name: String.t(),
          status: :idle | :busy | :waiting,
          memory: map(),
          inbox: [Message.t()],
          processed_count: non_neg_integer()
        }

  # ============================================
  # Client API
  # ============================================

  @doc """
  Start a linked AgentServer process.

  ## Options
  - `:memory` - Initial memory map (default: %{})
  - `:name` - Process registration name (optional)

  ## Examples

      {:ok, pid} = AgentServer.start_link("Worker-1")
      {:ok, pid} = AgentServer.start_link("Worker-2", memory: %{key: "value"})

  """
  @spec start_link(String.t(), keyword()) :: GenServer.on_start()
  def start_link(name, opts \\ []) when is_binary(name) do
    initial_memory = Keyword.get(opts, :memory, %{})
    gen_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, {name, initial_memory}, gen_opts)
  end

  @doc """
  Returns a child specification for starting under a supervisor.

  This is called automatically when you use `{AgentServer, name}` in a
  child specification.
  """
  def child_spec(arg) when is_binary(arg) do
    child_spec({arg, []})
  end

  def child_spec({name, opts}) when is_binary(name) and is_list(opts) do
    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [name, opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Get the agent's full state.

  ## Examples

      state = AgentServer.get_state(agent)
      state.name
      # => "Worker-1"

  """
  @spec get_state(GenServer.server()) :: state()
  def get_state(server) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Get the agent's current status.

  ## Examples

      :idle = AgentServer.get_status(agent)

  """
  @spec get_status(GenServer.server()) :: :idle | :busy | :waiting
  def get_status(server) do
    GenServer.call(server, :get_status)
  end

  @doc """
  Store a value in the agent's memory (async).

  This is a cast operation - it returns immediately without waiting
  for confirmation.

  ## Examples

      :ok = AgentServer.remember(agent, :context, "researching")

  """
  @spec remember(GenServer.server(), any(), any()) :: :ok
  def remember(server, key, value) do
    GenServer.cast(server, {:remember, key, value})
  end

  @doc """
  Recall a value from the agent's memory (sync).

  Returns the value or nil if not found.

  ## Examples

      "researching" = AgentServer.recall(agent, :context)
      nil = AgentServer.recall(agent, :missing)

  """
  @spec recall(GenServer.server(), any()) :: any()
  def recall(server, key) do
    GenServer.call(server, {:recall, key})
  end

  @doc """
  Clear all memory from the agent (async).

  ## Examples

      :ok = AgentServer.forget_all(agent)

  """
  @spec forget_all(GenServer.server()) :: :ok
  def forget_all(server) do
    GenServer.cast(server, :forget_all)
  end

  @doc """
  Send a task to the agent's inbox (async).

  Uses the Message struct for consistency with Phase 1.

  ## Examples

      :ok = AgentServer.send_task(agent, :search, %{query: "OTP"})

  """
  @spec send_task(GenServer.server(), atom(), map()) :: :ok
  def send_task(server, action, params \\ %{}) do
    GenServer.cast(server, {:send_task, action, params})
  end

  @doc """
  Send a raw message to the agent's inbox (async).

  ## Examples

      msg = Message.task("t-001", :search, %{query: "test"})
      :ok = AgentServer.send_message(agent, msg)

  """
  @spec send_message(GenServer.server(), Message.t()) :: :ok
  def send_message(server, %Message{} = message) do
    GenServer.cast(server, {:receive_message, message})
  end

  @doc """
  Process the next task in the inbox (sync).

  Returns the processed task and result.

  ## Examples

      {:ok, task, result} = AgentServer.process_next(agent)
      {:empty, nil} = AgentServer.process_next(agent)  # when inbox empty

  """
  @spec process_next(GenServer.server()) ::
          {:ok, Message.t(), any()} | {:empty, nil}
  def process_next(server) do
    GenServer.call(server, :process_next)
  end

  @doc """
  Get the count of tasks in the inbox (sync).

  ## Examples

      3 = AgentServer.inbox_count(agent)

  """
  @spec inbox_count(GenServer.server()) :: non_neg_integer()
  def inbox_count(server) do
    GenServer.call(server, :inbox_count)
  end

  @doc """
  Stop the agent gracefully.

  ## Examples

      :ok = AgentServer.stop(agent)

  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init({name, initial_memory}) do
    state = %{
      name: name,
      status: :idle,
      memory: initial_memory,
      inbox: [],
      processed_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call({:recall, key}, _from, state) do
    value = Map.get(state.memory, key)
    {:reply, value, state}
  end

  def handle_call(:inbox_count, _from, state) do
    {:reply, length(state.inbox), state}
  end

  def handle_call(:process_next, _from, state) do
    case state.inbox do
      [] ->
        {:reply, {:empty, nil}, state}

      [task | rest] ->
        # Mark as busy while processing
        state = %{state | status: :busy}
        result = handle_task(task)

        new_state = %{
          state
          | status: :idle,
            inbox: rest,
            processed_count: state.processed_count + 1,
            memory: Map.put(state.memory, :last_result, result)
        }

        {:reply, {:ok, task, result}, new_state}
    end
  end

  @impl true
  def handle_cast({:remember, key, value}, state) do
    new_memory = Map.put(state.memory, key, value)
    {:noreply, %{state | memory: new_memory}}
  end

  def handle_cast(:forget_all, state) do
    {:noreply, %{state | memory: %{}}}
  end

  def handle_cast({:send_task, action, params}, state) do
    task_id = generate_id()
    message = Message.task(task_id, action, params)
    {:noreply, %{state | inbox: state.inbox ++ [message]}}
  end

  def handle_cast({:receive_message, %Message{} = message}, state) do
    {:noreply, %{state | inbox: state.inbox ++ [message]}}
  end

  @impl true
  def handle_info(msg, state) do
    # Log unexpected messages but don't crash
    IO.puts("[AgentServer #{state.name}] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("[AgentServer #{state.name}] Terminating: #{inspect(reason)}")
    :ok
  end

  # ============================================
  # Private Functions - Task Handlers
  # ============================================

  defp handle_task(%Message{type: :task, payload: %{action: :search, params: params}}) do
    query = Map.get(params, :query, "")
    {:ok, "Search results for: #{query}"}
  end

  defp handle_task(%Message{type: :task, payload: %{action: :analyze, params: params}}) do
    data = Map.get(params, :data, "")
    {:ok, "Analysis of: #{data}"}
  end

  defp handle_task(%Message{type: :task, payload: %{action: :summarize, params: params}}) do
    text = Map.get(params, :text, "")
    {:ok, "Summary: #{String.slice(text, 0, 50)}..."}
  end

  defp handle_task(%Message{type: :task, payload: %{action: action}}) do
    {:error, {:unknown_action, action}}
  end

  defp handle_task(%Message{type: :response, payload: result}) do
    {:received_response, result}
  end

  defp handle_task(%Message{type: :error, payload: reason}) do
    {:received_error, reason}
  end

  defp handle_task(message) do
    {:error, {:invalid_message, message}}
  end

  # ============================================
  # Helpers
  # ============================================

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
