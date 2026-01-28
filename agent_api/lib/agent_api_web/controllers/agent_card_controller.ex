defmodule AgentApiWeb.AgentCardController do
  @moduledoc """
  Controller for the A2A Agent Card endpoint.

  The Agent Card is served at `/.well-known/agent.json` and provides
  discovery information for A2A clients.

  ## Comparison with GenServer

  Think of this controller action like a GenServer callback:

      GenServer:  handle_call(:get_state, from, state) → {:reply, state, state}
      Controller: show(conn, params) → json(conn, agent_card)

  Both:
  - Receive a request (message or HTTP)
  - Process it
  - Return a response

  The difference is the transport layer (Erlang messages vs HTTP).
  """
  use AgentApiWeb, :controller

  alias AgentApi.A2A.AgentCard

  @doc """
  Returns the Agent Card as JSON.

  The Agent Card contains:
  - name: Human-readable agent name
  - version: Agent version
  - url: Base URL for the agent
  - capabilities: What the agent supports
  - skills: List of actions the agent can perform

  ## Example Response

      {
        "name": "Elixir Agent Framework",
        "version": "0.1.0",
        "url": "http://localhost:4000",
        "capabilities": {
          "streaming": false,
          "pushNotifications": false
        },
        "skills": [
          {"id": "search", "name": "Search", ...},
          {"id": "analyze", "name": "Analyze", ...}
        ]
      }

  """
  def show(conn, _params) do
    # Build the base URL from the request
    base_url = build_base_url(conn)

    # Generate the Agent Card
    card = AgentCard.build(base_url)

    # Return as JSON
    json(conn, card)
  end

  # ============================================
  # Private Functions
  # ============================================

  # Build the base URL from the connection
  defp build_base_url(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = conn.host
    port = conn.port

    # Only include port if non-standard
    if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
