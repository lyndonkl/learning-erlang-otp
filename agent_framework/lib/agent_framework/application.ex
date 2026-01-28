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
    ┌────┴────┐
    ▼         ▼
  Registry  AgentSupervisor
              │
         (dynamic agents)
  ```

  The tree consists of:

  1. **Registry** - Provides name-based lookup for agents
  2. **AgentSupervisor** - DynamicSupervisor for agent processes

  ## Why This Structure?

  - **one_for_one strategy**: Registry and AgentSupervisor are independent.
    If one crashes, the other can continue operating.

  - **Registry first**: Agents may want to register themselves, so Registry
    must be started before any agents.

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
