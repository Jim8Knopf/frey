# AI System Quick Start Guide

## Overview

The Frey AI system is **fully automated via Infrastructure as Code** - no manual configuration needed!

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

### 2. Deploy (Automated IaC)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

**What this does automatically:**
- ✅ Deploys all Docker containers (Home Assistant, Ollama, Whisper, Piper, OpenWakeWord)
- ✅ Configures Home Assistant with complete voice pipeline
- ✅ Sets up Ollama conversation agent with function calling
- ✅ Pulls all required AI models (llama3.2:3b, nomic-embed-text, qwen2.5:14b)
- ✅ Deploys RAG service and task scheduler
- ✅ Configures shell commands and scripts
- ✅ **Everything ready to use - no manual UI configuration!**

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

## Advanced: Fine-Tune Your Own Model

Want even better performance? Fine-tune a larger model (7B-13B) on a GPU machine, then deploy it quantized to your Pi!

**Why fine-tune?**
- ✅ Use bigger models (8B) that still fit in Pi RAM when quantized
- ✅ Specialize for your exact commands and services
- ✅ Better accuracy than stock 3B models
- ✅ One-time cost: $0.15-$0.50 (GPU rental)

**Quick example:**
```bash
# On GPU machine
python3 scripts/finetune/finetune_frey_model.py \
  --model llama-3.1-8b \
  --dataset my_commands.jsonl \
  --quantization q4_k_m

# Transfer to Pi
scp frey-finetuned/gguf/*.gguf pi@frey.local:~/

# Import and use
docker exec ollama ollama create frey-assistant:q4 -f ~/Modelfile
```

**See**: [MODEL_FINETUNING.md](MODEL_FINETUNING.md) for complete guide

## Full Documentation

- **IaC setup guide**: [VOICE_ASSISTANT_IAC.md](VOICE_ASSISTANT_IAC.md) ⭐ **Start here for automated setup**
- **Fine-tuning guide**: [MODEL_FINETUNING.md](MODEL_FINETUNING.md) 🚀 **Advanced: Custom models**
- Architecture details: [AI_ARCHITECTURE.md](AI_ARCHITECTURE.md)
- Voice assistant setup: [VOICE_ASSISTANT.md](VOICE_ASSISTANT.md)
- Voice assistant quickstart: [VOICE_ASSISTANT_QUICKSTART.md](VOICE_ASSISTANT_QUICKSTART.md)
