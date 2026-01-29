defmodule AgentFramework.Application do
  @moduledoc """
  OTP Application for AgentFramework.

  This module is the entry point for the OTP application. When you run
  `iex -S mix` or `mix run`, this module's `start/2` callback is invoked
  automatically, starting the supervision tree.

  ## Supervision Tree

  ```
  AgentFramework.Supervisor (strategy: :one_for_one)
         │
    ┌────┼──────────────┐
    ▼    ▼              ▼
  Registry  AgentDirectory  AgentSupervisor
                              │
                         (dynamic agents)
  ```

  The tree consists of:

  1. **Registry** - Provides name-based lookup for agents
  2. **AgentDirectory** - ETS-backed cross-node agent name→{node, pid} directory
  3. **AgentSupervisor** - DynamicSupervisor for agent processes

  ## Why This Structure?

  - **one_for_one strategy**: Registry, AgentDirectory, and AgentSupervisor
    are independent. If one crashes, the others can continue operating.

  - **Registry first**: Agents may want to register themselves, so Registry
    must be started before any agents.

  - **AgentDirectory second**: ETS-backed directory for cross-node agent
    lookups. Must be started before agents can register themselves.

  - **DynamicSupervisor**: Agents are added at runtime, not at application
    startup, so we use DynamicSupervisor instead of regular Supervisor.

  ## Configuration

  No configuration is required. The application will start with default
  settings. Future versions may add configuration options for:

  - Registry name
  - Supervisor restart intensity
  - Default agent options

  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for named agent lookup
      # Agents can use AgentFramework.AgentRegistry.via("name") to register
      {Registry, keys: :unique, name: AgentFramework.Registry},

      # ETS-backed directory for cross-node agent lookups
      # Supports concurrent reads without GenServer bottleneck
      AgentFramework.AgentDirectory,

      # DynamicSupervisor for agent processes
      # Agents are added at runtime via AgentSupervisor.start_agent/2
      {AgentFramework.AgentSupervisor, name: AgentFramework.AgentSupervisor}
    ]

    # Start the top-level supervisor
    opts = [
      strategy: :one_for_one,
      name: AgentFramework.Supervisor
    ]

    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    :ok
  end
end
