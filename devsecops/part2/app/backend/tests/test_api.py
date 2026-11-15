def test_health_reports_database_connection(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {
        "status": "healthy",
        "database": "connected",
    }


def test_api_status_endpoint(client):
    response = client.get("/api")

    assert response.status_code == 200
    assert response.get_json() == {
        "status": "healthy",
        "message": "API is operational",
    }


def test_topic_create_and_list_round_trip(client):
    topic = {
        "name": "Containers",
        "description": "Container fundamentals",
        "slug": "containers",
    }

    created = client.post("/api/topics", json=topic)
    listed = client.get("/api/topics")

    assert created.status_code == 201
    assert created.get_json()["id"] == "containers"
    assert listed.status_code == 200
    assert listed.get_json() == [
        {
            "id": "containers",
            "title": "Containers",
            "description": "Container fundamentals",
            "question_count": 0,
        }
    ]


def test_topic_create_rejects_missing_fields(client):
    response = client.post("/api/topics", json={"name": "Incomplete"})

    assert response.status_code == 400
    assert response.get_json() == {"error": "Missing required fields"}


def test_quiz_start_rejects_missing_player_name(client):
    response = client.post("/api/quiz/containers/start", json={})

    assert response.status_code == 400
    assert "player" in response.get_json()["error"].lower()


def test_quiz_submit_rejects_incomplete_payload(client):
    response = client.post("/api/quiz/submit", json={"answers": {"1": 0}})

    assert response.status_code == 400
    assert response.get_json() == {"error": "session_id and answers are required"}
