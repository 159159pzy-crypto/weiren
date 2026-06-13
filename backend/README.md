# 猫眼之后 Backend

Local FastAPI backend for dialogue performance and SQLite logging.

The game remains authoritative for truth:

- Godot decides who is human, fake, or mimic.
- Godot decides which clues are real and which ending is reached.
- The backend only turns the current state and player question into in-character dialogue.
- If no LLM API is configured, the backend uses deterministic local fallback text.

## Run

```powershell
cd D:\game
python -m uvicorn backend.main:app --reload --host 127.0.0.1 --port 8787
```

## Optional LLM

Set these environment variables for an OpenAI-compatible chat completion API:

```powershell
$env:LLM_API_KEY="..."
$env:LLM_BASE_URL="https://api.openai.com/v1"
$env:LLM_MODEL="gpt-4.1-mini"
```

If the variables are missing or the request fails, the backend falls back to local text.

## Endpoints

- `GET /health`
- `POST /v1/dialogue`
- `GET /v1/logs/{session_id}`

