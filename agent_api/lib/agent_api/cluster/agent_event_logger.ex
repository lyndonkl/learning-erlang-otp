defmodule AgentApi.Cluster.AgentEventLogger do
  @moduledoc """
  PubSub subscriber that logs all agent and cluster events.

  Subscribes to both agent lifecycle events and cluster events,
  logging them with appropriate severity levels. Useful for
  debugging and monitoring in development.

  ## Event Types Logged

  - `:agent_started` - An agent was started (info)
  - `:agent_stopped` - An agent was stopped (info)
  - `:task_received` - An agent received a task (debug)
  - `:task_completed` - An agent completed a task (info)
  - `:node_up` - A node joined the cluster (info)
  - `:node_down` - A node left the cluster (warning)

  ## Example

      # Started automatically by AgentApi.Application
      # Logs appear in the console:
      #
      # [info] [AgentEventLogger] agent_started: Worker-1 on node1@host
      # [info] [AgentEventLogger] task_completed: Worker-1 on node1@host

  """
  use GenServer

  require Logger

  alias AgentApi.AgentEvents

  @default_name __MODULE__

  # ============================================
  # Client API
  # ============================================

  @doc """
  Start the AgentEventLogger GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # ============================================
  # Server Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    # Subscribe to all agent and cluster events
    AgentEvents.subscribe_agent_events()
    AgentEvents.subscribe_cluster_events()

    Logger.info("[AgentEventLogger] Started - subscribing to agent and cluster events")
    {:ok, %{event_count: 0}}
  end

  @impl true
  def handle_info({:agent_event, event}, state) do
    log_agent_event(event)
    {:noreply, %{state | event_count: state.event_count + 1}}
  end

  def handle_info({:cluster_event, event}, state) do
    log_cluster_event(event)
    {:noreply, %{state | event_count: state.event_count + 1}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp log_agent_event(%{event: :agent_started, agent: agent, node: node}) do
    Logger.info("[AgentEventLogger] agent_started: #{agent} on #{node}")
  end

  defp log_agent_event(%{event: :agent_stopped, agent: agent, node: node}) do
    Logger.info("[AgentEventLogger] agent_stopped: #{agent} on #{node}")
  end

  defp log_agent_event(%{event: :task_received, agent: agent, node: node}) do
    Logger.debug("[AgentEventLogger] task_received: #{agent} on #{node}")
  end

  defp log_agent_event(%{event: :task_completed, agent: agent, node: node}) do
    Logger.info("[AgentEventLogger] task_completed: #{agent} on #{node}")
  end

  defp log_agent_event(%{event: event_type, agent: agent, node: node}) do
    Logger.info("[AgentEventLogger] #{event_type}: #{agent} on #{node}")
  end

  defp log_cluster_event(%{event: :node_up, node: node}) do
    Logger.info("[AgentEventLogger] cluster: node_up #{node}")
  end

  defp log_cluster_event(%{event: :node_down, node: node}) do
    Logger.warning("[AgentEventLogger] cluster: node_down #{node}")
  end

  defp log_cluster_event(%{event: event_type} = event) do
    Logger.info("[AgentEventLogger] cluster: #{event_type} #{inspect(event)}")
  end
end
