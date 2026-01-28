defmodule AgentFramework.Message do
  @moduledoc """
  Structured message type for agent communication.

  Messages have:
  - type: :task | :response | :error
  - id: unique identifier
  - payload: message data
  - timestamp: when created
  """

  @enforce_keys [:type, :id]
  defstruct [:type, :id, :payload, :timestamp]

  @type t :: %__MODULE__{
          type: :task | :response | :error,
          id: String.t(),
          payload: any(),
          timestamp: DateTime.t() | nil
        }

  @doc """
  Create a new message with auto-timestamp.

  ## Examples

      iex> msg = AgentFramework.Message.new(:task, "001", %{action: :search})
      iex> msg.type
      :task
      iex> msg.id
      "001"
  """
  def new(type, id, payload \\ nil) do
    %__MODULE__{
      type: type,
      id: id,
      payload: payload,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Create a task message.

  ## Examples

      iex> msg = AgentFramework.Message.task("001", :search, %{query: "Elixir"})
      iex> msg.type
      :task
      iex> msg.payload.action
      :search
  """
  def task(id, action, params \\ %{}) do
    new(:task, id, %{action: action, params: params})
  end

  @doc """
  Create a response message.

  ## Examples

      iex> msg = AgentFramework.Message.response("001", {:ok, "done"})
      iex> msg.type
      :response
  """
  def response(id, result) do
    new(:response, id, result)
  end

  @doc """
  Create an error message.

  ## Examples

      iex> msg = AgentFramework.Message.error("001", :timeout)
      iex> msg.type
      :error
      iex> msg.payload
      :timeout
  """
  def error(id, reason) do
    new(:error, id, reason)
  end
end
