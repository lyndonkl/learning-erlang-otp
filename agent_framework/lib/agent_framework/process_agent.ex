defmodule AgentFramework.ProcessAgent do
  @moduledoc """
  A real process-based agent implementation.

  This module spawns agents as actual Elixir processes that:
  - Maintain their own state
  - Communicate via message passing
  - Can be monitored and supervised

  This builds on the Phase 1 Agent struct, but as living processes.

  ## Example

      # Start an agent process
      {:ok, pid} = ProcessAgent.start("Worker-1")

      # Send a task
      ProcessAgent.send_task(pid, :search, %{query: "OTP"})

      # Get state
      {:ok, state} = ProcessAgent.get_state(pid)

      # Stop the agent
      ProcessAgent.stop(pid)

  """

  alias AgentFramework.Message

  @type state :: %{
          name: String.t(),
          status: :idle | :busy | :waiting,
          memory: map(),
          inbox: list(),
          processed_count: non_neg_integer()
        }

  # ============================================
  # Public API
  # ============================================

  @doc """
  Start a new agent process.

  Returns `{:ok, pid}` on success.

  ## Options
  - `:name` - Agent name (required)
  - `:memory` - Initial memory map (default: %{})
  - `:register` - Whether to register with AgentRegistry (default: false)

  ## Examples

      {:ok, pid} = ProcessAgent.start("Worker-1")
      {:ok, pid} = ProcessAgent.start("Worker-2", memory: %{context: "research"})
  """
  @spec start(String.t(), keyword()) :: {:ok, pid()}
  def start(name, opts \\ []) when is_binary(name) do
    initial_memory = Keyword.get(opts, :memory, %{})
    register? = Keyword.get(opts, :register, false)

    pid = spawn(fn ->
      initial_state = %{
        name: name,
        status: :idle,
        memory: initial_memory,
        inbox: [],
        processed_count: 0
      }

      if register? do
        AgentFramework.AgentRegistry.register(name)
      end

      loop(initial_state)
    end)

    {:ok, pid}
  end

  @doc """
  Start a linked agent process.

  Like `start/2` but links the agent to the calling process.
  If the agent crashes, the caller receives an exit signal.

  ## Examples

      {:ok, pid} = ProcessAgent.start_link("Worker-1")
  """
  @spec start_link(String.t(), keyword()) :: {:ok, pid()}
  def start_link(name, opts \\ []) when is_binary(name) do
    initial_memory = Keyword.get(opts, :memory, %{})
    register? = Keyword.get(opts, :register, false)

    pid = spawn_link(fn ->
      initial_state = %{
        name: name,
        status: :idle,
        memory: initial_memory,
        inbox: [],
        processed_count: 0
      }

      if register? do
        AgentFramework.AgentRegistry.register(name)
      end

      loop(initial_state)
    end)

    {:ok, pid}
  end

  @doc """
  Stop an agent process gracefully.

  ## Examples

      ProcessAgent.stop(pid)
  """
  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    send(pid, :stop)
    :ok
  end

  @doc """
  Get the current state of an agent.

  ## Examples

      {:ok, state} = ProcessAgent.get_state(pid)
      state.name
      # => "Worker-1"
  """
  @spec get_state(pid(), timeout()) :: {:ok, state()} | {:error, :timeout}
  def get_state(pid, timeout \\ 5000) when is_pid(pid) do
    send(pid, {:get_state, self()})

    receive do
      {:state, state} -> {:ok, state}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Get the agent's current status.

  ## Examples

      {:ok, :idle} = ProcessAgent.get_status(pid)
  """
  @spec get_status(pid(), timeout()) :: {:ok, atom()} | {:error, :timeout}
  def get_status(pid, timeout \\ 5000) when is_pid(pid) do
    send(pid, {:get_status, self()})

    receive do
      {:status, status} -> {:ok, status}
    after
      timeout -> {:error, :timeout}
    end
  end

  # ============================================
  # Memory Operations
  # ============================================

  @doc """
  Store a value in the agent's memory.

  ## Examples

      ProcessAgent.remember(pid, :context, "researching")
  """
  @spec remember(pid(), any(), any()) :: :ok
  def remember(pid, key, value) when is_pid(pid) do
    send(pid, {:remember, key, value})
    :ok
  end

  @doc """
  Retrieve a value from the agent's memory.

  ## Examples

      {:ok, "researching"} = ProcessAgent.recall(pid, :context)
      {:ok, nil} = ProcessAgent.recall(pid, :missing)
  """
  @spec recall(pid(), any(), timeout()) :: {:ok, any()} | {:error, :timeout}
  def recall(pid, key, timeout \\ 5000) when is_pid(pid) do
    send(pid, {:recall, key, self()})

    receive do
      {:recalled, ^key, value} -> {:ok, value}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Clear all memory from the agent.

  ## Examples

      ProcessAgent.forget_all(pid)
  """
  @spec forget_all(pid()) :: :ok
  def forget_all(pid) when is_pid(pid) do
    send(pid, :forget_all)
    :ok
  end

  # ============================================
  # Task Operations
  # ============================================

  @doc """
  Send a task to the agent's inbox.

  Uses the Message struct from Phase 1 for consistency.

  ## Examples

      ProcessAgent.send_task(pid, :search, %{query: "OTP"})
  """
  @spec send_task(pid(), atom(), map()) :: :ok
  def send_task(pid, action, params \\ %{}) when is_pid(pid) do
    message = Message.task(generate_id(), action, params)
    send(pid, {:receive_task, message})
    :ok
  end

  @doc """
  Send a raw message to the agent's inbox.

  ## Examples

      msg = Message.task("t-001", :search, %{query: "test"})
      ProcessAgent.send_message(pid, msg)
  """
  @spec send_message(pid(), Message.t()) :: :ok
  def send_message(pid, %Message{} = message) when is_pid(pid) do
    send(pid, {:receive_task, message})
    :ok
  end

  @doc """
  Process the next task in the inbox.

  Returns the processed task and result.

  ## Examples

      {:ok, task, result} = ProcessAgent.process_next(pid)
      {:empty, nil} = ProcessAgent.process_next(pid)  # when inbox empty
  """
  @spec process_next(pid(), timeout()) ::
          {:ok, Message.t(), any()} | {:empty, nil} | {:error, :timeout}
  def process_next(pid, timeout \\ 5000) when is_pid(pid) do
    send(pid, {:process_next, self()})

    receive do
      {:processed, task, result} -> {:ok, task, result}
      {:empty, nil} -> {:empty, nil}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Get the count of tasks in the inbox.

  ## Examples

      {:ok, 3} = ProcessAgent.inbox_count(pid)
  """
  @spec inbox_count(pid(), timeout()) :: {:ok, non_neg_integer()} | {:error, :timeout}
  def inbox_count(pid, timeout \\ 5000) when is_pid(pid) do
    send(pid, {:inbox_count, self()})

    receive do
      {:count, n} -> {:ok, n}
    after
      timeout -> {:error, :timeout}
    end
  end

  # ============================================
  # Process Loop (Private)
  # ============================================

  defp loop(state) do
    receive do
      # --- State Queries ---
      {:get_state, from} ->
        send(from, {:state, state})
        loop(state)

      {:get_status, from} ->
        send(from, {:status, state.status})
        loop(state)

      # --- Memory Operations ---
      {:remember, key, value} ->
        new_memory = Map.put(state.memory, key, value)
        loop(%{state | memory: new_memory})

      {:recall, key, from} ->
        value = Map.get(state.memory, key)
        send(from, {:recalled, key, value})
        loop(state)

      :forget_all ->
        loop(%{state | memory: %{}})

      # --- Inbox Operations ---
      {:receive_task, %Message{} = message} ->
        new_inbox = state.inbox ++ [message]
        loop(%{state | inbox: new_inbox})

      {:inbox_count, from} ->
        send(from, {:count, length(state.inbox)})
        loop(state)

      {:peek_task, from} ->
        task = List.first(state.inbox)
        send(from, {:next_task, task})
        loop(state)

      # --- Task Processing ---
      {:process_next, from} ->
        case state.inbox do
          [] ->
            send(from, {:empty, nil})
            loop(state)

          [task | rest] ->
            state = %{state | status: :busy}
            result = handle_task(state, task)

            state = %{state |
              status: :idle,
              inbox: rest,
              processed_count: state.processed_count + 1
            }

            # Store result in memory
            state = %{state | memory: Map.put(state.memory, :last_result, result)}

            send(from, {:processed, task, result})
            loop(state)
        end

      # --- Inter-Agent Communication ---
      {:delegate, target_name, action, params, from} ->
        case AgentFramework.AgentRegistry.lookup(target_name) do
          {:ok, target_pid} ->
            message = Message.task(generate_id(), action, params)
            send(target_pid, {:receive_task, message})
            send(from, {:delegated, target_name, message.id})

          :error ->
            send(from, {:error, {:agent_not_found, target_name}})
        end

        loop(state)

      # --- Control ---
      :stop ->
        :ok

      {:crash, reason} ->
        exit(reason)

      # --- Catch-all ---
      _other ->
        loop(state)
    after
      60000 ->
        # Idle timeout - just continue
        loop(state)
    end
  end

  # ============================================
  # Task Handlers (Private)
  # ============================================

  defp handle_task(_state, %Message{type: :task, payload: %{action: :search, params: params}}) do
    query = Map.get(params, :query, "")
    {:ok, "Search results for: #{query}"}
  end

  defp handle_task(_state, %Message{type: :task, payload: %{action: :analyze, params: params}}) do
    data = Map.get(params, :data, "")
    {:ok, "Analysis of: #{data}"}
  end

  defp handle_task(_state, %Message{type: :task, payload: %{action: :summarize, params: params}}) do
    text = Map.get(params, :text, "")
    {:ok, "Summary: #{String.slice(text, 0, 50)}..."}
  end

  defp handle_task(_state, %Message{type: :task, payload: %{action: action}}) do
    {:error, {:unknown_action, action}}
  end

  defp handle_task(_state, %Message{type: :response, payload: result}) do
    {:received_response, result}
  end

  defp handle_task(_state, %Message{type: :error, payload: reason}) do
    {:received_error, reason}
  end

  defp handle_task(_state, message) do
    {:error, {:invalid_message, message}}
  end

  # ============================================
  # Helpers
  # ============================================

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
