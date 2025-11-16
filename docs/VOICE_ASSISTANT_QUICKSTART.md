# Voice Assistant Quick Start

Get voice control working in 10 minutes using Home Assistant Assist.

## TL;DR

```bash
# 1. Deploy services
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation

# 2. Configure in Home Assistant UI (3 clicks)
# 3. Say "OK Nabu, what time is it?"
```

## Prerequisites

✅ Raspberry Pi 5 (8GB+ recommended)
✅ Frey system deployed
✅ Home Assistant running

## Step 1: Deploy Services (2 minutes)

```bash
cd /home/user/frey
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

This deploys:
- ✅ Whisper (Speech-to-Text)
- ✅ Piper (Text-to-Speech)
- ✅ OpenWakeWord (Wake word detection)
- ✅ Ollama with Llama 3.2 3B model

**First deployment takes ~5 minutes** (downloads 2GB Ollama model)

## Step 2: Configure Home Assistant (5 minutes)

Access Home Assistant: `https://homeassistant.frey`

### 2a. Add Wyoming Services

1. **Settings → Devices & Services**
2. **Add Integration** → Search **"Wyoming Protocol"**
3. Add these 3 services:

| Name | Host | Port |
|------|------|------|
| Whisper | `wyoming-whisper` | `10300` |
| Piper | `piper` | `10200` |
| OpenWakeWord | `openwakeword` | `10400` |

### 2b. Add Ollama

1. **Settings → Devices & Services**
2. **Add Integration** → Search **"Ollama"** (or "Extended OpenAI" / "LLM")
3. Configure:
   - Host: `http://ollama:11434`
   - Model: `llama3.2:3b`

### 2c. Create Voice Assistant

1. **Settings → Voice assistants**
2. **Add Assistant**
3. Configure:
   - **Speech-to-Text**: Whisper
   - **Text-to-Speech**: Piper
   - **Conversation agent**: Ollama
   - **Wake word**: ok_nabu

### 2d. Enable Shell Commands

```bash
# SSH to server
ssh user@frey.local

# Edit Home Assistant config
nano /opt/frey/appdata/homeassistant/configuration.yaml
```

Add this line:
```yaml
shell_command: !include voice_assistant_config.yaml
```

Restart:
```bash
docker restart homeassistant
```

## Step 3: Test It!

### On Desktop/Laptop

1. Open Home Assistant
2. Click the mic icon (top right)
3. Say: **"What time is it?"**
4. Listen to response!

### With Wake Word (requires microphone)

1. Say: **"OK Nabu"**
2. Wait for chime
3. Say: **"What time is it?"**
4. Listen to response!

### On Mobile

1. Install **Home Assistant Companion** app
2. Login to `homeassistant.frey`
3. App **Settings → Assist → Enable**
4. Use mic button to talk

## Voice Commands

**The LLM (Ollama) automatically understands natural language - no automations needed!**

Try these after setup:

**General:**
- "OK Nabu, what can you do?"
- "OK Nabu, what time is it?"
- "OK Nabu, tell me a joke"

**Service Control** (works immediately):
- "OK Nabu, start Jellyfin"
- "OK Nabu, stop Sonarr"
- "OK Nabu, restart Radarr"
- "OK Nabu, turn on the torrent client"

**Service Status:**
- "OK Nabu, is Jellyfin running?"
- "OK Nabu, what services are running?"
- "OK Nabu, check the status of Sonarr"

**System Info:**
- "OK Nabu, show me the system status"
- "OK Nabu, how much disk space is left?"
- "OK Nabu, what's the memory usage?"

**The LLM understands variations!** You can say "Jelly" instead of "Jellyfin", "torrent" instead of "qBittorrent", etc.

## How It Works (No Automations Needed!)

The system uses **function calling** with Ollama:

1. You speak a command
2. Ollama (LLM) understands what you want
3. Ollama calls the right shell command with parameters
4. Result is spoken back to you

A single smart script (`frey-docker-control`) handles all Docker operations. The LLM figures out what service and what action you want.

**No need to create automations for each service!** The LLM is smart enough to understand and call the right commands.

## Troubleshooting

### "Wyoming service not found"

**Check containers:**
```bash
docker ps | grep -E "wyoming|piper|openwakeword"
```

**Should see:**
- wyoming-whisper
- piper
- openwakeword

If missing, redeploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

### "Ollama not responding"

**Check Ollama:**
```bash
docker logs ollama
docker exec ollama ollama list
```

**Should show:** `llama3.2:3b`

**If missing, pull manually:**
```bash
docker exec ollama ollama pull llama3.2:3b
```

### "Wake word not working"

**Try mobile app first** - if that works, problem is microphone hardware.

**Check OpenWakeWord:**
```bash
docker logs openwakeword
```

**Try different wake word:**
```yaml
# group_vars/all/main.yml
voice_assistant:
  wake_word: "hey_jarvis"
```

Redeploy after changing.

### "Too slow"

**Use faster model:**
```yaml
voice_assistant:
  ollama_model: "llama3.2:1b"  # 3x faster
```

Or:
```yaml
voice_assistant:
  ollama_model: "phi3:mini"  # Good balance
```

## Next Steps

1. **Mobile app** - Control from anywhere
2. **Automations** - Add more voice commands
3. **ESP32 satellites** - Add hardware voice assistants
4. **n8n integration** - Trigger complex workflows
5. **Custom intents** - Train custom commands

## Full Documentation

See `docs/VOICE_ASSISTANT.md` for:
- Advanced configuration
- Custom automations
- ESP32 hardware satellites
- n8n workflow integration
- Troubleshooting guide

## Remember

- **Wake word**: "OK Nabu" (configurable)
- **First time?** Use mobile app mic button
- **Not working?** Check logs: `docker logs homeassistant`
- **Mobile app** = easiest way to test

🎤 **You now have a local voice assistant!** No cloud, fully private, yours to control.
