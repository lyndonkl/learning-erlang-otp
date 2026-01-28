defmodule AgentApiWeb.A2AControllerTest do
  use AgentApiWeb.ConnCase

  alias AgentApi.A2A.TaskManager

  # Start a test agent before each test that needs it
  setup do
    # Ensure the supervisor is running
    # The agent_framework application should start it
    :ok
  end

  describe "POST /a2a - JSON-RPC parsing" do
    test "rejects invalid JSON-RPC (missing jsonrpc)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{"method" => "ListAgents", "id" => 1})

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32600
      assert response["error"]["message"] == "Invalid Request"
    end

    test "rejects invalid JSON-RPC (wrong version)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{"jsonrpc" => "1.0", "method" => "ListAgents", "id" => 1})

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32600
    end

    test "returns method not found for unknown methods", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "UnknownMethod",
          "params" => %{},
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32601
      assert String.contains?(response["error"]["message"], "UnknownMethod")
    end
  end

  describe "POST /a2a - ListAgents" do
    test "returns list of agents", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "ListAgents",
          "params" => %{},
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert is_list(response["result"]["agents"])
      assert is_integer(response["result"]["count"])
    end
  end

  describe "POST /a2a - StartAgent" do
    test "starts a new agent", %{conn: conn} do
      agent_name = "Test-Agent-#{System.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "StartAgent",
          "params" => %{"name" => agent_name},
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["result"]["status"] == "started"
      assert response["result"]["agent"] == agent_name

      # Verify agent exists
      assert TaskManager.agent_exists?(agent_name)
    end

    test "returns invalid params without name", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "StartAgent",
          "params" => %{},
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32602
    end
  end

  describe "POST /a2a - SendMessage" do
    setup %{conn: conn} do
      agent_name = "Worker-#{System.unique_integer([:positive])}"
      {:ok, _pid} = TaskManager.start_agent(agent_name)
      {:ok, conn: conn, agent: agent_name}
    end

    test "sends task to agent", %{conn: conn, agent: agent} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "SendMessage",
          "params" => %{
            "agent" => agent,
            "action" => "search",
            "params" => %{"query" => "test"}
          },
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["result"]["status"] == "created"
      assert response["result"]["agent"] == agent
    end

    test "returns agent not found for missing agent", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "SendMessage",
          "params" => %{
            "agent" => "NonExistent-Agent",
            "action" => "search",
            "params" => %{}
          },
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32001
    end

    test "returns invalid params without required fields", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "SendMessage",
          "params" => %{"agent" => "Worker-1"},
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32602
    end
  end

  describe "POST /a2a - GetAgentState" do
    setup %{conn: conn} do
      agent_name = "Worker-#{System.unique_integer([:positive])}"
      {:ok, _pid} = TaskManager.start_agent(agent_name)
      {:ok, conn: conn, agent: agent_name}
    end

    test "returns agent state", %{conn: conn, agent: agent} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "GetAgentState",
          "params" => %{"agent" => agent},
          "id" => 1
        })

      response = json_response(conn, 200)
      result = response["result"]

      assert result["name"] == agent
      assert result["status"] == "idle"
      assert is_integer(result["inbox_count"])
      assert is_integer(result["processed_count"])
    end

    test "returns agent not found for missing agent", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "GetAgentState",
          "params" => %{"agent" => "NonExistent"},
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32001
    end
  end

  describe "POST /a2a - ProcessNext" do
    setup %{conn: conn} do
      agent_name = "Worker-#{System.unique_integer([:positive])}"
      {:ok, _pid} = TaskManager.start_agent(agent_name)
      {:ok, conn: conn, agent: agent_name}
    end

    test "returns empty when no tasks", %{conn: conn, agent: agent} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "ProcessNext",
          "params" => %{"agent" => agent},
          "id" => 1
        })

      response = json_response(conn, 200)
      assert response["result"]["status"] == "empty"
    end

    test "processes task and returns result", %{conn: conn, agent: agent} do
      # First send a task
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/a2a", %{
        "jsonrpc" => "2.0",
        "method" => "SendMessage",
        "params" => %{"agent" => agent, "action" => "search", "params" => %{"query" => "test"}},
        "id" => 1
      })

      # Give cast time to process
      Process.sleep(50)

      # Then process it
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/a2a", %{
          "jsonrpc" => "2.0",
          "method" => "ProcessNext",
          "params" => %{"agent" => agent},
          "id" => 2
        })

      response = json_response(conn, 200)
      assert response["result"]["status"] == "completed"
      assert response["result"]["agent"] == agent
    end
  end
end
