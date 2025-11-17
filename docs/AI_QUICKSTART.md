# AI System Quick Start Guide

## Quick Setup (5 Minutes)

### 1. Enable AI Features

Edit `group_vars/all/main.yml`:

```yaml
voice_assistant:
  enabled: true

rag:
  enabled: true

task_scheduler:
  enabled: true
```

### 2. Deploy

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

### 3. Load Your Documents

```bash
# SSH to your Pi
ssh pi@frey.local

# Copy documents to knowledge directory
sudo mkdir -p /opt/frey/appdata/knowledge
sudo cp ~/my-travel-guides/*.pdf /opt/frey/appdata/knowledge/

# Ingest documents
docker exec -it rag-service python3 /app/ingest_documents.py
```

## Using Voice Commands

### System Control
- "Hey Nabu, start Jellyfin"
- "Hey Nabu, list all services"
- "Hey Nabu, what's the system status?"

### Knowledge Queries (RAG)
- "Hey Nabu, what are the best restaurants in Tokyo?"
- "Hey Nabu, tell me about visiting Iceland"

## Queueing Overnight Tasks

```bash
# Create task file
cat > /opt/frey/appdata/task-queue/pending_mytask.json << 'EOF'
{
  "type": "research",
  "prompt": "Your complex reasoning task here...",
  "created_at": "2025-11-17T10:00:00"
}
EOF

# Check in the morning
cat /opt/frey/appdata/task-queue/completed_mytask.json
```

## Quick Checks

```bash
# Are services running?
docker ps | grep -E 'ollama|rag-service|task-scheduler'

# What models are loaded?
curl -s http://ollama.frey:11434/api/ps | jq

# What's in my knowledge base?
curl -s http://rag-service:8001/collections | jq

# Test RAG query
curl -X POST http://rag-service:8001/query \
  -H 'Content-Type: application/json' \
  -d '{"query": "test question", "collection": "travel_guides"}' | jq
```

## Memory Usage At A Glance

| Time | Mode | Model Loaded | RAM Usage |
|------|------|--------------|-----------|
| Day | Voice + RAG | llama3.2:3b | ~6.6GB |
| Night (11PM-7AM) | Reasoning | qwen2.5:14b | ~12.2GB |

**Key principle**: Only ONE model in RAM at a time ✅

## Common Issues

**"Voice assistant not responding"**
```bash
docker restart ollama homeassistant
```

**"RAG returns no information"**
```bash
# Re-ingest documents
docker exec -it rag-service python3 /app/ingest_documents.py
```

**"Overnight tasks not running"**
```bash
# Check scheduler logs
docker logs task-scheduler

# Verify it's quiet hours (11 PM - 7 AM)
date
```

## Full Documentation

- Architecture details: [AI_ARCHITECTURE.md](AI_ARCHITECTURE.md)
- Voice assistant setup: [VOICE_ASSISTANT.md](VOICE_ASSISTANT.md)
- Voice assistant quickstart: [VOICE_ASSISTANT_QUICKSTART.md](VOICE_ASSISTANT_QUICKSTART.md)
