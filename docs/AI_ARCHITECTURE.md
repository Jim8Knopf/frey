# Frey AI Architecture - Multi-Modal Intelligence System

## Overview

Frey implements a memory-efficient multi-modal AI architecture designed specifically for Raspberry Pi 5 with 16GB RAM. The system provides three distinct AI capabilities while staying within memory constraints by using smart model loading.

## Architecture Philosophy

**Challenge**: Running multiple AI models simultaneously would exceed available memory (16GB RAM).

**Solution**: Smart model loading - Ollama automatically loads and unloads models as needed, keeping only ONE model in RAM at a time.

## Three AI Modes

### 1. Fast Voice Responses (Real-time)
- **Model**: llama3.2:3b (~2.2GB RAM)
- **Purpose**: Quick responses to voice commands (1-2 seconds)
- **Use Cases**:
  - "Start Jellyfin"
  - "What services are running?"
  - "Restart Sonarr"
  - General conversation and system control
- **Keep Alive**: 10 minutes (stays loaded for quick consecutive commands)

### 2. RAG Knowledge Base (Low Hallucination)
- **Model**: Same llama3.2:3b + nomic-embed-text (~2.4GB total)
- **Purpose**: Accurate answers from your documents
- **Use Cases**:
  - "What are the best restaurants in Tokyo?" (from travel guides)
  - "Tell me about visiting Iceland"
  - Any factual questions from ingested documents
- **Hallucination**: Very low - only answers from document context
- **Keep Alive**: 10 minutes

### 3. Complex Overnight Tasks (Deep Reasoning)
- **Model**: qwen2.5:14b (~8GB RAM)
- **Purpose**: Complex reasoning tasks during quiet hours
- **Use Cases**:
  - Research and analysis tasks
  - Complex planning and reasoning
  - Long-form content generation
- **Schedule**: Runs during quiet hours (default: 11 PM - 7 AM)
- **Keep Alive**: 0 (unloads immediately after task completion)

## Memory Budget

### Daytime Operation (Voice + RAG)
- llama3.2:3b: ~2.2GB
- nomic-embed-text: ~140MB
- ChromaDB: ~200MB
- RAG service: ~150MB
- System overhead: ~4GB
- **Total: ~6.6GB** ✅ Well within budget

### Nighttime Operation (Overnight Tasks)
- qwen2.5:14b: ~8GB
- Task scheduler: ~100MB
- System overhead: ~4GB
- **Total: ~12.2GB** ✅ Acceptable during quiet hours
- **Note**: Voice assistant becomes unavailable during reasoning tasks (acceptable at night)

## Smart Model Loading

Ollama is configured with strict memory limits:

```yaml
environment:
  - OLLAMA_NUM_PARALLEL=1           # Only 1 request at a time
  - OLLAMA_MAX_LOADED_MODELS=1      # Only 1 model in RAM
  - OLLAMA_KEEP_ALIVE=10m           # Keep model for 10 min after last use
  - OLLAMA_NUM_THREAD=8             # Use all Pi 5 cores
  - OLLAMA_NUM_CTX=4096             # 4K context window
```

**How it works**:
1. Voice command arrives → llama3.2:3b loads (if not already loaded)
2. User asks RAG question → Same model still loaded, switches to RAG context
3. 10 minutes of no activity → Model unloads from RAM
4. Nighttime quiet hours → qwen2.5:14b loads for complex tasks
5. Morning arrives → Reasoning model unloads, voice assistant available again

## Component Architecture

### Core Services

```
┌─────────────────────────────────────────────────────────────┐
│                         Ollama                              │
│              (Smart Model Loading Controller)               │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ llama3.2:3b  │  │nomic-embed   │  │qwen2.5:14b   │      │
│  │ (Primary)    │  │(Embeddings)  │  │(Reasoning)   │      │
│  │ 2.2GB        │  │140MB         │  │8GB           │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
│  Only ONE model loaded at a time (OLLAMA_MAX_LOADED_MODELS=1)│
└─────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
         ┌──────────▼─────────┐  ┌─────────▼──────────┐
         │  Home Assistant    │  │   RAG Service      │
         │  Voice Assistant   │  │   (Port 8001)      │
         │                    │  │                    │
         │  • Whisper (STT)   │  │  • ChromaDB        │
         │  • Piper (TTS)     │  │  • Document Query  │
         │  • OpenWakeWord    │  │  • Low hallucination│
         └────────────────────┘  └────────────────────┘

                    ┌──────────────────────┐
                    │  Task Scheduler      │
                    │  (Quiet Hours Only)  │
                    │                      │
                    │  • Queue Management  │
                    │  • 11 PM - 7 AM      │
                    │  • qwen2.5:14b       │
                    └──────────────────────┘
```

### Data Flow

**Voice Command Flow**:
```
User speaks → OpenWakeWord → Whisper (STT) → Ollama (llama3.2:3b) → Piper (TTS) → Audio response
                                                     │
                                                     ├→ frey-docker-control (system control)
                                                     └→ frey_query_knowledge (RAG)
```

**RAG Query Flow**:
```
User question → Ollama (embeddings) → ChromaDB (vector search) → Top 5 docs
                                                                       │
Ollama (llama3.2:3b) ← RAG prompt with context ← Document chunks ─────┘
         │
         └→ Answer (fact-based, low hallucination)
```

**Overnight Task Flow**:
```
Task queued → /queue/pending_*.json
                     │
                     ├→ Quiet hours? → Wait
                     │
                     └→ 11 PM arrives → task-scheduler loads qwen2.5:14b
                                              │
                                              ├→ Process complex reasoning
                                              └→ Save result → /queue/completed_*.json
                                                         │
                                                         └→ Unload model (free RAM)
```

## Configuration

### Enable RAG System

In `group_vars/all/main.yml`:

```yaml
rag:
  enabled: true
  vector_db:
    port: 8000
    persist_directory: "{{ storage.appdata_dir }}/chromadb"
  service:
    port: 8001
  documents:
    chunk_size: 1000
    chunk_overlap: 200
    top_k_results: 5
```

### Enable Task Scheduler

```yaml
task_scheduler:
  enabled: true
  schedule:
    quiet_hours_start: "23:00"
    quiet_hours_end: "07:00"
  limits:
    max_concurrent_tasks: 1
    max_task_duration: "6h"
  queue:
    path: "{{ storage.appdata_dir }}/task-queue"
```

### AI Models Configuration

```yaml
ai_models:
  primary:
    name: "llama3.2:3b"
    size: "~2.2GB RAM"
  reasoning:
    enabled: true
    name: "qwen2.5:14b"
    size: "~8GB RAM"
  embedding:
    name: "nomic-embed-text"
    size: "~140MB RAM"
  ollama:
    num_parallel: 1          # Critical: only 1 model at a time
    max_loaded_models: 1     # Critical: memory limit
    keep_alive: "10m"
    num_thread: 8
    num_ctx: 4096
```

## Usage

### 1. Ingesting Documents for RAG

After deployment, load your documents:

```bash
# SSH into your Pi
ssh pi@frey.local

# Become automation user
sudo su - automation_manager

# Copy your travel guides to the knowledge directory
cp ~/Downloads/japan-guide.pdf /opt/frey/appdata/knowledge/
cp ~/Downloads/iceland-travel.pdf /opt/frey/appdata/knowledge/

# Run document ingestion
cd /opt/frey/appdata/rag-service
python3 ingest_documents.py --path /opt/frey/appdata/knowledge --collection travel_guides
```

**Ingestion Output**:
```
INFO - Testing ChromaDB connection...
INFO - ✓ ChromaDB connected
INFO - Testing Ollama connection...
INFO - ✓ Ollama connected
INFO - Found 2 document(s) to process
INFO - Processing: japan-guide.pdf
INFO - Split into 47 chunks
INFO - Added 47/47 chunks
INFO - Processing: iceland-travel.pdf
INFO - Split into 32 chunks
INFO - Added 32/32 chunks
INFO - ✓ Ingested 79 chunks from 2 files

Available collections (1):
  - travel_guides: 79 documents
```

**Supported formats**: PDF, DOCX, TXT, MD

### 2. Voice Assistant Usage

After configuring Home Assistant Assist (see VOICE_ASSISTANT.md):

**System Control**:
- "Hey Nabu, start Jellyfin"
- "Hey Nabu, is Sonarr running?"
- "Hey Nabu, what services are available?"

**Knowledge Base Queries** (RAG):
- "Hey Nabu, what are the best restaurants in Tokyo?"
- "Hey Nabu, tell me about visiting Iceland in winter"
- "Hey Nabu, where should I stay in Kyoto?"

The LLM automatically determines whether to use RAG based on the question type.

### 3. Queueing Overnight Tasks

Create task files in the queue directory:

```bash
# Create a complex reasoning task
cat > /opt/frey/appdata/task-queue/pending_research_001.json << 'EOF'
{
  "type": "research",
  "prompt": "Analyze the top 10 travel destinations in Southeast Asia. For each destination, provide: 1) Best time to visit, 2) Top 3 attractions, 3) Budget considerations, 4) Safety tips. Format as a detailed comparison.",
  "created_at": "2025-11-17T10:00:00"
}
EOF
```

**Task Processing**:
- Task sits in queue until 11 PM
- Task scheduler activates during quiet hours
- Loads qwen2.5:14b (8GB model) for deep reasoning
- Processes task (may take 5-30 minutes for complex reasoning)
- Saves result to `/opt/frey/appdata/task-queue/completed_research_001.json`
- Unloads model to free memory
- Voice assistant becomes available again at 7 AM

**Check results**:
```bash
cat /opt/frey/appdata/task-queue/completed_research_001.json | jq '.result.result'
```

## Monitoring

### Check Model Status

```bash
# See what models are loaded
curl http://ollama.frey:11434/api/ps

# See available models
curl http://ollama.frey:11434/api/tags

# Check Ollama logs
docker logs ollama -f
```

### Check RAG Service

```bash
# Health check
curl http://rag-service:8001/health

# List collections
curl http://rag-service:8001/collections

# Test query
curl -X POST http://rag-service:8001/query \
  -H 'Content-Type: application/json' \
  -d '{"query": "What are the best restaurants in Tokyo?", "collection": "travel_guides"}'
```

### Check Task Scheduler

```bash
# View scheduler logs
docker logs task-scheduler -f

# Check queue
ls -lh /opt/frey/appdata/task-queue/

# View pending tasks
cat /opt/frey/appdata/task-queue/pending_*.json

# View completed tasks
cat /opt/frey/appdata/task-queue/completed_*.json
```

## Performance Characteristics

### Voice Response Time
- **Cold start** (model not loaded): 3-5 seconds
- **Warm** (model loaded): 1-2 seconds
- **Keep alive**: 10 minutes of quick responses after first use

### RAG Query Time
- **Embedding generation**: ~0.5 seconds
- **Vector search**: ~0.1 seconds
- **LLM response**: 1-3 seconds
- **Total**: 2-4 seconds

### Reasoning Task Time
- **Model loading**: ~10 seconds (qwen2.5:14b)
- **Complex reasoning**: 5-30 minutes (depends on task complexity)
- **Model unloading**: ~2 seconds

### Memory Usage Over Time

```
06:00 AM │ Voice assistant available        │ RAM: ~6.6GB
12:00 PM │ Voice + RAG queries              │ RAM: ~6.6GB
06:00 PM │ Voice assistant active           │ RAM: ~6.6GB
11:00 PM │ Task scheduler starts            │ RAM: ~12.2GB
03:00 AM │ Processing complex task          │ RAM: ~12.2GB
07:00 AM │ Tasks complete, model unloads    │ RAM: ~6.6GB
         │ Voice assistant available        │
```

## Troubleshooting

### Voice assistant not responding
1. Check Ollama is running: `docker ps | grep ollama`
2. Check model is available: `curl http://ollama.frey:11434/api/tags`
3. Check Home Assistant Assist configuration
4. Verify OpenWakeWord is running: `docker logs openwakeword`

### RAG returning "I don't have information"
1. Verify documents were ingested: `curl http://rag-service:8001/collections`
2. Check collection has documents: Should show count > 0
3. Re-ingest if needed: `python3 /opt/frey/appdata/rag-service/ingest_documents.py`

### Overnight tasks not processing
1. Check scheduler is running: `docker ps | grep task-scheduler`
2. Verify it's quiet hours: `date` should be between 11 PM - 7 AM
3. Check task file format: Must be valid JSON
4. View scheduler logs: `docker logs task-scheduler`

### Out of memory errors
1. Check only 1 model loaded: `curl http://ollama.frey:11434/api/ps`
2. Verify OLLAMA_MAX_LOADED_MODELS=1: `docker exec ollama env | grep OLLAMA`
3. Stop unnecessary containers: `docker stop <container>`
4. Check system memory: `free -h`

## Best Practices

### Document Ingestion
- **Chunk size**: 1000 characters works well for most documents
- **File formats**: PDF and DOCX are best, TXT/MD also supported
- **Organization**: Use subdirectories in `/knowledge` for different topics
- **Re-ingestion**: Safe to run multiple times, creates new chunks with unique IDs

### Task Scheduling
- **Task files**: Use descriptive names with timestamps
- **Queue management**: Clean up completed tasks periodically
- **Complexity**: Reserve overnight tasks for truly complex reasoning
- **Quiet hours**: Adjust timing based on your usage patterns

### Memory Management
- **Don't disable**: Keep OLLAMA_MAX_LOADED_MODELS=1
- **Model size**: Stick to recommended models for your RAM
- **Monitoring**: Watch memory with `htop` if issues arise
- **Trade-offs**: Smaller models = faster but less capable

## Comparison to Alternatives

### Why not run all models simultaneously?
**Memory math**:
- llama3.2:3b: 2.2GB
- qwen2.5:14b: 8GB
- Total: 10.2GB + system overhead = **13-14GB**
- Leaves only 2-3GB for everything else ❌

With smart loading:
- Only one model at a time: 2.2-8GB
- Leaves 8-13GB for system and services ✅

### Why not use cloud AI?
- **Privacy**: All data stays local
- **Cost**: No API fees
- **Latency**: Local inference is faster for voice
- **Offline**: Works without internet

### Why not just use ChatGPT API?
- **Privacy**: Travel plans, documents stay private
- **Cost**: Free after initial setup
- **Control**: You own the models and data
- **Learning**: Great for understanding AI systems

## Future Enhancements

Possible improvements:
- Web UI for RAG queries (instead of voice only)
- Automatic document re-indexing
- Multiple knowledge collections (travel, cooking, technical docs)
- Task scheduler API for programmatic task submission
- Grafana dashboard for AI metrics (model usage, response times)
- Support for larger models (if upgrading to Pi with 32GB RAM)

## References

- [Ollama Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [ChromaDB Documentation](https://docs.trychroma.com/)
- [Home Assistant Assist](https://www.home-assistant.io/voice_control/)
- [RAG Explained](https://www.promptingguide.ai/techniques/rag)
