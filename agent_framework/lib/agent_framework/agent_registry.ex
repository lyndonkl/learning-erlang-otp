defmodule AgentFramework.AgentRegistry do
  @moduledoc """
  Registry for named agent processes.

  Provides name-based lookup for agent processes, enabling:
  - Starting agents with unique names
  - Looking up agents by name instead of PID
  - Automatic cleanup when agents die

  ## Example

      # Start the registry (usually done at application start)
      AgentRegistry.start_link()

      # Register the current process as an agent
      AgentRegistry.register("Worker-1")

      # Lookup an agent by name
      {:ok, pid} = AgentRegistry.lookup("Worker-1")

      # List all registered agents
      ["Worker-1", "Worker-2"] = AgentRegistry.list()

  """

  @registry_name __MODULE__

  # ============================================
  # Registry Lifecycle
  # ============================================

  @doc """
  Start the agent registry.

  This should be called once at application startup.
  Returns `{:ok, pid}` or `{:error, reason}`.

  ## Examples

      {:ok, _pid} = AgentRegistry.start_link()
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, any()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @registry_name)
    Registry.start_link(keys: :unique, name: name)
  end

  @doc """
  Check if the registry is running.

  ## Examples

      true = AgentRegistry.running?()
  """
  @spec running?() :: boolean()
  def running? do
    case Process.whereis(@registry_name) do
      nil -> false
      _pid -> true
    end
  end

  # ============================================
  # Registration
  # ============================================

  @doc """
  Register the current process as an agent with the given name.

  Returns `:ok` on success, `{:error, :already_registered}` if the name is taken.

  ## Examples

      :ok = AgentRegistry.register("Worker-1")
      {:error, :already_registered} = AgentRegistry.register("Worker-1")
  """
  @spec register(String.t(), map()) :: :ok | {:error, :already_registered}
  def register(name, metadata \\ %{}) when is_binary(name) do
    case Registry.register(@registry_name, name, metadata) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> {:error, :already_registered}
    end
  end

  @doc """
  Unregister the current process from the given name.

  ## Examples

      :ok = AgentRegistry.unregister("Worker-1")
  """
  @spec unregister(String.t()) :: :ok
  def unregister(name) when is_binary(name) do
    Registry.unregister(@registry_name, name)
  end

  # ============================================
  # Lookup
  # ============================================

  @doc """
  Look up an agent by name.

  Returns `{:ok, pid}` if found, `:error` if not found.

  ## Examples

      {:ok, pid} = AgentRegistry.lookup("Worker-1")
      :error = AgentRegistry.lookup("NonExistent")
  """
  @spec lookup(String.t()) :: {:ok, pid()} | :error
  def lookup(name) when is_binary(name) do
    case Registry.lookup(@registry_name, name) do
      [{pid, _metadata}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Look up an agent and get its metadata.

  Returns `{:ok, pid, metadata}` if found, `:error` if not found.

  ## Examples

      {:ok, pid, %{role: :worker}} = AgentRegistry.lookup_with_meta("Worker-1")
  """
  @spec lookup_with_meta(String.t()) :: {:ok, pid(), map()} | :error
  def lookup_with_meta(name) when is_binary(name) do
    case Registry.lookup(@registry_name, name) do
      [{pid, metadata}] -> {:ok, pid, metadata}
      [] -> :error
    end
  end

  @doc """
  Check if an agent with the given name exists.

  ## Examples

      true = AgentRegistry.exists?("Worker-1")
      false = AgentRegistry.exists?("NonExistent")
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(name) when is_binary(name) do
    case lookup(name) do
      {:ok, _pid} -> true
      :error -> false
    end
  end

  # ============================================
  # Listing
  # ============================================

  @doc """
  List all registered agent names.

  ## Examples

      ["Worker-1", "Worker-2"] = AgentRegistry.list()
  """
  @spec list() :: [String.t()]
  def list do
    Registry.select(@registry_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  List all registered agents with their PIDs.

  ## Examples

      [{"Worker-1", #PID<0.123.0>}] = AgentRegistry.list_with_pids()
  """
  @spec list_with_pids() :: [{String.t(), pid()}]
  def list_with_pids do
    Registry.select(@registry_name, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Count the number of registered agents.

  ## Examples

      2 = AgentRegistry.count()
  """
  @spec count() :: non_neg_integer()
  def count do
    length(list())
  end

  # ============================================
  # Messaging Helpers
  # ============================================

  @doc """
  Send a message to a named agent.

  Returns `:ok` if the agent exists, `:error` if not found.

  ## Examples

      :ok = AgentRegistry.send("Worker-1", {:task, :search})
      :error = AgentRegistry.send("NonExistent", {:task, :search})
  """
  @spec send(String.t(), any()) :: :ok | :error
  def send(name, message) when is_binary(name) do
    case lookup(name) do
      {:ok, pid} ->
        Kernel.send(pid, message)
        :ok

      :error ->
        :error
    end
  end

  @doc """
  Broadcast a message to all registered agents.

  Returns the count of agents that received the message.

  ## Examples

      3 = AgentRegistry.broadcast({:system, :shutdown_warning})
  """
  @spec broadcast(any()) :: non_neg_integer()
  def broadcast(message) do
    agents = list_with_pids()

    Enum.each(agents, fn {_name, pid} ->
      Kernel.send(pid, message)
    end)

    length(agents)
  end

  # ============================================
  # Via Tuple Support
  # ============================================

  @doc """
  Get a via tuple for use with GenServer/Agent.

  This enables starting processes that auto-register:

      GenServer.start_link(MyServer, args, name: AgentRegistry.via("Worker-1"))

  ## Examples

      {:via, Registry, {AgentRegistry, "Worker-1"}} = AgentRegistry.via("Worker-1")
  """
  @spec via(String.t()) :: {:via, Registry, {atom(), String.t()}}
  def via(name) when is_binary(name) do
    {:via, Registry, {@registry_name, name}}
  end

  @doc """
  Get a via tuple with metadata.

  ## Examples

      {:via, Registry, {AgentRegistry, "Worker-1", %{role: :worker}}} =
        AgentRegistry.via("Worker-1", %{role: :worker})
  """
  @spec via(String.t(), map()) :: {:via, Registry, {atom(), String.t(), map()}}
  def via(name, metadata) when is_binary(name) and is_map(metadata) do
    {:via, Registry, {@registry_name, name, metadata}}
  end
end
