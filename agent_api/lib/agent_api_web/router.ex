defmodule AgentApiWeb.Router do
  @moduledoc """
  Router for AgentApi.

  Defines the routes for A2A protocol endpoints:

  - `GET /.well-known/agent.json` - Agent Card for discovery
  - `POST /a2a` - JSON-RPC endpoint for agent interaction

  ## Request Flow

      Request: GET /.well-known/agent.json
           │
           ▼
      pipe_through :api
           │
           ▼
      AgentCardController.show/2
           │
           ▼
      Response: Agent Card JSON

  """
  use AgentApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AgentApiWeb do
    pipe_through :api

    # A2A Agent Card endpoint (discovery)
    get "/.well-known/agent.json", AgentCardController, :show

    # A2A JSON-RPC endpoint
    post "/a2a", A2AController, :handle
  end

  # Health check endpoint
  scope "/health", AgentApiWeb do
    pipe_through :api
    get "/", HealthController, :index
  end
end
