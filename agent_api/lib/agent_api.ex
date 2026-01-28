defmodule AgentApi do
  @moduledoc """
  AgentApi - A2A Protocol HTTP layer for AgentFramework.

  This Phoenix application provides HTTP endpoints for the A2A
  (Agent-to-Agent) protocol, allowing external clients to:

  1. Discover agent capabilities via the Agent Card
  2. Send tasks to agents via JSON-RPC
  3. Query task status and results

  ## Architecture

      External Client
           │
           ▼
      ┌─────────┐
      │ Phoenix │  HTTP Layer (this app)
      │ Endpoint│
      └────┬────┘
           │ JSON-RPC
           ▼
      ┌─────────┐
      │ Agent   │  OTP Layer (agent_framework)
      │ Server  │
      └─────────┘

  ## Endpoints

  - `GET /.well-known/agent.json` - Agent Card (discovery)
  - `POST /a2a` - JSON-RPC endpoint for agent interaction

  """
end
