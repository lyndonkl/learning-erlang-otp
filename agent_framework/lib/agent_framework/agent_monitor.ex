defmodule AgentFramework.AgentMonitor do
  @moduledoc """
  Monitors agent processes and handles failures.

  This module provides a simple supervisor-like process that:
  - Monitors agent processes
  - Detects crashes
  - Optionally restarts crashed agents
  - Logs failures

  ## Example

      # Start the monitor
      {:ok, monitor} = AgentMonitor.start_link()

      # Register an agent to be monitored
      {:ok, agent} = ProcessAgent.start_link("Worker-1")
      AgentMonitor.monitor_agent(monitor, "Worker-1", agent)

      # The monitor will restart the agent if it crashes
      send(agent, {:crash, :test_crash})

  """

  alias AgentFramework.ProcessAgent

  @type monitor_state :: %{
          agents: %{String.t() => agent_info()},
          restart_policy: :always | :never | :transient
        }

  @type agent_info :: %{
          pid: pid(),
          ref: reference(),
          restart_count: non_neg_integer(),
          config: map()
        }

  # ============================================
  # Public API
  # ============================================

  @doc """
  Start an agent monitor process.

  ## Options
  - `:restart_policy` - `:always`, `:never`, or `:transient` (default: `:always`)
    - `:always` - Always restart crashed agents
    - `:never` - Never restart (just log)
    - `:transient` - Only restart on abnormal exits
  - `:max_restarts` - Maximum restarts per agent (default: 5)

  ## Examples

      {:ok, monitor} = AgentMonitor.start_link()
      {:ok, monitor} = AgentMonitor.start_link(restart_policy: :never)
  """
  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    restart_policy = Keyword.get(opts, :restart_policy, :always)
    max_restarts = Keyword.get(opts, :max_restarts, 5)

    pid = spawn_link(fn ->
      Process.flag(:trap_exit, true)

      loop(%{
        agents: %{},
        restart_policy: restart_policy,
        max_restarts: max_restarts
      })
    end)

    {:ok, pid}
  end

  @doc """
  Stop the agent monitor.

  This will also stop all monitored agents.

  ## Examples

      AgentMonitor.stop(monitor)
  """
  @spec stop(pid()) :: :ok
  def stop(monitor) when is_pid(monitor) do
    send(monitor, :stop)
    :ok
  end

  @doc """
  Start and monitor a new agent.

  Returns `{:ok, agent_pid}` on success.

  ## Examples

      {:ok, agent} = AgentMonitor.start_agent(monitor, "Worker-1")
      {:ok, agent} = AgentMonitor.start_agent(monitor, "Worker-2", memory: %{key: "value"})
  """
  @spec start_agent(pid(), String.t(), keyword()) :: {:ok, pid()} | {:error, any()}
  def start_agent(monitor, name, opts \\ []) when is_pid(monitor) and is_binary(name) do
    send(monitor, {:start_agent, name, opts, self()})

    receive do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    after
      5000 -> {:error, :timeout}
    end
  end

  @doc """
  Monitor an existing agent process.

  ## Examples

      {:ok, agent} = ProcessAgent.start_link("Worker-1")
      :ok = AgentMonitor.monitor_agent(monitor, "Worker-1", agent)
  """
  @spec monitor_agent(pid(), String.t(), pid(), map()) :: :ok | {:error, any()}
  def monitor_agent(monitor, name, agent_pid, config \\ %{})
      when is_pid(monitor) and is_binary(name) and is_pid(agent_pid) do
    send(monitor, {:monitor_agent, name, agent_pid, config, self()})

    receive do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    after
      5000 -> {:error, :timeout}
    end
  end

  @doc """
  Stop monitoring an agent (and optionally stop the agent itself).

  ## Examples

      :ok = AgentMonitor.unmonitor_agent(monitor, "Worker-1")
      :ok = AgentMonitor.unmonitor_agent(monitor, "Worker-1", stop_agent: true)
  """
  @spec unmonitor_agent(pid(), String.t(), keyword()) :: :ok
  def unmonitor_agent(monitor, name, opts \\ []) when is_pid(monitor) and is_binary(name) do
    stop_agent? = Keyword.get(opts, :stop_agent, false)
    send(monitor, {:unmonitor_agent, name, stop_agent?})
    :ok
  end

  @doc """
  List all monitored agents.

  ## Examples

      [{"Worker-1", #PID<...>}, {"Worker-2", #PID<...>}] = AgentMonitor.list_agents(monitor)
  """
  @spec list_agents(pid(), timeout()) :: [{String.t(), pid()}]
  def list_agents(monitor, timeout \\ 5000) when is_pid(monitor) do
    send(monitor, {:list_agents, self()})

    receive do
      {:agents, agents} -> agents
    after
      timeout -> []
    end
  end

  @doc """
  Get detailed status of the monitor.

  ## Examples

      %{
        agent_count: 2,
        restart_policy: :always,
        agents: %{
          "Worker-1" => %{pid: ..., restart_count: 0},
          "Worker-2" => %{pid: ..., restart_count: 1}
        }
      } = AgentMonitor.status(monitor)
  """
  @spec status(pid(), timeout()) :: map()
  def status(monitor, timeout \\ 5000) when is_pid(monitor) do
    send(monitor, {:status, self()})

    receive do
      {:status, status} -> status
    after
      timeout -> %{error: :timeout}
    end
  end

  # ============================================
  # Monitor Loop (Private)
  # ============================================

  defp loop(state) do
    receive do
      # --- Start a new agent ---
      {:start_agent, name, opts, from} ->
        case Map.get(state.agents, name) do
          nil ->
            case do_start_agent(name, opts) do
              {:ok, pid, ref} ->
                agent_info = %{
                  pid: pid,
                  ref: ref,
                  restart_count: 0,
                  config: Keyword.get(opts, :config, %{})
                }

                send(from, {:ok, pid})
                loop(%{state | agents: Map.put(state.agents, name, agent_info)})

              {:error, reason} ->
                send(from, {:error, reason})
                loop(state)
            end

          _existing ->
            send(from, {:error, :already_exists})
            loop(state)
        end

      # --- Monitor existing agent ---
      {:monitor_agent, name, pid, config, from} ->
        ref = Process.monitor(pid)
        Process.link(pid)

        agent_info = %{
          pid: pid,
          ref: ref,
          restart_count: 0,
          config: config
        }

        send(from, :ok)
        loop(%{state | agents: Map.put(state.agents, name, agent_info)})

      # --- Unmonitor agent ---
      {:unmonitor_agent, name, stop_agent?} ->
        case Map.get(state.agents, name) do
          nil ->
            loop(state)

          %{pid: pid, ref: ref} ->
            Process.demonitor(ref, [:flush])
            Process.unlink(pid)

            if stop_agent? do
              ProcessAgent.stop(pid)
            end

            loop(%{state | agents: Map.delete(state.agents, name)})
        end

      # --- Agent crashed (via monitor) ---
      {:DOWN, ref, :process, pid, reason} ->
        handle_agent_down(state, ref, pid, reason)

      # --- Agent crashed (via link) ---
      {:EXIT, pid, reason} ->
        handle_agent_exit(state, pid, reason)

      # --- Queries ---
      {:list_agents, from} ->
        agents =
          state.agents
          |> Enum.map(fn {name, %{pid: pid}} -> {name, pid} end)

        send(from, {:agents, agents})
        loop(state)

      {:status, from} ->
        status = %{
          agent_count: map_size(state.agents),
          restart_policy: state.restart_policy,
          max_restarts: state.max_restarts,
          agents:
            state.agents
            |> Enum.map(fn {name, info} ->
              {name, %{pid: info.pid, restart_count: info.restart_count}}
            end)
            |> Map.new()
        }

        send(from, {:status, status})
        loop(state)

      # --- Shutdown ---
      :stop ->
        IO.puts("[AgentMonitor] Shutting down...")

        Enum.each(state.agents, fn {name, %{pid: pid}} ->
          IO.puts("[AgentMonitor] Stopping agent #{name}")
          ProcessAgent.stop(pid)
        end)

        :ok

      _other ->
        loop(state)
    end
  end

  # ============================================
  # Failure Handling (Private)
  # ============================================

  defp handle_agent_down(state, ref, pid, reason) do
    case find_agent_by_ref(state.agents, ref) do
      {name, agent_info} ->
        IO.puts("[AgentMonitor] Agent #{name} (#{inspect(pid)}) down: #{inspect(reason)}")
        handle_agent_failure(state, name, agent_info, reason)

      nil ->
        loop(state)
    end
  end

  defp handle_agent_exit(state, pid, reason) do
    case find_agent_by_pid(state.agents, pid) do
      {name, agent_info} ->
        IO.puts("[AgentMonitor] Agent #{name} (#{inspect(pid)}) exited: #{inspect(reason)}")
        handle_agent_failure(state, name, agent_info, reason)

      nil ->
        loop(state)
    end
  end

  defp handle_agent_failure(state, name, agent_info, reason) do
    should_restart? = should_restart?(state.restart_policy, reason, agent_info, state.max_restarts)

    if should_restart? do
      IO.puts("[AgentMonitor] Restarting agent #{name}...")
      Process.sleep(100)  # Brief delay before restart

      case do_start_agent(name, config: agent_info.config) do
        {:ok, new_pid, new_ref} ->
          new_info = %{agent_info |
            pid: new_pid,
            ref: new_ref,
            restart_count: agent_info.restart_count + 1
          }

          IO.puts("[AgentMonitor] Agent #{name} restarted as #{inspect(new_pid)}")
          loop(%{state | agents: Map.put(state.agents, name, new_info)})

        {:error, restart_reason} ->
          IO.puts("[AgentMonitor] Failed to restart #{name}: #{inspect(restart_reason)}")
          loop(%{state | agents: Map.delete(state.agents, name)})
      end
    else
      IO.puts("[AgentMonitor] Not restarting agent #{name}")
      loop(%{state | agents: Map.delete(state.agents, name)})
    end
  end

  defp should_restart?(:never, _reason, _info, _max), do: false
  defp should_restart?(_policy, :normal, _info, _max), do: false
  defp should_restart?(_policy, :shutdown, _info, _max), do: false
  defp should_restart?(_policy, {:shutdown, _}, _info, _max), do: false
  defp should_restart?(_policy, _reason, %{restart_count: count}, max) when count >= max do
    IO.puts("[AgentMonitor] Max restarts (#{max}) reached")
    false
  end
  defp should_restart?(:always, _reason, _info, _max), do: true
  defp should_restart?(:transient, _reason, _info, _max), do: true

  # ============================================
  # Helpers (Private)
  # ============================================

  defp do_start_agent(name, opts) do
    _config = Keyword.get(opts, :config, %{})
    memory = Keyword.get(opts, :memory, %{})

    case ProcessAgent.start_link(name, memory: memory) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        {:ok, pid, ref}

      error ->
        error
    end
  end

  defp find_agent_by_ref(agents, ref) do
    Enum.find(agents, fn {_name, %{ref: r}} -> r == ref end)
  end

  defp find_agent_by_pid(agents, pid) do
    Enum.find(agents, fn {_name, %{pid: p}} -> p == pid end)
  end
end
