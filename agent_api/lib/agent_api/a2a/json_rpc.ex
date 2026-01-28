defmodule AgentApi.A2A.JsonRpc do
  @moduledoc """
  JSON-RPC 2.0 parsing and encoding for A2A protocol.

  The A2A protocol uses JSON-RPC 2.0 as its transport format.
  This module handles parsing incoming requests and building responses.

  ## JSON-RPC 2.0 Format

  ### Request
      {
        "jsonrpc": "2.0",
        "method": "SendMessage",
        "params": {...},
        "id": 1
      }

  ### Success Response
      {
        "jsonrpc": "2.0",
        "result": {...},
        "id": 1
      }

  ### Error Response
      {
        "jsonrpc": "2.0",
        "error": {"code": -32600, "message": "Invalid Request"},
        "id": 1
      }

  ## Error Codes

  - `-32700` - Parse error
  - `-32600` - Invalid Request
  - `-32601` - Method not found
  - `-32602` - Invalid params
  - `-32603` - Internal error

  """

  @type request :: %{
          jsonrpc: String.t(),
          method: String.t(),
          params: map(),
          id: integer() | String.t() | nil
        }

  @type response :: %{
          jsonrpc: String.t(),
          result: any(),
          id: integer() | String.t() | nil
        }

  @type error_response :: %{
          jsonrpc: String.t(),
          error: %{code: integer(), message: String.t(), data: any()},
          id: integer() | String.t() | nil
        }

  # Standard JSON-RPC error codes
  @error_parse -32700
  @error_invalid_request -32600
  @error_method_not_found -32601
  @error_invalid_params -32602
  @error_internal -32603

  # A2A specific error codes
  @error_agent_not_found -32001
  @error_task_not_found -32002

  @doc """
  Parse a JSON-RPC request from params.

  Returns `{:ok, request}` or `{:error, error_response}`.
  """
  @spec parse(map()) :: {:ok, request()} | {:error, error_response()}
  def parse(%{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id})
      when is_binary(method) and is_map(params) do
    {:ok, %{jsonrpc: "2.0", method: method, params: params, id: id}}
  end

  def parse(%{"jsonrpc" => "2.0", "method" => method, "id" => id})
      when is_binary(method) do
    {:ok, %{jsonrpc: "2.0", method: method, params: %{}, id: id}}
  end

  def parse(%{"jsonrpc" => "2.0", "method" => method, "params" => params})
      when is_binary(method) and is_map(params) do
    # Notification (no id) - still valid
    {:ok, %{jsonrpc: "2.0", method: method, params: params, id: nil}}
  end

  def parse(%{"id" => id}) do
    {:error, error(@error_invalid_request, "Invalid Request", nil, id)}
  end

  def parse(_) do
    {:error, error(@error_invalid_request, "Invalid Request", nil, nil)}
  end

  @doc """
  Build a success response.
  """
  @spec success(any(), integer() | String.t() | nil) :: response()
  def success(result, id) do
    %{jsonrpc: "2.0", result: result, id: id}
  end

  @doc """
  Build an error response.
  """
  @spec error(integer(), String.t(), any(), integer() | String.t() | nil) :: error_response()
  def error(code, message, data \\ nil, id) do
    error_obj =
      if data do
        %{code: code, message: message, data: data}
      else
        %{code: code, message: message}
      end

    %{jsonrpc: "2.0", error: error_obj, id: id}
  end

  # Convenience error constructors

  @doc "Build a 'Parse error' response."
  def parse_error(id \\ nil), do: error(@error_parse, "Parse error", nil, id)

  @doc "Build an 'Invalid Request' response."
  def invalid_request(id \\ nil), do: error(@error_invalid_request, "Invalid Request", nil, id)

  @doc "Build a 'Method not found' response."
  def method_not_found(method, id),
    do: error(@error_method_not_found, "Method not found: #{method}", nil, id)

  @doc "Build an 'Invalid params' response."
  def invalid_params(details, id),
    do: error(@error_invalid_params, "Invalid params", details, id)

  @doc "Build an 'Internal error' response."
  def internal_error(details \\ nil, id),
    do: error(@error_internal, "Internal error", details, id)

  @doc "Build an 'Agent not found' response."
  def agent_not_found(agent_name, id),
    do: error(@error_agent_not_found, "Agent not found: #{agent_name}", nil, id)

  @doc "Build a 'Task not found' response."
  def task_not_found(task_id, id),
    do: error(@error_task_not_found, "Task not found: #{task_id}", nil, id)
end
