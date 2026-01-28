defmodule AgentApi.A2A.AgentCard do
  @moduledoc """
  Agent Card data structure for A2A protocol discovery.

  The Agent Card is served at `/.well-known/agent.json` and tells other
  agents WHO this agent is and WHAT it can do.

  ## A2A Specification

  According to the A2A protocol, an Agent Card contains:
  - name: Human-readable name
  - version: Agent version
  - url: Base URL for the agent
  - capabilities: What the agent supports (streaming, push notifications)
  - skills: List of actions the agent can perform

  ## Example

      iex> AgentCard.build("http://localhost:4000")
      %{
        name: "Elixir Agent Framework",
        version: "0.1.0",
        url: "http://localhost:4000",
        capabilities: %{streaming: false, pushNotifications: false},
        skills: [...]
      }

  """

  @doc """
  Build an Agent Card with the given base URL.

  ## Options
  - `:name` - Agent name (default: "Elixir Agent Framework")
  - `:version` - Agent version (default: "0.1.0")
  - `:skills` - List of skill maps (default: built-in skills)
  """
  @spec build(String.t(), keyword()) :: map()
  def build(base_url, opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "Elixir Agent Framework"),
      version: Keyword.get(opts, :version, "0.1.0"),
      url: base_url,
      capabilities: %{
        streaming: false,
        pushNotifications: false
      },
      skills: Keyword.get(opts, :skills, default_skills())
    }
  end

  @doc """
  Returns the default skills available in the AgentFramework.

  These correspond to the task handlers in AgentServer:
  - search: Search for information
  - analyze: Analyze provided data
  - summarize: Summarize text content
  """
  @spec default_skills() :: [map()]
  def default_skills do
    [
      %{
        id: "search",
        name: "Search",
        description: "Search for information based on a query",
        inputSchema: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "The search query"}
          },
          required: ["query"]
        }
      },
      %{
        id: "analyze",
        name: "Analyze",
        description: "Analyze provided data and return insights",
        inputSchema: %{
          type: "object",
          properties: %{
            data: %{type: "string", description: "The data to analyze"}
          },
          required: ["data"]
        }
      },
      %{
        id: "summarize",
        name: "Summarize",
        description: "Summarize text content",
        inputSchema: %{
          type: "object",
          properties: %{
            text: %{type: "string", description: "The text to summarize"}
          },
          required: ["text"]
        }
      }
    ]
  end
end
