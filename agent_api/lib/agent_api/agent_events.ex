defmodule AgentApi.AgentEvents do
  @moduledoc """
  PubSub-based event broadcasting for agent lifecycle events.

  Provides a centralized module for broadcasting and subscribing to
  agent events across the cluster. Uses Phoenix.PubSub which automatically
  propagates messages to all connected nodes.

  ## Topics

  - `"agent:events"` - All agent lifecycle events (started, stopped, task_completed)
  - `"agent:events:<name>"` - Events for a specific agent
  - `"cluster:events"` - Cluster-level events (node_up, node_down)

  ## Event Format

  All events are maps with at least:

      %{
        event: :atom,       # Event type
        agent: "name",      # Agent name (agent events)
        node: :node@host,   # Node where event occurred
        timestamp: DateTime  # When event occurred
      }

  ## Example

      # Subscribe to all agent events
      AgentEvents.subscribe_agent_events()

      # Subscribe to a specific agent
      AgentEvents.subscribe_agent("Worker-1")

      # Broadcast an event
      AgentEvents.broadcast_agent_started("Worker-1")

      # In a GenServer handle_info:
      def handle_info({:agent_event, event}, state) do
        IO.inspect(event)
        {:noreply, state}
      end

  """

  @pubsub AgentApi.PubSub
  @agent_events_topic "agent:events"
  @cluster_events_topic "cluster:events"

  # ============================================
  # Subscription API
  # ============================================

  @doc """
  Subscribe to all agent lifecycle events.

  The calling process will receive messages in the form:
  `{:agent_event, event_map}`
  """
  @spec subscribe_agent_events() :: :ok | {:error, term()}
  def subscribe_agent_events do
    Phoenix.PubSub.subscribe(@pubsub, @agent_events_topic)
  end

  @doc """
  Subscribe to events for a specific agent.

  The calling process will receive messages in the form:
  `{:agent_event, event_map}`
  """
  @spec subscribe_agent(String.t()) :: :ok | {:error, term()}
  def subscribe_agent(agent_name) when is_binary(agent_name) do
    Phoenix.PubSub.subscribe(@pubsub, "agent:events:#{agent_name}")
  end

  @doc """
  Subscribe to cluster-level events (node up/down).

  The calling process will receive messages in the form:
  `{:cluster_event, event_map}`
  """
  @spec subscribe_cluster_events() :: :ok | {:error, term()}
  def subscribe_cluster_events do
    Phoenix.PubSub.subscribe(@pubsub, @cluster_events_topic)
  end

  @doc """
  Unsubscribe from all agent events.
  """
  @spec unsubscribe_agent_events() :: :ok
  def unsubscribe_agent_events do
    Phoenix.PubSub.unsubscribe(@pubsub, @agent_events_topic)
  end

  @doc """
  Unsubscribe from a specific agent's events.
  """
  @spec unsubscribe_agent(String.t()) :: :ok
  def unsubscribe_agent(agent_name) when is_binary(agent_name) do
    Phoenix.PubSub.unsubscribe(@pubsub, "agent:events:#{agent_name}")
  end

  # ============================================
  # Broadcasting API - Agent Events
  # ============================================

  @doc """
  Broadcast that an agent was started.
  """
  @spec broadcast_agent_started(String.t()) :: :ok | {:error, term()}
  def broadcast_agent_started(agent_name) do
    event = build_agent_event(:agent_started, agent_name)
    broadcast_agent_event(agent_name, event)
  end

  @doc """
  Broadcast that an agent was stopped.
  """
  @spec broadcast_agent_stopped(String.t()) :: :ok | {:error, term()}
  def broadcast_agent_stopped(agent_name) do
    event = build_agent_event(:agent_stopped, agent_name)
    broadcast_agent_event(agent_name, event)
  end

  @doc """
  Broadcast that an agent completed a task.
  """
  @spec broadcast_task_completed(String.t(), map()) :: :ok | {:error, term()}
  def broadcast_task_completed(agent_name, result \\ %{}) do
    event = build_agent_event(:task_completed, agent_name, %{result: result})
    broadcast_agent_event(agent_name, event)
  end

  @doc """
  Broadcast that an agent received a task.
  """
  @spec broadcast_task_received(String.t(), map()) :: :ok | {:error, term()}
  def broadcast_task_received(agent_name, task_info \\ %{}) do
    event = build_agent_event(:task_received, agent_name, %{task: task_info})
    broadcast_agent_event(agent_name, event)
  end

  # ============================================
  # Broadcasting API - Cluster Events
  # ============================================

  @doc """
  Broadcast a cluster-level event (node_up, node_down, etc.).
  """
  @spec broadcast_cluster_event(atom(), map()) :: :ok | {:error, term()}
  def broadcast_cluster_event(event_type, data \\ %{}) do
    event =
      Map.merge(data, %{
        event: event_type,
        node: Node.self(),
        timestamp: DateTime.utc_now()
      })

    Phoenix.PubSub.broadcast(@pubsub, @cluster_events_topic, {:cluster_event, event})
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp build_agent_event(event_type, agent_name, extra \\ %{}) do
    Map.merge(extra, %{
      event: event_type,
      agent: agent_name,
      node: Node.self(),
      timestamp: DateTime.utc_now()
    })
  end

  defp broadcast_agent_event(agent_name, event) do
    # Broadcast to the general agent events topic
    Phoenix.PubSub.broadcast(@pubsub, @agent_events_topic, {:agent_event, event})

    # Also broadcast to the agent-specific topic
    Phoenix.PubSub.broadcast(@pubsub, "agent:events:#{agent_name}", {:agent_event, event})
  end
end
