defmodule AgentApiWeb.HealthController do
  @moduledoc """
  Health check controller for operational monitoring.
  """
  use AgentApiWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end
