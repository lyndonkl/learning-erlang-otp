defmodule AgentFramework.AgentDirectory do
  @moduledoc """
  ETS-backed directory mapping agent names to their node and pid.

  Provides fast concurrent reads for agent lookups without going through
  a single GenServer process. Uses ETS `:set` table with `:public` access
  so any process can read, while writes are coordinated through this GenServer.

  ## Why ETS Instead of GenServer State?

  GenServer state requires all reads to go through a single process.
  With many agents doing lookups, this becomes a bottleneck:

      GenServer:  Agent-1 ──┐
                  Agent-2 ──┼── GenServer (serial) ──> state
                  Agent-3 ──┘

      ETS:        Agent-1 ──> ETS table (concurrent reads)
                  Agent-2 ──> ETS table
                  Agent-3 ──> ETS table

  ## Table Structure

  Each entry: `{name, node, pid}`

  - `name` - Agent name (String.t), unique key
  - `node` - Node where agent is running (atom)
  - `pid`  - Process identifier

  ## Example

      AgentDirectory.register("Worker-1", node(), self())
      {:ok, {node, pid}} = AgentDirectory.lookup("Worker-1")
      AgentDirectory.unregister("Worker-1")

  """
  use GenServer

  require Logger

  @table_name :agent_directory
  @default_name __MODULE__

  # ============================================
  # Client API
  # ============================================

  @doc """
  Start the AgentDirectory GenServer.

  Creates the ETS table and manages its lifecycle.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register an agent in the directory.

  Associates an agent name with its node and pid.
  If an agent with the same name exists, it will be overwritten.

  ## Examples

      :ok = AgentDirectory.register("Worker-1", node(), pid)

  """
  @spec register(String.t(), node(), pid()) :: :ok
  def register(name, node, pid) when is_binary(name) and is_atom(node) and is_pid(pid) do
    GenServer.call(@default_name, {:register, name, node, pid})
  end

  @doc """
  Unregister an agent from the directory.

  ## Examples

      :ok = AgentDirectory.unregister("Worker-1")

  """
  @spec unregister(String.t()) :: :ok
  def unregister(name) when is_binary(name) do
    GenServer.call(@default_name, {:unregister, name})
  end

  @doc """
  Look up an agent by name.

  Reads directly from ETS (no GenServer call needed - concurrent reads).

  ## Examples

      {:ok, {node, pid}} = AgentDirectory.lookup("Worker-1")
      :error = AgentDirectory.lookup("NonExistent")

  """
  @spec lookup(String.t()) :: {:ok, {node(), pid()}} | :error
  def lookup(name) when is_binary(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, node, pid}] -> {:ok, {node, pid}}
      [] -> :error
    end
  end

  @doc """
  List all registered agents.

  Returns a list of `{name, node, pid}` tuples.

  ## Examples

      agents = AgentDirectory.all_agents()
      # => [{"Worker-1", :node1@host, #PID<0.123.0>}, ...]

  """
  @spec all_agents() :: [{String.t(), node(), pid()}]
  def all_agents do
    :ets.tab2list(@table_name)
  end

  @doc """
  List agents on a specific node.

  ## Examples

      agents = AgentDirectory.agents_on_node(:node1@host)

  """
  @spec agents_on_node(node()) :: [{String.t(), node(), pid()}]
  def agents_on_node(node) when is_atom(node) do
    :ets.match_object(@table_name, {:_, node, :_})
  end

  @doc """
  Remove all agents registered on a specific node.

  Useful when a node goes down and its agents are no longer reachable.

  ## Examples

      :ok = AgentDirectory.remove_node_agents(:crashed_node@host)

  """
  @spec remove_node_agents(node()) :: :ok
  def remove_node_agents(node) when is_atom(node) do
    GenServer.call(@default_name, {:remove_node_agents, node})
  end

  @doc """
  Get the count of registered agents.

  ## Examples

      5 = AgentDirectory.count()

  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table_name, :size)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, name, node, pid}, _from, state) do
    :ets.insert(@table_name, {name, node, pid})
    Logger.debug("[AgentDirectory] Registered #{name} on #{node}")
    {:reply, :ok, state}
  end

  def handle_call({:unregister, name}, _from, state) do
    :ets.delete(@table_name, name)
    Logger.debug("[AgentDirectory] Unregistered #{name}")
    {:reply, :ok, state}
  end

  def handle_call({:remove_node_agents, node}, _from, state) do
    :ets.match_delete(@table_name, {:_, node, :_})
    Logger.info("[AgentDirectory] Removed all agents on #{node}")
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
