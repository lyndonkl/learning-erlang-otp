defmodule AgentApi.Application do
  @moduledoc """
  OTP Application for AgentApi.

  Starts the Phoenix endpoint and integrates with the AgentFramework
  supervision tree for A2A protocol support.

  ## Supervision Tree

      AgentApi.Supervisor
           │
      ┌────┼──────────────┬──────────────────┬──────────────┐
      ▼    ▼              ▼                  ▼              ▼
   PubSub  Cluster   ClusterMonitor   AgentEventLogger  Endpoint
           Supervisor
  """
  use Application

  @impl true
  def start(_type, _args) do
    # libcluster topology configuration
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      # Start the PubSub system
      {Phoenix.PubSub, name: AgentApi.PubSub},
      # Start libcluster for automatic node discovery
      {Cluster.Supervisor, [topologies, [name: AgentApi.ClusterSupervisor]]},
      # Monitor node up/down events
      AgentApi.Cluster.ClusterMonitor,
      # Log agent and cluster events via PubSub
      AgentApi.Cluster.AgentEventLogger,
      # Start the Endpoint (http/https)
      AgentApiWeb.Endpoint
      # Note: AgentFramework.AgentSupervisor is started by agent_framework app
    ]

    opts = [strategy: :one_for_one, name: AgentApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgentApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
