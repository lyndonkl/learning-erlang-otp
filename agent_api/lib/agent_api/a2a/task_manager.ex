defmodule AgentApi.A2A.TaskManager do
  @moduledoc """
  Task management for A2A protocol.

  Bridges the gap between A2A JSON-RPC calls and AgentFramework's
  GenServer-based agents. Handles:

  - Agent discovery and lookup (local and cross-node via AgentRouter)
  - Task dispatch to AgentServer
  - Task state tracking
  - Result retrieval

  ## Task State Machine

  A2A tasks follow this state machine:

      created → working → completed
                    ↘ failed
                    ↘ cancelled

  ## Cross-Node Routing (Phase 5)

  Uses AgentRouter to find agents across the cluster:

      TaskManager.send_message("Worker-1", :search, %{})
        → AgentRouter.find_agent("Worker-1")
          → Check AgentDirectory (ETS)
          → Check local Registry
          → Query remote nodes via RPC

  ## Example

      # Dispatch a task
      {:ok, result} = TaskManager.send_message("Worker-1", :search, %{query: "test"})

      # Get agent state
      {:ok, state} = TaskManager.get_agent_state("Worker-1")

  """

  alias AgentFramework.{AgentServer, AgentSupervisor}
  alias AgentApi.Cluster.AgentRouter
  alias AgentApi.AgentEvents

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
  Uses AgentRouter for cross-node agent discovery.

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

    case AgentRouter.find_agent(agent_name) do
      {:ok, {node, pid}} ->
        # Send task to the agent (async), handling local vs remote
        if node == Node.self() do
          :ok = AgentServer.send_task(pid, action, params)
        else
          :rpc.call(node, AgentFramework.AgentServer, :send_task, [pid, action, params])
        end

        # Broadcast event
        AgentEvents.broadcast_task_received(agent_name, %{action: action, params: params})

        {:ok,
         %{
           status: :created,
           agent: agent_name,
           task_id: nil,
           result: nil,
           node: node
         }}

      :error ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Get the current state of an agent.

  Returns the agent's full state including inbox and memory.
  Uses AgentRouter for cross-node lookup.
  """
  @spec get_agent_state(String.t()) :: {:ok, map()} | {:error, :agent_not_found}
  def get_agent_state(agent_name) when is_binary(agent_name) do
    AgentRouter.get_agent_state(agent_name)
  end

  @doc """
  Process the next task for an agent and return the result.

  This is a synchronous operation - it processes one task and returns.
  Uses AgentRouter for cross-node routing.
  """
  @spec process_next(String.t()) ::
          {:ok, task_result()} | {:error, :agent_not_found} | {:empty, nil}
  def process_next(agent_name) when is_binary(agent_name) do
    case AgentRouter.process_next(agent_name) do
      {:ok, task, result} ->
        # Broadcast completion event
        AgentEvents.broadcast_task_completed(agent_name, %{task_id: task.id})

        {:ok,
         %{
           status: :completed,
           agent: agent_name,
           task_id: task.id,
           result: serialize_result(result)
         }}

      {:empty, nil} ->
        {:empty, nil}

      {:error, :agent_not_found} ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  List all available agents across the cluster.

  Returns a list of agent PIDs with their names and nodes.
  """
  @spec list_agents() :: [{String.t(), pid()}]
  def list_agents do
    AgentRouter.list_all_agents()
    |> Enum.map(fn {name, _node, pid} -> {name, pid} end)
  end

  @doc """
  List all agents with full cluster information.

  Returns a list of `{name, node, pid}` tuples.
  """
  @spec list_agents_with_nodes() :: [{String.t(), node(), pid()}]
  def list_agents_with_nodes do
    AgentRouter.list_all_agents()
  end

  @doc """
  Start a new agent with the given name.

  Uses AgentSupervisor to create a supervised agent on the local node.
  Registers the agent in the AgentDirectory for cross-node discovery.
  """
  @spec start_agent(String.t(), keyword()) :: {:ok, pid()} | {:error, any()}
  def start_agent(name, opts \\ []) do
    case AgentSupervisor.start_agent(name, opts) do
      {:ok, pid} ->
        # Register in directory for cross-node discovery
        AgentRouter.register_agent(name, pid)
        # Broadcast agent started event
        AgentEvents.broadcast_agent_started(name)
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Check if an agent exists by name (searches across cluster).
  """
  @spec agent_exists?(String.t()) :: boolean()
  def agent_exists?(agent_name) when is_binary(agent_name) do
    case AgentRouter.find_agent(agent_name) do
      {:ok, _} -> true
      :error -> false
    end
  end

  # ============================================
  # Private Functions
  # ============================================

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
