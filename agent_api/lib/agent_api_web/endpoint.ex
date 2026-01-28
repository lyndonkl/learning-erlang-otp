defmodule AgentApiWeb.Endpoint do
  @moduledoc """
  The Phoenix Endpoint for AgentApi.

  This is the entry point for all HTTP requests. The request flows:

      HTTP Request
           │
           ▼
      ┌─────────┐
      │Endpoint │ ← You are here
      └────┬────┘
           │
           ▼
      ┌─────────┐
      │ Router  │
      └────┬────┘
           │
           ▼
      ┌─────────┐
      │Pipeline │ (Plugs)
      └────┬────┘
           │
           ▼
      ┌──────────┐
      │Controller│
      └──────────┘
  """
  use Phoenix.Endpoint, otp_app: :agent_api

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_agent_api_key",
    signing_salt: "agent_api_signing_salt",
    same_site: "Lax"
  ]

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug AgentApiWeb.Router
end
