defmodule AgentApi.A2A.TaskManager do
  @moduledoc """
  Task management for A2A protocol.

  Bridges the gap between A2A JSON-RPC calls and AgentFramework's
  GenServer-based agents. Handles:

  - Agent discovery and lookup
  - Task dispatch to AgentServer
  - Task state tracking
  - Result retrieval

  ## Task State Machine

  A2A tasks follow this state machine:

      created → working → completed
                    ↘ failed
                    ↘ cancelled

  ## Example

      # Dispatch a task
      {:ok, result} = TaskManager.send_message("Worker-1", :search, %{query: "test"})

      # Get agent state
      {:ok, state} = TaskManager.get_agent_state("Worker-1")

  """

  alias AgentFramework.{AgentServer, AgentSupervisor}

  @type task_result :: %{
          status: :created | :working | :completed | :failed,
          agent: String.t(),
          task_id: String.t() | nil,
          result: any() | nil
        }

  @doc """
  Dispatch a SendMessage request to an agent.

  Creates a task and sends it to the specified agent.
  Returns immediately with task status (async processing).

  ## Parameters
  - `agent_name` - Name of the target agent
  - `action` - The action to perform (atom or string)
  - `params` - Parameters for the action

  ## Returns
  - `{:ok, task_result}` on success
  - `{:error, :agent_not_found}` if agent doesn't exist
  """
  @spec send_message(String.t(), atom() | String.t(), map()) ::
          {:ok, task_result()} | {:error, :agent_not_found}
  def send_message(agent_name, action, params) when is_binary(agent_name) do
    action = normalize_action(action)

    case find_agent(agent_name) do
      {:ok, pid} ->
        # Send task to the agent (async)
        :ok = AgentServer.send_task(pid, action, params)

        {:ok,
         %{
           status: :created,
           agent: agent_name,
           task_id: nil,
           result: nil
         }}

      :error ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Get the current state of an agent.

  Returns the agent's full state including inbox and memory.
  """
  @spec get_agent_state(String.t()) :: {:ok, map()} | {:error, :agent_not_found}
  def get_agent_state(agent_name) when is_binary(agent_name) do
    case find_agent(agent_name) do
      {:ok, pid} ->
        state = AgentServer.get_state(pid)
        {:ok, state}

      :error ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Process the next task for an agent and return the result.

  This is a synchronous operation - it processes one task and returns.
  """
  @spec process_next(String.t()) ::
          {:ok, task_result()} | {:error, :agent_not_found} | {:empty, nil}
  def process_next(agent_name) when is_binary(agent_name) do
    case find_agent(agent_name) do
      {:ok, pid} ->
        case AgentServer.process_next(pid) do
          {:ok, task, result} ->
            {:ok,
             %{
               status: :completed,
               agent: agent_name,
               task_id: task.id,
               result: serialize_result(result)
             }}

          {:empty, nil} ->
            {:empty, nil}
        end

      :error ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  List all available agents.

  Returns a list of agent PIDs with their names.
  """
  @spec list_agents() :: [{String.t(), pid()}]
  def list_agents do
    AgentSupervisor.list_agents()
    |> Enum.map(fn pid ->
      state = AgentServer.get_state(pid)
      {state.name, pid}
    end)
  end

  @doc """
  Start a new agent with the given name.

  Uses AgentSupervisor to create a supervised agent.
  """
  @spec start_agent(String.t(), keyword()) :: {:ok, pid()} | {:error, any()}
  def start_agent(name, opts \\ []) do
    AgentSupervisor.start_agent(name, opts)
  end

  @doc """
  Check if an agent exists by name.
  """
  @spec agent_exists?(String.t()) :: boolean()
  def agent_exists?(agent_name) when is_binary(agent_name) do
    case find_agent(agent_name) do
      {:ok, _pid} -> true
      :error -> false
    end
  end

  # ============================================
  # Private Functions
  # ============================================

  # Find an agent by name, searching through all supervised agents
  defp find_agent(agent_name) do
    # First try Registry lookup (if agent was registered)
    case AgentSupervisor.whereis(agent_name) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        # Fall back to searching all agents
        agents = AgentSupervisor.list_agents()

        result =
          Enum.find(agents, fn pid ->
            try do
              state = AgentServer.get_state(pid)
              state.name == agent_name
            catch
              :exit, _ -> false
            end
          end)

        case result do
          nil -> :error
          pid -> {:ok, pid}
        end
    end
  end

  # Normalize action to atom
  defp normalize_action(action) when is_atom(action), do: action
  defp normalize_action(action) when is_binary(action), do: String.to_atom(action)

  # Serialize result to JSON-encodable format
  defp serialize_result({:ok, value}) when is_binary(value), do: %{ok: value}
  defp serialize_result({:ok, value}) when is_map(value), do: %{ok: value}
  defp serialize_result({:ok, value}), do: %{ok: inspect(value)}
  defp serialize_result({:error, reason}), do: %{error: inspect(reason)}
  defp serialize_result({:received_response, value}), do: %{received_response: inspect(value)}
  defp serialize_result({:received_error, reason}), do: %{received_error: inspect(reason)}
  defp serialize_result(value) when is_binary(value), do: value
  defp serialize_result(value) when is_map(value), do: value
  defp serialize_result(value), do: inspect(value)
end
