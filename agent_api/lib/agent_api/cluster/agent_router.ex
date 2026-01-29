defmodule AgentApi.Cluster.AgentRouter do
  @moduledoc """
  Cross-node agent discovery and routing.

  Provides a unified API for finding and communicating with agents
  regardless of which node they are on. Uses AgentDirectory for
  fast lookups and falls back to querying remote nodes.

  ## Lookup Strategy

  1. Check local AgentDirectory (ETS - fast)
  2. Check local AgentSupervisor (Registry - fast)
  3. Query remote nodes via `:rpc.call/4` (slower, network)

  ## Example

      # Find an agent anywhere in the cluster
      {:ok, {node, pid}} = AgentRouter.find_agent("Worker-1")

      # Call an agent on any node
      {:ok, state} = AgentRouter.get_agent_state("Worker-1")

      # Send a task to an agent on any node
      :ok = AgentRouter.send_task("Worker-1", :search, %{query: "OTP"})

      # List agents across all nodes
      agents = AgentRouter.list_all_agents()

  """

  require Logger

  alias AgentFramework.{AgentDirectory, AgentServer, AgentSupervisor}

  # ============================================
  # Agent Discovery
  # ============================================

  @doc """
  Find an agent by name across the cluster.

  Returns `{:ok, {node, pid}}` if found, `:error` if not found
  on any node.

  ## Lookup Order
  1. AgentDirectory (ETS, cross-node cache)
  2. Local AgentSupervisor Registry
  3. Remote nodes via RPC

  ## Examples

      {:ok, {:node1@host, pid}} = AgentRouter.find_agent("Worker-1")
      :error = AgentRouter.find_agent("NonExistent")

  """
  @spec find_agent(String.t()) :: {:ok, {node(), pid()}} | :error
  def find_agent(agent_name) when is_binary(agent_name) do
    # Step 1: Check AgentDirectory (fast ETS lookup)
    case AgentDirectory.lookup(agent_name) do
      {:ok, {node, pid}} ->
        if Process.alive?(pid) or node != Node.self() do
          {:ok, {node, pid}}
        else
          # Stale entry - remove and continue search
          AgentDirectory.unregister(agent_name)
          find_agent_local_or_remote(agent_name)
        end

      :error ->
        find_agent_local_or_remote(agent_name)
    end
  end

  @doc """
  Get the state of an agent on any node.

  ## Examples

      {:ok, state} = AgentRouter.get_agent_state("Worker-1")
      {:error, :agent_not_found} = AgentRouter.get_agent_state("NonExistent")

  """
  @spec get_agent_state(String.t()) :: {:ok, map()} | {:error, :agent_not_found}
  def get_agent_state(agent_name) when is_binary(agent_name) do
    case find_agent(agent_name) do
      {:ok, {node, pid}} ->
        if node == Node.self() do
          {:ok, AgentServer.get_state(pid)}
        else
          case :rpc.call(node, AgentFramework.AgentServer, :get_state, [pid]) do
            {:badrpc, _reason} -> {:error, :agent_not_found}
            state -> {:ok, state}
          end
        end

      :error ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Send a task to an agent on any node.

  ## Examples

      :ok = AgentRouter.send_task("Worker-1", :search, %{query: "OTP"})
      {:error, :agent_not_found} = AgentRouter.send_task("NonExistent", :search, %{})

  """
  @spec send_task(String.t(), atom(), map()) :: :ok | {:error, :agent_not_found}
  def send_task(agent_name, action, params) when is_binary(agent_name) do
    case find_agent(agent_name) do
      {:ok, {node, pid}} ->
        if node == Node.self() do
          AgentServer.send_task(pid, action, params)
        else
          case :rpc.call(node, AgentFramework.AgentServer, :send_task, [pid, action, params]) do
            {:badrpc, _reason} -> {:error, :agent_not_found}
            result -> result
          end
        end

      :error ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Process the next task for an agent on any node.

  ## Examples

      {:ok, task, result} = AgentRouter.process_next("Worker-1")

  """
  @spec process_next(String.t()) :: {:ok, any(), any()} | {:empty, nil} | {:error, :agent_not_found}
  def process_next(agent_name) when is_binary(agent_name) do
    case find_agent(agent_name) do
      {:ok, {node, pid}} ->
        if node == Node.self() do
          AgentServer.process_next(pid)
        else
          case :rpc.call(node, AgentFramework.AgentServer, :process_next, [pid]) do
            {:badrpc, _reason} -> {:error, :agent_not_found}
            result -> result
          end
        end

      :error ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  List all agents across the entire cluster.

  Returns a list of `{name, node, pid}` tuples.

  ## Examples

      agents = AgentRouter.list_all_agents()
      # => [{"Worker-1", :node1@host, #PID<0.123.0>}, ...]

  """
  @spec list_all_agents() :: [{String.t(), node(), pid()}]
  def list_all_agents do
    # Local agents
    local_agents = list_local_agents()

    # Remote agents
    remote_agents =
      Node.list()
      |> Enum.flat_map(fn node ->
        case :rpc.call(node, __MODULE__, :list_local_agents, []) do
          {:badrpc, _reason} -> []
          agents -> agents
        end
      end)

    local_agents ++ remote_agents
  end

  @doc """
  List agents on the local node.

  Returns a list of `{name, node, pid}` tuples.
  """
  @spec list_local_agents() :: [{String.t(), node(), pid()}]
  def list_local_agents do
    AgentSupervisor.list_agents()
    |> Enum.map(fn pid ->
      try do
        state = AgentServer.get_state(pid)
        {state.name, Node.self(), pid}
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Register a local agent in the directory.

  Called when an agent is started to make it discoverable across nodes.
  """
  @spec register_agent(String.t(), pid()) :: :ok
  def register_agent(agent_name, pid) when is_binary(agent_name) and is_pid(pid) do
    AgentDirectory.register(agent_name, Node.self(), pid)
  end

  @doc """
  Unregister an agent from the directory.

  Called when an agent is stopped.
  """
  @spec unregister_agent(String.t()) :: :ok
  def unregister_agent(agent_name) when is_binary(agent_name) do
    AgentDirectory.unregister(agent_name)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp find_agent_local_or_remote(agent_name) do
    # Step 2: Check local Registry
    case AgentSupervisor.whereis(agent_name) do
      {:ok, pid} ->
        # Register in directory for future lookups
        AgentDirectory.register(agent_name, Node.self(), pid)
        {:ok, {Node.self(), pid}}

      :error ->
        # Step 3: Search local agents by name
        case search_local_agents(agent_name) do
          {:ok, pid} ->
            AgentDirectory.register(agent_name, Node.self(), pid)
            {:ok, {Node.self(), pid}}

          :error ->
            # Step 4: Query remote nodes
            find_agent_remote(agent_name)
        end
    end
  end

  defp search_local_agents(agent_name) do
    result =
      AgentSupervisor.list_agents()
      |> Enum.find(fn pid ->
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

  defp find_agent_remote(agent_name) do
    Node.list()
    |> Enum.find_value(:error, fn node ->
      case :rpc.call(node, AgentFramework.AgentSupervisor, :whereis, [agent_name]) do
        {:ok, pid} ->
          # Cache in directory
          AgentDirectory.register(agent_name, node, pid)
          {:ok, {node, pid}}

        _ ->
          # Try searching all agents on that node
          case :rpc.call(node, __MODULE__, :search_local_agents_public, [agent_name]) do
            {:ok, pid} ->
              AgentDirectory.register(agent_name, node, pid)
              {:ok, {node, pid}}

            _ ->
              nil
          end
      end
    end)
  end

  @doc false
  # Public wrapper for RPC calls from remote nodes
  def search_local_agents_public(agent_name) do
    search_local_agents(agent_name)
  end
end
