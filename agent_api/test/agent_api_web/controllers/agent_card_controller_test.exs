defmodule AgentApiWeb.AgentCardControllerTest do
  use AgentApiWeb.ConnCase

  describe "GET /.well-known/agent.json" do
    test "returns valid Agent Card", %{conn: conn} do
      conn = get(conn, "/.well-known/agent.json")

      assert json_response(conn, 200)

      response = json_response(conn, 200)
      assert response["name"] == "Elixir Agent Framework"
      assert response["version"] == "0.1.0"
      assert is_binary(response["url"])
      assert is_map(response["capabilities"])
      assert is_list(response["skills"])
    end

    test "includes required capabilities", %{conn: conn} do
      conn = get(conn, "/.well-known/agent.json")
      response = json_response(conn, 200)

      capabilities = response["capabilities"]
      assert Map.has_key?(capabilities, "streaming")
      assert Map.has_key?(capabilities, "pushNotifications")
    end

    test "includes expected skills", %{conn: conn} do
      conn = get(conn, "/.well-known/agent.json")
      response = json_response(conn, 200)

      skills = response["skills"]
      skill_ids = Enum.map(skills, & &1["id"])

      assert "search" in skill_ids
      assert "analyze" in skill_ids
      assert "summarize" in skill_ids
    end

    test "each skill has required fields", %{conn: conn} do
      conn = get(conn, "/.well-known/agent.json")
      response = json_response(conn, 200)

      for skill <- response["skills"] do
        assert Map.has_key?(skill, "id")
        assert Map.has_key?(skill, "name")
        assert Map.has_key?(skill, "description")
        assert Map.has_key?(skill, "inputSchema")
      end
    end
  end
end
