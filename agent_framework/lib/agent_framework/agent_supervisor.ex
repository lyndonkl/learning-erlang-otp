defmodule AgentFramework.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for agent processes.

  This is the OTP version of Phase 2's AgentMonitor. Instead of manually
  implementing process monitoring, restart logic, and failure handling,
  we leverage OTP's battle-tested DynamicSupervisor.

  ## Features

  - Start agents at runtime with `start_agent/2`
  - Automatic restart on agent crash
  - Configurable restart intensity (max_restarts/max_seconds)
  - Integration with OTP observer and debugging tools

  ## Example

      # Usually started by Application, but can start manually:
      {:ok, _} = AgentSupervisor.start_link([])

      # Start agents dynamically
      {:ok, agent1} = AgentSupervisor.start_agent("Worker-1")
      {:ok, agent2} = AgentSupervisor.start_agent("Worker-2", memory: %{key: "val"})

      # List supervised agents
      [pid1, pid2] = AgentSupervisor.list_agents()

      # Stop an agent
      :ok = AgentSupervisor.stop_agent(agent1)

  ## Comparison with Phase 2 AgentMonitor

  | AgentMonitor (Phase 2) | AgentSupervisor (Phase 3) |
  |------------------------|---------------------------|
  | ~200 lines of code     | ~50 lines of code         |
  | Manual Process.monitor | Automatic via OTP         |
  | Custom restart logic   | Built-in strategies       |
  | Limited debugging      | Full OTP observer support |

  """
  use DynamicSupervisor

  alias AgentFramework.AgentServer

  @default_name __MODULE__

  # ============================================
  # Public API
  # ============================================

  @doc """
  Start the agent supervisor.

  This is typically called by the Application module, not directly.

  ## Options

  - `:name` - Process name (default: #{inspect(@default_name)})

  ## Examples

      {:ok, pid} = AgentSupervisor.start_link([])
      {:ok, pid} = AgentSupervisor.start_link(name: MyApp.AgentSupervisor)

  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Start a new supervised agent.

  The agent will be automatically restarted if it crashes.

  ## Options

  - `:memory` - Initial memory map (default: %{})

  ## Examples

      {:ok, pid} = AgentSupervisor.start_agent("Worker-1")
      {:ok, pid} = AgentSupervisor.start_agent("Worker-2", memory: %{context: "research"})

  """
  @spec start_agent(String.t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(name, opts \\ []) when is_binary(name) do
    spec = {AgentServer, {name, opts}}
    DynamicSupervisor.start_child(@default_name, spec)
  end

  @doc """
  Start a supervised agent under a specific supervisor.

  Use this when running multiple supervisors (e.g., in tests).

  ## Examples

      {:ok, sup} = AgentSupervisor.start_link(name: :test_sup)
      {:ok, agent} = AgentSupervisor.start_agent(:test_sup, "Worker-1")

  """
  @spec start_agent(GenServer.server(), String.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_agent(supervisor, name, opts) when is_binary(name) do
    spec = {AgentServer, {name, opts}}
    DynamicSupervisor.start_child(supervisor, spec)
  end

  @doc """
  Stop a supervised agent.

  The agent will be terminated and removed from supervision.

  ## Examples

      :ok = AgentSupervisor.stop_agent(agent_pid)

  """
  @spec stop_agent(pid()) :: :ok | {:error, :not_found}
  def stop_agent(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(@default_name, pid)
  end

  @doc """
  Stop an agent under a specific supervisor.

  ## Examples

      :ok = AgentSupervisor.stop_agent(:test_sup, agent_pid)

  """
  @spec stop_agent(GenServer.server(), pid()) :: :ok | {:error, :not_found}
  def stop_agent(supervisor, pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(supervisor, pid)
  end

  @doc """
  List all supervised agent PIDs.

  ## Examples

      [pid1, pid2, pid3] = AgentSupervisor.list_agents()

  """
  @spec list_agents() :: [pid()]
  def list_agents do
    list_agents(@default_name)
  end

  @doc """
  List agents under a specific supervisor.
  """
  @spec list_agents(GenServer.server()) :: [pid()]
  def list_agents(supervisor) do
    DynamicSupervisor.which_children(supervisor)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end

  @doc """
  Count supervised agents.

  Returns a map with counts for:
  - `:specs` - Number of child specifications
  - `:active` - Number of actively running children
  - `:supervisors` - Number of child supervisors
  - `:workers` - Number of child workers

  ## Examples

      %{active: 3, specs: 3, supervisors: 0, workers: 3} = AgentSupervisor.count_agents()

  """
  @spec count_agents() :: %{
          specs: non_neg_integer(),
          active: non_neg_integer(),
          supervisors: non_neg_integer(),
          workers: non_neg_integer()
        }
  def count_agents do
    count_agents(@default_name)
  end

  @doc """
  Count agents under a specific supervisor.
  """
  @spec count_agents(GenServer.server()) :: map()
  def count_agents(supervisor) do
    DynamicSupervisor.count_children(supervisor)
  end

  @doc """
  Get information about a specific agent by name.

  This requires the Registry to be running and agents to be registered.
  Returns `{:ok, pid}` if found, `:error` if not.

  ## Examples

      {:ok, pid} = AgentSupervisor.whereis("Worker-1")
      :error = AgentSupervisor.whereis("NonExistent")

  """
  @spec whereis(String.t()) :: {:ok, pid()} | :error
  def whereis(name) when is_binary(name) do
    case Registry.lookup(AgentFramework.Registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  # ============================================
  # Callbacks
  # ============================================

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 60
    )
  end
end
