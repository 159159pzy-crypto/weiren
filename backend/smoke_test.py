from __future__ import annotations

from fastapi.testclient import TestClient

from backend.main import DB_PATH, app


def main() -> None:
    client = TestClient(app)
    health = client.get("/health")
    assert health.status_code == 200, health.text
    payload = {
        "session_id": "backend-smoke",
        "character_id": "anon",
        "character_name": "千早爱音",
        "current_form": "anon",
        "true_role": "fake",
        "location": "door",
        "day": 2,
        "event_type": "visitor_panic",
        "chase_type": "fake_chased",
        "known_facts": ["红虹膜"],
        "forbidden_facts": ["不要改变身份真相"],
        "personality": ["话多、紧张"],
        "speech_style": "话多、紧张",
        "stress": 80,
        "trust": 40,
        "is_being_chased": False,
        "player_message": "你记得昨天的暗号吗？",
        "candidate_clue": {"title": "记忆漏洞", "text": "她把暗号顺序说反了。"},
    }
    response = client.post("/v1/dialogue", json=payload)
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["clue_triggered"] is True
    for key in ["emotion", "expression", "action", "trust_delta", "stress_delta", "stamina_cost", "suggested_options"]:
        assert key in data, key
    assert isinstance(data["suggested_options"], list)
    assert "暗号" in data["dialogue"]
    logs = client.get("/v1/logs/backend-smoke")
    assert logs.status_code == 200, logs.text
    assert len(logs.json()) >= 1
    summary = client.get("/v1/session/backend-smoke/summary")
    assert summary.status_code == 200, summary.text
    summary_data = summary.json()
    assert summary_data["dialogue_count"] >= 1
    assert summary_data["clue_hits"] >= 1
    assert summary_data["source_counts"].get("fallback", 0) >= 1
    print("BACKEND_SMOKE_OK", health.json()["characters"], DB_PATH.exists(), data["source"])


if __name__ == "__main__":
    main()
