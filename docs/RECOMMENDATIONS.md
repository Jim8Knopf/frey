# Recommendations: Level Up Your Voice Assistant

Based on your current Frey setup, here are recommendations to take it from **good** to **amazing**.

## Quick Wins (Easy, High Impact)

### 1. Custom Wake Word ⭐ HIGHLY RECOMMENDED

**Current:** "Ok Nabu" (generic)
**Better:** "Hey Frey" or "Computer" (like Star Trek) or "KITT" (Knight Rider)

**Why:** Makes it feel more personal and unique to your system.

**How to implement:**

OpenWakeWord supports custom wake words! You can:

**Option A: Use existing wake words**
```yaml
# In group_vars/all/main.yml
voice_assistant:
  wake_word: "hey_jarvis"  # or "alexa", "hey_mycroft", "hey_jarvis"
```

Available wake words: https://github.com/dscripka/openWakeWord#pre-trained-models

**Option B: Train your own "Hey Frey" wake word**

1. Record 50-100 samples of yourself saying "Hey Frey"
2. Use OpenWakeWord training: https://github.com/dscripka/openWakeWord/tree/main/training
3. Deploy custom model to your Pi

**Time:** 2-3 hours for custom training
**Impact:** ⭐⭐⭐⭐⭐ Feels completely personalized

---

### 2. Better Voice (Piper TTS Upgrade) ⭐ RECOMMENDED

**Current:** Default Piper voice (functional but robotic)
**Better:** High-quality neural voice

**Available voices:**
- `en_US-lessac-medium` - Clear, neutral (current default)
- `en_US-libritts-high` - More natural, requires more RAM
- `en_GB-alan-medium` - British accent (like KITT!)
- `en_US-ryan-high` - Warm, friendly voice

**How to change:**

```yaml
# In group_vars/all/main.yml
voice_assistant:
  piper_voice: "en_GB-alan-medium"  # British like KITT
  # or
  piper_voice: "en_US-libritts-high"  # High quality American
```

Then redeploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

**Try voices:** https://rhasspy.github.io/piper-samples/

**Time:** 5 minutes
**Impact:** ⭐⭐⭐⭐ Much more pleasant to interact with

---

### 3. Add Conversation Memory ⭐⭐⭐ GAME CHANGER

**Current:** Each voice command is independent
**Better:** Remember conversation context

**Example:**
```
You: "Start Jellyfin"
Frey: "Starting Jellyfin."
You: "And Sonarr too"  # <-- Currently won't understand "too"
Frey: "Starting Sonarr as well."  # <-- With memory!
```

**How to implement:**

Add conversation history to Home Assistant:

```yaml
# In roles/automation/templates/homeassistant/packages/frey_voice.yaml.j2

conversation:
  - platform: ollama
    url: "http://ollama:11434"
    model: "{{ voice_assistant.ollama_model }}"
    prompt: |
      You are Frey, a helpful voice assistant.

      Remember the conversation history and use context from previous messages.
      If user says "and that too" or "also X", refer to previous commands.

      [rest of prompt...]
    options:
      temperature: 0.7
      top_p: 0.9
      num_ctx: 4096
      num_keep: 512  # <-- Keep last 512 tokens for context
```

**Time:** 10 minutes
**Impact:** ⭐⭐⭐⭐⭐ Feels like a real conversation

---

### 4. Voice Confirmations ⭐ RECOMMENDED

**Current:** Frey responds with text, but you might not see it
**Better:** Frey speaks confirmations

**Example:**
```
You: "Start Jellyfin"
Frey: [SPEAKS] "Starting Jellyfin now"
```

**Already configured!** Home Assistant voice pipeline should speak responses by default.

**Verify it's working:**
1. Open Home Assistant: `http://homeassistant.frey:8123`
2. Settings → Voice assistants → Frey Voice Assistant
3. Under "Text-to-speech": Should say "Piper"
4. Test: Say wake word, then "Start Jellyfin"

**If not working:**
```bash
# Check Piper is running
docker ps | grep piper

# Check logs
docker logs wyoming-piper

# Restart voice pipeline
docker restart homeassistant wyoming-piper
```

**Time:** 5 minutes to verify
**Impact:** ⭐⭐⭐⭐ Essential for voice-only control

---

## Medium Effort (Worth It)

### 5. Routines and Scenes ⭐⭐⭐ VERY USEFUL

**Idea:** Control multiple services with one command

**Example routines:**

**"Movie Time"**
```
- Start Jellyfin
- Dim lights (if you have smart lights)
- Set volume to 50%
- Stop music services
```

**"Goodnight"**
```
- Stop all media services
- Enable overnight reasoning mode
- Turn off lights
- Set alarm
```

**"Work Mode"**
```
- Start Home Assistant
- Start monitoring (Grafana)
- Stop media services
- Start productivity timer
```

**How to implement:**

```yaml
# In roles/automation/templates/homeassistant/packages/frey_voice.yaml.j2

script:
  frey_movie_time:
    alias: "Movie Time"
    sequence:
      - service: shell_command.frey_docker
        data:
          action: "start"
          service: "jellyfin"
      # Add more steps...
      - service: notify.persistent_notification
        data:
          message: "Movie mode activated. Enjoy!"

# Add to training dataset:
# {"input": "Movie time", "output": "Setting up movie mode for you. <function_call>frey_movie_time()</function_call>"}
```

**Time:** 1-2 hours
**Impact:** ⭐⭐⭐⭐⭐ Massively improves daily workflow

---

### 6. Mobile Access (Talk from Anywhere) ⭐⭐⭐

**Idea:** Control Frey from your phone

**Options:**

**Option A: Home Assistant Companion App** (Easiest)
1. Install Home Assistant app (iOS/Android)
2. Configure: Settings → Assist → Frey Voice Assistant
3. Use "Hey Nabu" on your phone
4. Works from anywhere (if you expose Home Assistant externally)

**Option B: VPN Access**
- Use Tailscale (already in TODO.md for Frey)
- Access `http://homeassistant.frey:8123` securely from phone
- Use web interface for voice commands

**Time:** 30 minutes
**Impact:** ⭐⭐⭐⭐ Control from anywhere in house (or world!)

---

### 7. Smart Notifications ⭐⭐

**Idea:** Frey notifies you proactively

**Examples:**
- "Sonarr downloaded new episode of [Show]"
- "System update available"
- "Disk space low"
- "Download completed"

**How to implement:**

Use **ntfy** (already in TODO.md):

```yaml
# In docker-compose
ntfy:
  image: binwiederhier/ntfy
  command:
    - serve
  ports:
    - "9080:80"
  volumes:
    - ./ntfy:/var/cache/ntfy

# Configure services to send notifications
# Example: Sonarr → Settings → Connect → ntfy
```

**Then add to Frey:**
```python
# Frey can announce notifications via voice!
"You have a new notification from Sonarr: Breaking Bad S05E10 downloaded."
```

**Time:** 2-3 hours
**Impact:** ⭐⭐⭐⭐ Stay informed without checking

---

### 8. Monitoring Dashboard ⭐⭐

**Idea:** "Hey Frey, show system status"

**Current:** Text response
**Better:** Visual dashboard

**Implementation:**

You already have Grafana! Add AI metrics dashboard:

**Metrics to track:**
- Ollama inference time
- Voice recognition accuracy
- Most used commands
- Model RAM usage over time
- Response times

**Create dashboard:**
```bash
# Add Prometheus metrics to Ollama
# Track inference times, token counts, etc.

# Configure in Grafana
# Create "AI Performance" dashboard
```

**Time:** 3-4 hours
**Impact:** ⭐⭐⭐ Understand usage patterns, optimize performance

---

## Advanced (For the Future)

### 9. Multi-User Voice Profiles ⭐⭐⭐⭐

**Idea:** Recognize WHO is speaking

**Use case:**
- Different users get personalized responses
- Access control (kids can't stop critical services)
- Personal preferences (your preferred voice, language)

**How:**
- Train voice embeddings for each user
- Use speaker identification before processing command
- Route to personalized assistants

**Tools:** Resemblyzer, PyAnnote Audio, or SpeechBrain

**Time:** 8-12 hours
**Impact:** ⭐⭐⭐⭐⭐ Family-friendly, secure

---

### 10. Proactive Suggestions ⭐⭐⭐

**Idea:** Frey suggests actions based on patterns

**Examples:**
- "It's 8 PM. Would you like me to start your usual movie night routine?"
- "Your favorite show just downloaded. Ready to watch?"
- "System has been idle for 2 hours. Should I free up RAM by unloading models?"

**How to implement:**

Use **overnight reasoning mode** (already configured!) to:
1. Analyze usage patterns
2. Generate suggestions
3. Store in RAG knowledge base
4. Present via voice when relevant

**Example script:**
```python
# Overnight task: Analyze patterns
# Input: Last week's voice commands
# Output: Personalized suggestions

# "User typically starts Jellyfin at 8 PM on Fridays"
# → At 7:55 PM Friday: "Would you like movie time?"
```

**Time:** 6-10 hours
**Impact:** ⭐⭐⭐⭐⭐ Feels like AI that knows you

---

### 11. Visual Context (Cameras) ⭐⭐⭐⭐

**Idea:** "What do you see?" → Frey describes camera feed

**Use case:**
- "Is the package at the door?"
- "Who's at the front door?"
- "What's the weather like outside?"

**How:**
- Add USB camera to Pi 5
- Use vision model (LLaVA, BakLLaVA) via Ollama
- Integrate with voice commands

**Example:**
```bash
# Install vision model
ollama pull llava:7b-v1.6-q4_k_m

# Query with image
curl -X POST http://ollama:11434/api/generate \
  -d '{"model":"llava:7b-v1.6-q4_k_m", "prompt":"What do you see?", "images":["base64..."]}'
```

**RAM impact:** +4GB when vision model loaded
**Time:** 4-6 hours
**Impact:** ⭐⭐⭐⭐⭐ Multimodal AI!

---

### 12. Natural Language Automation ⭐⭐⭐⭐

**Idea:** "Remind me to check Sonarr in 30 minutes"

**Current:** Can't schedule future actions
**Better:** Natural language scheduling

**Examples:**
- "Wake me up at 7 AM tomorrow"
- "Download this when the server is idle"
- "Check for updates every Sunday"

**How:**
- Extract time/date entities from voice command
- Use Home Assistant automations
- Create dynamic schedules

**Time:** 4-6 hours
**Impact:** ⭐⭐⭐⭐ True smart assistant

---

### 13. Offline Mode ⭐⭐

**Idea:** Work without internet

**Current status:** Already works offline! ✅

Everything is local:
- ✅ Ollama (local)
- ✅ Whisper (local)
- ✅ Piper (local)
- ✅ OpenWakeWord (local)
- ✅ RAG (local)

**BUT:** Fine-tuning requires Google Colab (internet)

**Fully offline fine-tuning:**
1. Set up local GPU machine
2. Run `scripts/finetune/finetune_frey_model.py`
3. No internet needed after initial setup

**Time:** 1 hour (if you have GPU)
**Impact:** ⭐⭐⭐ True privacy/security

---

### 14. Voice Shortcuts ⭐

**Idea:** Quick single-word commands

**Examples:**
- "Status" → System status
- "Movies" → Start Jellyfin
- "Downloads" → Check qBittorrent
- "Sleep" → Goodnight routine

**Implementation:**
Add to fine-tuning dataset:
```jsonl
{"input": "Status", "output": "Checking system status. <function_call>frey_system_info()</function_call>"}
{"input": "Movies", "output": "Starting Jellyfin. <function_call>frey_docker_start(service=\"jellyfin\")</function_call>"}
```

**Time:** 30 minutes (add to dataset, retrain)
**Impact:** ⭐⭐⭐⭐ Faster, more natural

---

### 15. Context-Aware Responses ⭐⭐⭐⭐

**Idea:** Frey knows what's happening

**Examples:**

**Scenario 1: Download in progress**
```
You: "Start Jellyfin"
Frey: "Starting Jellyfin. By the way, qBittorrent is currently downloading Breaking Bad S05E10 - 75% complete."
```

**Scenario 2: Service already running**
```
You: "Start Jellyfin"
Frey: "Jellyfin is already running and has been up for 3 hours."
```

**Scenario 3: System load**
```
You: "Start the 14B reasoning model"
Frey: "Warning: System RAM is at 85%. I recommend stopping Jellyfin first to free up space."
```

**How:**
- Query Docker API for real-time status
- Check system metrics before executing commands
- Provide context in responses

**Time:** 4-6 hours
**Impact:** ⭐⭐⭐⭐⭐ Intelligent, not just reactive

---

## Security & Privacy

### 16. Voice Command Authentication ⭐⭐⭐

**Idea:** Require confirmation for dangerous commands

**Examples:**
```
You: "Stop all services"
Frey: "This will stop all Docker services. Please confirm by saying 'Yes, do it'."
You: "Yes, do it"
Frey: "Confirmed. Stopping all services."
```

**Protected commands:**
- Stop critical services (Home Assistant, Ollama)
- Delete data
- System shutdown/reboot
- Network changes

**Time:** 2-3 hours
**Impact:** ⭐⭐⭐⭐ Prevents accidents

---

### 17. Command Audit Log ⭐⭐

**Idea:** Track all voice commands

**Why:**
- Security (who did what?)
- Debugging (what command failed?)
- Training data (collect real usage for fine-tuning)

**Implementation:**
```yaml
# Log to file
automation:
  - alias: "Log Voice Commands"
    trigger:
      platform: event
      event_type: conversation_started
    action:
      service: notify.log_file
      data:
        message: "Voice command: {{ trigger.event.data.text }}"
```

**Time:** 1 hour
**Impact:** ⭐⭐⭐ Useful for debugging and improvement

---

## Performance Optimization

### 18. Model Warm-up ⭐⭐

**Idea:** Pre-load model before first use

**Current:** First command takes 3-5 seconds (model loading)
**Better:** Model ready instantly

**Implementation:**
```yaml
# In docker-compose
ollama:
  # ... existing config
  healthcheck:
    test: ["CMD", "ollama", "run", "llama3.2:3b", "Hello"]
    start_period: 30s
    interval: 5m
```

This keeps model "warm" and ready.

**Time:** 10 minutes
**Impact:** ⭐⭐⭐ Faster first response

---

### 19. Response Streaming ⭐

**Idea:** Start speaking before full response generated

**Current:** Wait for full response → then speak
**Better:** Stream response → speak as generated

**Result:** Feels ~2x faster

**Implementation:** Configure Home Assistant to stream Ollama responses

**Time:** 1-2 hours
**Impact:** ⭐⭐⭐⭐ Much snappier experience

---

## Fun Additions

### 20. Easter Eggs ⭐⭐⭐

**Idea:** Hidden personality features

**Examples:**
```jsonl
{"input": "Tell me a joke", "output": "Why don't programmers like nature? It has too many bugs."}
{"input": "What's the meaning of life?", "output": "42. Obviously."}
{"input": "Do you dream of electric sheep?", "output": "Only when I'm in sleep mode. Which, ironically, I never am."}
{"input": "Are you KITT?", "output": "I appreciate the comparison, Michael. But I'm Frey, and this is YOUR very own Knight Industries Two Thousand."}
```

**Time:** 30 minutes (add to dataset)
**Impact:** ⭐⭐⭐⭐⭐ Makes interaction delightful

---

## Recommended Priority

### Start Here (This Week)
1. ✅ **Custom wake word** - "Hey Frey" (2-3 hours)
2. ✅ **Better voice** - British KITT voice (5 minutes)
3. ✅ **Voice confirmations** - Verify working (5 minutes)
4. ✅ **Easter eggs** - Add personality (30 minutes)

**Total time:** ~4 hours
**Impact:** Transforms experience from "functional" to "delightful"

### Next (This Month)
5. ✅ **Routines** - Movie time, goodnight, work mode (2 hours)
6. ✅ **Mobile access** - Home Assistant app (30 minutes)
7. ✅ **Voice shortcuts** - Single-word commands (30 minutes)
8. ✅ **Conversation memory** - Context awareness (1 hour)

**Total time:** ~4 hours
**Impact:** Daily quality of life improvements

### Future (When You're Ready)
9. ✅ **Smart notifications** - ntfy integration (3 hours)
10. ✅ **Multi-user profiles** - Family support (12 hours)
11. ✅ **Visual context** - Camera integration (6 hours)
12. ✅ **Proactive suggestions** - Pattern learning (10 hours)

**Total time:** ~30 hours
**Impact:** Truly next-level smart home

---

## What NOT to Do

❌ **Don't:** Add too many features at once
✅ **Do:** Implement one, test thoroughly, then next

❌ **Don't:** Overtrain your model (overfitting)
✅ **Do:** Keep dataset diverse, retrain when you have 10+ new examples

❌ **Don't:** Expose Home Assistant directly to internet
✅ **Do:** Use VPN (Tailscale) or secure reverse proxy

❌ **Don't:** Run out of RAM
✅ **Do:** Monitor with Grafana, keep smart loading enabled

❌ **Don't:** Ignore security
✅ **Do:** Implement command authentication for dangerous actions

---

## Summary: Quick Wins First

**This weekend (4 hours):**
```bash
# 1. Change wake word to "Hey Frey" (15 min)
# 2. Switch to British voice (5 min)
# 3. Add 10 easter eggs to dataset (30 min)
# 4. Retrain on Google Colab (20 min)
# 5. Deploy new model (10 min)
# 6. Test and enjoy! (2 hours of playing)
```

**Result:** Your voice assistant goes from "cool tech demo" to "indispensable companion"

---

**Questions? Pick one thing from "Start Here" and let me know if you want detailed implementation!**
