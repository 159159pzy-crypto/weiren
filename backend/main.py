from __future__ import annotations

import json
import os
import sqlite3
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Literal

from fastapi import FastAPI
from pydantic import BaseModel, Field


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
DB_PATH = ROOT / "backend" / "game_state.sqlite3"

Role = Literal["human", "fake", "mimic"]


class DialogueRequest(BaseModel):
    session_id: str = "local"
    character_id: str
    character_name: str
    current_form: str = ""
    true_role: Role
    location: str = "door"
    day: int = Field(ge=1, le=9)
    event_type: str = ""
    known_facts: list[str] = Field(default_factory=list)
    forbidden_facts: list[str] = Field(default_factory=list)
    personality: list[str] = Field(default_factory=list)
    speech_style: str = ""
    stress: int = Field(default=50, ge=0, le=100)
    trust: int = Field(default=50, ge=0, le=100)
    is_being_chased: bool = False
    player_message: str
    candidate_clue: dict[str, Any] | None = None


class DialogueResponse(BaseModel):
    dialogue: str
    emotion: str
    expression: str
    action: str
    clue_triggered: bool = False
    clue_id: str | None = None
    trust_delta: int = 0
    stress_delta: int = 0
    stamina_cost: int = 1
    suggested_options: list[str] = Field(default_factory=list)
    source: str = "fallback"


app = FastAPI(title="猫眼之后 Backend", version="0.1.0")


def _load_characters() -> dict[str, dict[str, Any]]:
    path = DATA_DIR / "characters.json"
    if not path.exists():
        return {}
    rows = json.loads(path.read_text(encoding="utf-8"))
    return {row["id"]: row for row in rows}


CHARACTERS = _load_characters()


def _db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS dialogue_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            session_id TEXT NOT NULL,
            day INTEGER NOT NULL,
            character_id TEXT NOT NULL,
            true_role TEXT NOT NULL,
            player_message TEXT NOT NULL,
            response_json TEXT NOT NULL
        )
        """
    )
    return conn


def _log_dialogue(request: DialogueRequest, response: DialogueResponse) -> None:
    with _db() as conn:
        conn.execute(
            """
            INSERT INTO dialogue_log (
                created_at, session_id, day, character_id, true_role, player_message, response_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                time.time(),
                request.session_id,
                request.day,
                request.character_id,
                request.true_role,
                request.player_message,
                response.model_dump_json(ensure_ascii=False),
            ),
        )


def _system_prompt() -> str:
    return (
        "你是《猫眼之后》的角色表演后端。系统真相已经由游戏决定。"
        "你只能表演角色语气、恐惧反应、撒谎方式、情绪变化和诱导话术。"
        "禁止改变 true_role，禁止决定谁死亡，禁止创造新的真实线索，禁止泄露 forbidden_facts。"
        "必须输出严格 JSON，字段为 dialogue, emotion, expression, action, clue_triggered, "
        "clue_id, trust_delta, stress_delta, stamina_cost, suggested_options。"
    )


def _llm_response(request: DialogueRequest) -> DialogueResponse | None:
    api_key = os.environ.get("LLM_API_KEY")
    base_url = os.environ.get("LLM_BASE_URL", "https://api.openai.com/v1").rstrip("/")
    model = os.environ.get("LLM_MODEL", "gpt-4.1-mini")
    if not api_key:
        return None

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": _system_prompt()},
            {
                "role": "user",
                "content": json.dumps(request.model_dump(), ensure_ascii=False),
            },
        ],
        "temperature": 0.8,
        "response_format": {"type": "json_object"},
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{base_url}/chat/completions",
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            body = json.loads(resp.read().decode("utf-8"))
        content = body["choices"][0]["message"]["content"]
        parsed = json.loads(content)
        parsed["source"] = "llm"
        return DialogueResponse(**parsed)
    except (urllib.error.URLError, KeyError, ValueError, TypeError):
        return None


def _fallback_response(request: DialogueRequest) -> DialogueResponse:
    char = CHARACTERS.get(request.character_id, {})
    short = char.get("short") or request.character_name
    clue = request.candidate_clue or {}
    clue_text = clue.get("text", "")
    clue_title = clue.get("title")
    clue_triggered = bool(clue_title)

    if request.true_role == "human":
        if clue_triggered:
            dialogue = f"你问得太细了……可是对，{clue_text}"
            emotion = "紧张"
            action = "她把手贴在门边，呼吸是真的乱了。"
            trust_delta = -1
            stress_delta = 4
        elif request.is_being_chased:
            dialogue = "我知道你会怀疑。那就先开隔离区，别直接开内门。后面的声音真的在靠近。"
            emotion = "恐慌"
            action = "她回头看了一眼，声音压低到几乎断掉。"
            trust_delta = -2
            stress_delta = 7
        else:
            dialogue = f"我是{short}。你可以继续问，但不要把每个害怕的人都当成怪物。"
            emotion = "不安"
            action = "她没有靠近猫眼，只是等你下一句话。"
            trust_delta = 0
            stress_delta = 3
    elif request.true_role == "mimic":
        if clue_triggered:
            dialogue = f"“{request.player_message}。”她先重复了一遍问题。{clue_text}"
            emotion = "空白"
            action = "她的回答慢了半拍，像在等待某个看不见的提示。"
            trust_delta = -3
            stress_delta = 1
        else:
            dialogue = f"我是{short}。如果你需要证据，我可以给你证据。你想听哪一种？"
            emotion = "平静"
            action = "她的眼睛没有离开猫眼，呼吸几乎听不见。"
            trust_delta = -2
            stress_delta = 0
    else:
        if clue_triggered:
            dialogue = f"这不重要。你看错了，或者有人想让你这样想。{clue_text}"
            emotion = "急躁"
            action = "她回答得太快，快得像提前背过。"
            trust_delta = -2
            stress_delta = 2
        else:
            dialogue = "别浪费时间。你越问，外面就越有时间靠近。"
            emotion = "催促"
            action = "她用指节轻敲门板，节奏重复得过分整齐。"
            trust_delta = -1
            stress_delta = 2

    return DialogueResponse(
        dialogue=dialogue,
        emotion=emotion,
        expression=emotion,
        action=action,
        clue_triggered=clue_triggered,
        clue_id=clue_title,
        trust_delta=trust_delta,
        stress_delta=stress_delta,
        stamina_cost=1,
        suggested_options=["问今日暗号", "进行生理检查", "放入隔离区"],
        source="fallback",
    )


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "characters": len(CHARACTERS),
        "db": str(DB_PATH),
        "llm_configured": bool(os.environ.get("LLM_API_KEY")),
    }


@app.post("/v1/dialogue")
def dialogue(request: DialogueRequest) -> DialogueResponse:
    response = _llm_response(request) or _fallback_response(request)
    _log_dialogue(request, response)
    return response


@app.get("/v1/logs/{session_id}")
def logs(session_id: str) -> list[dict[str, Any]]:
    with _db() as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT created_at, session_id, day, character_id, true_role, player_message, response_json
            FROM dialogue_log
            WHERE session_id = ?
            ORDER BY id DESC
            LIMIT 50
            """,
            (session_id,),
        ).fetchall()
    result = []
    for row in rows:
        item = dict(row)
        item["response"] = json.loads(item.pop("response_json"))
        result.append(item)
    return result


@app.get("/v1/session/{session_id}/summary")
def session_summary(session_id: str) -> dict[str, Any]:
    rows = logs(session_id)
    source_counts: dict[str, int] = {}
    character_ids: set[str] = set()
    days: list[int] = []
    clue_hits = 0
    for row in rows:
        character_ids.add(str(row.get("character_id", "")))
        days.append(int(row.get("day", 0)))
        response = row.get("response", {})
        source = str(response.get("source", "unknown"))
        source_counts[source] = source_counts.get(source, 0) + 1
        if bool(response.get("clue_triggered", False)):
            clue_hits += 1
    return {
        "session_id": session_id,
        "dialogue_count": len(rows),
        "day_min": min(days) if days else None,
        "day_max": max(days) if days else None,
        "character_count": len(character_ids),
        "source_counts": source_counts,
        "clue_hits": clue_hits,
        "recent": rows[:5],
    }
