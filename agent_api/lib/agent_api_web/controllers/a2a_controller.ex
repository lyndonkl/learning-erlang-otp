defmodule AgentApiWeb.A2AController do
  @moduledoc """
  Controller for A2A JSON-RPC endpoint.

  Handles all A2A protocol methods via JSON-RPC 2.0:

  - `SendMessage` - Send a task to an agent
  - `GetTask` - Get task status/result
  - `GetAgentState` - Get agent's full state
  - `ListAgents` - List all available agents
  - `StartAgent` - Start a new agent
  - `ProcessNext` - Process next task (for testing)

  ## JSON-RPC Format

  Request:
      POST /a2a
      Content-Type: application/json

      {
        "jsonrpc": "2.0",
        "method": "SendMessage",
        "params": {
          "agent": "Worker-1",
          "action": "search",
          "params": {"query": "OTP"}
        },
        "id": 1
      }

  Response:
      {
        "jsonrpc": "2.0",
        "result": {"status": "created", "agent": "Worker-1"},
        "id": 1
      }

  ## Comparison with GenServer

      GenServer:  handle_call({:send_task, action, params}, from, state)
      Controller: dispatch("SendMessage", params)

  Both pattern match on the request type and delegate to appropriate handlers.
  """
  use AgentApiWeb, :controller

  alias AgentApi.A2A.{JsonRpc, TaskManager}

  @doc """
  Handle JSON-RPC requests.

  Parses the incoming JSON-RPC request, dispatches to the appropriate
  method handler, and returns a JSON-RPC response.
  """
  def handle(conn, params) do
    case JsonRpc.parse(params) do
      {:ok, request} ->
        response = dispatch(request)
        json(conn, response)

      {:error, error_response} ->
        json(conn, error_response)
    end
  end

  # ============================================
  # Method Dispatch
  # ============================================

  defp dispatch(%{method: method, params: params, id: id}) do
    case method do
      "SendMessage" -> handle_send_message(params, id)
      "GetAgentState" -> handle_get_agent_state(params, id)
      "ListAgents" -> handle_list_agents(id)
      "StartAgent" -> handle_start_agent(params, id)
      "ProcessNext" -> handle_process_next(params, id)
      _ -> JsonRpc.method_not_found(method, id)
    end
  end

  # ============================================
  # Method Handlers
  # ============================================

  # SendMessage - Send a task to an agent
  # Params: {agent: string, action: string, params: object}
  defp handle_send_message(%{"agent" => agent, "action" => action} = params, id) do
    task_params = Map.get(params, "params", %{})

    case TaskManager.send_message(agent, action, task_params) do
      {:ok, result} ->
        JsonRpc.success(result, id)

      {:error, :agent_not_found} ->
        JsonRpc.agent_not_found(agent, id)
    end
  end

  defp handle_send_message(_params, id) do
    JsonRpc.invalid_params("Missing required: agent, action", id)
  end

  # GetAgentState - Get an agent's full state
  # Params: {agent: string}
  defp handle_get_agent_state(%{"agent" => agent}, id) do
    case TaskManager.get_agent_state(agent) do
      {:ok, state} ->
        # Convert to JSON-friendly format
        json_state = %{
          name: state.name,
          status: state.status,
          inbox_count: length(state.inbox),
          processed_count: state.processed_count,
          memory_keys: Map.keys(state.memory)
        }

        JsonRpc.success(json_state, id)

      {:error, :agent_not_found} ->
        JsonRpc.agent_not_found(agent, id)
    end
  end

  defp handle_get_agent_state(_params, id) do
    JsonRpc.invalid_params("Missing required: agent", id)
  end

  # ListAgents - List all available agents
  # Params: none
  defp handle_list_agents(id) do
    agents =
      TaskManager.list_agents()
      |> Enum.map(fn {name, _pid} -> name end)

    JsonRpc.success(%{agents: agents, count: length(agents)}, id)
  end

  # StartAgent - Start a new agent
  # Params: {name: string, memory?: object}
  defp handle_start_agent(%{"name" => name} = params, id) do
    opts =
      case Map.get(params, "memory") do
        nil -> []
        memory when is_map(memory) -> [memory: memory]
      end

    case TaskManager.start_agent(name, opts) do
      {:ok, _pid} ->
        JsonRpc.success(%{status: "started", agent: name}, id)

      {:error, {:already_started, _}} ->
        JsonRpc.success(%{status: "already_exists", agent: name}, id)

      {:error, reason} ->
        JsonRpc.internal_error(inspect(reason), id)
    end
  end

  defp handle_start_agent(_params, id) do
    JsonRpc.invalid_params("Missing required: name", id)
  end

  # ProcessNext - Process the next task (useful for testing)
  # Params: {agent: string}
  defp handle_process_next(%{"agent" => agent}, id) do
    case TaskManager.process_next(agent) do
      {:ok, result} ->
        JsonRpc.success(result, id)

      {:empty, nil} ->
        JsonRpc.success(%{status: "empty", message: "No tasks in inbox"}, id)

      {:error, :agent_not_found} ->
        JsonRpc.agent_not_found(agent, id)
    end
  end

  defp handle_process_next(_params, id) do
    JsonRpc.invalid_params("Missing required: agent", id)
  end
end
