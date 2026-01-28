# Learning Plan: Erlang/OTP + Elixir + Phoenix for Multi-Agent Framework

## Goal
Learn the essential fundamentals to build a multi-agent communication framework with A2A protocol support. Focus on concepts, not syntax memorization.

---

## Learning Philosophy
- **Concepts over syntax** - understand WHY things work, learn syntax as you code
- **Just enough** - skip topics not relevant to your framework
- **Project-driven** - apply concepts immediately to your agent framework
- **Top-down** - start with Elixir (friendlier), dip into Erlang/OTP for deep concepts

---

## Phase 1: Core Elixir (2-3 days)
> Source: [Elixir School](https://elixirschool.com/en)

### Essential Lessons (do these)
| Lesson | Why It Matters |
|--------|----------------|
| [Basics](https://elixirschool.com/en/lessons/basics/basics) | Data types, operators - skim quickly |
| [Collections](https://elixirschool.com/en/lessons/basics/collections) | Lists, maps, tuples - core data structures |
| [Pattern Matching](https://elixirschool.com/en/lessons/basics/pattern_matching) | **CRITICAL** - foundation of Elixir/Erlang |
| [Functions](https://elixirschool.com/en/lessons/basics/functions) | Function definitions, anonymous functions |
| [Pipe Operator](https://elixirschool.com/en/lessons/basics/pipe_operator) | `|>` - idiomatic Elixir code |
| [Modules](https://elixirschool.com/en/lessons/basics/modules) | Code organization |
| [Mix](https://elixirschool.com/en/lessons/basics/mix) | Build tool - create/manage projects |

### Skip or Skim
- Control Structures (learn as needed)
- Sigils, Comprehensions, Date/Time (reference later)
- Documentation, IEX Helpers (nice-to-have)

### Checkpoint Project
```
Create a simple module that:
1. Defines an "Agent" struct with name, state, inbox
2. Uses pattern matching to handle different message types
3. Pipe operations to transform messages
```

---

## Phase 2: Concurrency Model (2-3 days)
> Source: [Learn You Some Erlang](https://learnyousomeerlang.com/content) - selected chapters

### Essential Chapters
| Chapter | Why It Matters |
|---------|----------------|
| [The Hitchhiker's Guide to Concurrency](https://learnyousomeerlang.com/the-hitchhikers-guide-to-concurrency) | **START HERE** - processes, spawn, send/receive |
| [More On Multiprocessing](https://learnyousomeerlang.com/more-on-multiprocessing) | Process state, selective receive |
| [Errors and Processes](https://learnyousomeerlang.com/errors-and-processes) | Links, monitors, trapping exits - fault tolerance basics |
| [Designing a Concurrent Application](https://learnyousomeerlang.com/designing-a-concurrent-application) | Real example of building with processes |

### Reading Strategy
- Read for **concepts**, not Erlang syntax
- You'll implement in Elixir, which is cleaner
- Focus on: spawn, send (`!`), receive, link, monitor

### Skip These (for now)
- Chapters 1-11 (syntax-heavy basics)
- Chapter 10: Functionally Solving Problems
- Chapter 11: Data Structures

### Checkpoint Project
```elixir
# In Elixir, implement:
1. Spawn two agent processes
2. Have them send messages to each other
3. One agent crashes - observe what happens
4. Link them - observe crash propagation
5. Add a monitor - handle the crash gracefully
```

---

## Phase 3: OTP Behaviours (3-4 days)
> Source: [Elixir School Advanced](https://elixirschool.com/en/lessons/advanced/otp_concurrency) + [Learn You Some Erlang OTP](https://learnyousomeerlang.com/what-is-otp)

### Essential Lessons

**From Elixir School:**
| Lesson | Why It Matters |
|--------|----------------|
| [OTP Concurrency](https://elixirschool.com/en/lessons/advanced/otp_concurrency) | GenServer - your agents will be GenServers |
| [OTP Supervisors](https://elixirschool.com/en/lessons/advanced/otp_supervisors) | **CRITICAL** - fault tolerance for your agents |
| [OTP Distribution](https://elixirschool.com/en/lessons/advanced/otp_distribution) | Multi-node agent clusters |

**From Learn You Some Erlang (deeper understanding):**
| Chapter | Why It Matters |
|---------|----------------|
| [What is OTP?](https://learnyousomeerlang.com/what-is-otp) | Philosophy and overview |
| [Clients and Servers](https://learnyousomeerlang.com/clients-and-servers) | GenServer internals - understand what's happening |
| [Who Supervises The Supervisors?](https://learnyousomeerlang.com/supervisors) | Supervision tree design |

### Key Concepts to Master
1. **GenServer** - Agent = GenServer
   - `init/1` - agent initialization
   - `handle_call/3` - synchronous request (A2A tasks)
   - `handle_cast/2` - async messages (agent-to-agent)
   - `handle_info/2` - system messages, timeouts

2. **Supervision Trees**
   - `:one_for_one` - restart just the failed agent
   - `:one_for_all` - restart all agents in group
   - `:rest_for_one` - restart agent + ones started after
   - Restart strategies, child specs

### Skip These (for now)
- [Finite State Machines](https://learnyousomeerlang.com/finite-state-machines) (gen_statem) - use if needed later
- [Event Handlers](https://learnyousomeerlang.com/event-handlers) (gen_event) - rarely needed

### Checkpoint Project
```elixir
# Build a mini agent system:
1. Create AgentServer (GenServer) with:
   - state: %{name, memory, inbox}
   - handle_call for synchronous queries
   - handle_cast for async messages from other agents

2. Create AgentSupervisor
   - Supervises multiple agents
   - Restart strategy: one_for_one

3. Test fault tolerance:
   - Kill an agent process
   - Watch supervisor restart it
```

---

## Phase 4: Phoenix Essentials (2-3 days)
> Source: [Phoenix Framework Guides](https://hexdocs.pm/phoenix/overview.html)

### Essential Guides
| Guide | Why It Matters |
|-------|----------------|
| [Up and Running](https://hexdocs.pm/phoenix/up_and_running.html) | Create your first Phoenix project |
| [Directory Structure](https://hexdocs.pm/phoenix/directory_structure.html) | Understand project layout |
| [Request Life-cycle](https://hexdocs.pm/phoenix/request_lifecycle.html) | How HTTP requests flow |
| [Routing](https://hexdocs.pm/phoenix/routing.html) | Define API endpoints |
| [Controllers](https://hexdocs.pm/phoenix/controllers.html) | Handle HTTP requests |
| [JSON and APIs](https://hexdocs.pm/phoenix/json_and_apis.html) | **CRITICAL** - A2A is JSON-RPC |
| [Channels](https://hexdocs.pm/phoenix/channels.html) | Real-time communication (WebSockets) |

### Skip These (for now)
- Views, Templates, HTML - you're building an API
- Ecto/Database - unless you need persistence
- Authentication guides - add later
- LiveView - not relevant for agent framework

### Key Phoenix Concepts for A2A
1. **Endpoint** - Entry point, handles HTTP
2. **Router** - Maps URLs to controllers
3. **Controller** - Handles requests, returns JSON
4. **Channels** - WebSocket connections for real-time
5. **PubSub** - Broadcast messages across cluster

### Checkpoint Project
```elixir
# Build A2A-compatible endpoint:
1. Create Phoenix API project (--no-html --no-assets)
2. Implement /.well-known/agent.json (Agent Card)
3. Implement /a2a endpoint for JSON-RPC
4. Parse JSON-RPC request, dispatch to agent
5. Return JSON-RPC response
```

---

## Phase 5: Integration & Distribution (2-3 days)
> Source: [Learn You Some Erlang - Distribunomicon](https://learnyousomeerlang.com/distribunomicon) + Elixir School

### Essential Reading
| Resource | Why It Matters |
|----------|----------------|
| [Distribunomicon](https://learnyousomeerlang.com/distribunomicon) | Distributed Erlang concepts |
| [Elixir School - ETS](https://elixirschool.com/en/lessons/storage/ets) | Fast in-memory storage for agent state |
| [Plug](https://elixirschool.com/en/lessons/misc/plug) | HTTP middleware (Phoenix uses this) |

### Key Concepts
1. **Node Clustering** - Connect multiple BEAM instances
2. **Phoenix.PubSub** - Cross-node message broadcasting
3. **ETS** - Shared state within a node
4. **Registry** - Process discovery by name

### Final Integration Project
```elixir
# Multi-agent system with A2A:
1. Start 2 Phoenix nodes
2. Cluster them together
3. Agent on Node1 sends task to Agent on Node2
4. Use PubSub for broadcasting
5. External client calls A2A endpoint
6. Task routed to appropriate agent
```

---

## Quick Reference: What Maps to What

| Your Framework Concept | Erlang/OTP/Elixir Concept |
|----------------------|---------------------------|
| Agent | GenServer process |
| Agent communication | send/receive, GenServer.cast |
| Agent supervision | Supervisor, supervision tree |
| Agent discovery | Registry, Phoenix.PubSub |
| A2A Agent Card | JSON endpoint (Phoenix Controller) |
| A2A Task | GenServer state + async handling |
| Multi-node agents | Distributed Erlang, clustering |
| Real-time updates | Phoenix Channels, PubSub |

---

## Resources Summary

### Primary Resources (in order)
1. [Elixir School](https://elixirschool.com/en) - Basics through OTP
2. [Learn You Some Erlang](https://learnyousomeerlang.com/content) - Deep concurrency concepts
3. [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html) - HTTP/API layer
4. [OTP Design Principles](https://www.erlang.org/doc/design_principles/users_guide) - Reference

### When You Get Stuck
- Elixir syntax → [Elixir Cheatsheet](https://devhints.io/elixir)
- GenServer patterns → [Elixir School OTP](https://elixirschool.com/en/lessons/advanced/otp_concurrency)
- HTTP/JSON → [Phoenix JSON Guide](https://hexdocs.pm/phoenix/json_and_apis.html)

---

## Estimated Timeline

| Phase | Duration | Focus |
|-------|----------|-------|
| Phase 1 | 2-3 days | Elixir basics |
| Phase 2 | 2-3 days | Concurrency model |
| Phase 3 | 3-4 days | OTP behaviours |
| Phase 4 | 2-3 days | Phoenix HTTP/API |
| Phase 5 | 2-3 days | Distribution |
| **Total** | **~2 weeks** | Ready to build framework |

---

## Next Steps After Learning

1. Implement A2A protocol library in Elixir
2. Build GenServer-based Agent abstraction
3. Add LLM client (HTTP calls to local model server)
4. Create supervision tree for agent management
5. Add Phoenix endpoint for external A2A communication
