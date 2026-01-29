defmodule AgentApi.Cluster.ClusterMonitor do
  @moduledoc """
  GenServer that monitors node connections and disconnections.

  Subscribes to `:net_kernel.monitor_nodes/1` to receive
  `:nodeup` and `:nodedown` messages. Tracks the current set
  of connected nodes and broadcasts cluster events via PubSub.

  ## Supervision Tree

  Started by AgentApi.Application as part of the cluster supervision.

  ## Example

      ClusterMonitor.connected_nodes()
      # => [:node2@host, :node3@host]

      ClusterMonitor.cluster_info()
      # => %{self: :node1@host, connected: [:node2@host], total: 2}

  """
  use GenServer

  require Logger

  alias AgentApi.AgentEvents

  @default_name __MODULE__

  # ============================================
  # Client API
  # ============================================

  @doc """
  Start the ClusterMonitor GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Get the list of currently connected nodes.

  ## Examples

      [:node2@host, :node3@host] = ClusterMonitor.connected_nodes()

  """
  @spec connected_nodes() :: [node()]
  def connected_nodes do
    GenServer.call(@default_name, :connected_nodes)
  end

  @doc """
  Get cluster information.

  Returns a map with:
  - `:self` - This node's name
  - `:connected` - List of connected nodes
  - `:total` - Total node count (including self)

  ## Examples

      %{self: :node1@host, connected: [:node2@host], total: 2}
      = ClusterMonitor.cluster_info()

  """
  @spec cluster_info() :: map()
  def cluster_info do
    GenServer.call(@default_name, :cluster_info)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    # Subscribe to node up/down events
    :net_kernel.monitor_nodes(true)

    state = %{
      connected_nodes: Node.list(),
      self: Node.self()
    }

    Logger.info("[ClusterMonitor] Started on #{Node.self()}, connected to #{length(state.connected_nodes)} nodes")
    {:ok, state}
  end

  @impl true
  def handle_call(:connected_nodes, _from, state) do
    {:reply, state.connected_nodes, state}
  end

  def handle_call(:cluster_info, _from, state) do
    info = %{
      self: state.self,
      connected: state.connected_nodes,
      total: length(state.connected_nodes) + 1
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("[ClusterMonitor] Node connected: #{node}")
    new_nodes = Enum.uniq([node | state.connected_nodes])
    new_state = %{state | connected_nodes: new_nodes}

    # Broadcast node up event via PubSub
    AgentEvents.broadcast_cluster_event(:node_up, %{node: node, connected: new_nodes})

    {:noreply, new_state}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.warning("[ClusterMonitor] Node disconnected: #{node}")
    new_nodes = List.delete(state.connected_nodes, node)
    new_state = %{state | connected_nodes: new_nodes}

    # Clean up agents from the disconnected node
    AgentFramework.AgentDirectory.remove_node_agents(node)

    # Broadcast node down event via PubSub
    AgentEvents.broadcast_cluster_event(:node_down, %{node: node, connected: new_nodes})

    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("[ClusterMonitor] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :net_kernel.monitor_nodes(false)
    :ok
  end
end
