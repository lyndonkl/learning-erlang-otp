# Learning Erlang/OTP with Elixir

A hands-on learning journey through Erlang/OTP concepts using Elixir, building toward a multi-agent framework with A2A protocol support.

## Structure

```
.
├── notebooks/           # Livebook notebooks for interactive learning
│   ├── 01-06            # Phase 1: Core Elixir
│   ├── 07-11            # Phase 2: Concurrency Model
│   └── 12-16            # Phase 3: OTP Behaviours
├── agent_framework/     # Working Elixir project
│   ├── lib/             # Source code
│   └── test/            # Tests
└── learning-plan.md     # Full learning roadmap
```

## Phases

### Phase 1: Core Elixir (Complete)
- Basics, collections, pattern matching
- Functions, pipe operator, modules
- Mix project setup
- **Checkpoint**: Agent struct with message handling

### Phase 2: Concurrency Model (Complete)
- Processes, spawn, send/receive
- Links, monitors, fault tolerance
- "Let it crash" philosophy
- **Checkpoint**: ProcessAgent, AgentMonitor, AgentRegistry

### Phase 3: OTP Behaviours (Complete)
- GenServer, Supervisor, Application
- Supervision trees and restart strategies
- DynamicSupervisor for runtime children
- OTP Distribution basics
- **Checkpoint**: AgentServer (GenServer), AgentSupervisor (DynamicSupervisor)

### Phase 4: Phoenix Essentials (Planned)
- HTTP/API layer with Phoenix
- A2A protocol endpoints

## Running the Agent Framework

```bash
cd agent_framework
mix deps.get
mix test

# Interactive session
iex -S mix

# Start an agent
{:ok, agent} = AgentFramework.start_otp_agent("Worker-1")
AgentFramework.otp_remember(agent, :task, "research")
AgentFramework.otp_send_task(agent, :search, %{query: "OTP"})
{:ok, task, result} = AgentFramework.otp_process_next(agent)
```

## Running Livebook Notebooks

1. Install [Livebook](https://livebook.dev/)
2. Open any `.livemd` file from the `notebooks/` directory
3. Follow the interactive exercises

## Learning Resources

- [Elixir School](https://elixirschool.com/)
- [Learn You Some Erlang](https://learnyousomeerlang.com/)
- [Phoenix Guides](https://hexdocs.pm/phoenix/)

## License

MIT
