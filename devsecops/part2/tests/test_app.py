def test_health(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"


def test_homepage(client):
    response = client.get("/")

    assert response.status_code == 200
    assert b"DevOps Quest" in response.data


def test_list_challenges_hides_answers(client):
    response = client.get("/api/challenges?player_id=1")

    assert response.status_code == 200
    assert len(response.get_json()) == 8
    assert "answer" not in response.get_json()[0]


def test_create_player(client):
    response = client.post(
        "/api/players", json={"username": "pipeline_panda", "avatar": "🐼"}
    )

    assert response.status_code == 201
    assert response.get_json()["username"] == "pipeline_panda"
    assert response.get_json()["level"] == 1


def test_rejects_invalid_player(client):
    response = client.post("/api/players", json={"username": "x"})

    assert response.status_code == 400


def test_rejects_duplicate_player(client):
    response = client.post("/api/players", json={"username": "demo"})

    assert response.status_code == 409


def test_correct_answer_awards_xp_once(client):
    first = client.post(
        "/api/challenges/docker-detective/submit",
        json={"player_id": 1, "answer": "USER"},
    )
    second = client.post(
        "/api/challenges/docker-detective/submit",
        json={"player_id": 1, "answer": "USER"},
    )

    assert first.status_code == 200
    assert first.get_json()["correct"] is True
    assert first.get_json()["earned_xp"] == 40
    assert second.get_json()["earned_xp"] == 0


def test_wrong_answer_costs_energy(client):
    response = client.post(
        "/api/challenges/docker-detective/submit",
        json={"player_id": 1, "answer": "EXPOSE"},
    )

    assert response.status_code == 200
    assert response.get_json()["correct"] is False
    assert response.get_json()["player"]["energy"] == 4


def test_missing_challenge_returns_404(client):
    response = client.post(
        "/api/challenges/not-real/submit",
        json={"player_id": 1, "answer": "anything"},
    )

    assert response.status_code == 404


def test_daily_spin_awards_xp(client):
    response = client.post("/api/players/1/spin")

    assert response.status_code == 200
    assert response.get_json()["reward"] in [5, 10, 15, 25, 50]


def test_leaderboard_contains_demo_player(client):
    response = client.get("/api/leaderboard")

    assert response.status_code == 200
    assert response.get_json()[0]["username"] == "demo"


def test_token_is_issued(client):
    response = client.post("/api/players/1/token")

    assert response.status_code == 200
    assert response.get_json()["token"]


def test_metrics_are_exposed(client):
    response = client.get("/metrics")

    assert response.status_code == 200
    assert b"devops_quest_requests_total" in response.data
