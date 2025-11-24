# Frey Voice Assistant (Home Assistant Assist)

A local, privacy-focused voice assistant using Home Assistant's built-in Assist feature. Control your Frey server with voice commands - no cloud services needed.

## Overview

The Frey voice assistant leverages **Home Assistant Assist**, the native voice assistant framework built into Home Assistant. This provides:

- **Wake Word Detection**: Via OpenWakeWord ("OK Nabu", "Hey Jarvis", etc.)
- **Speech-to-Text**: Whisper (highly accurate, fully local)
- **Conversation Agent**: Ollama with Llama 3.2 3B (natural language understanding)
- **Text-to-Speech**: Piper (natural voice responses)
- **System Control**: Docker container management, service status, system info

**Everything runs locally** on your Raspberry Pi - no cloud, no external APIs, completely private.

## Why Home Assistant Assist?

Instead of building a custom voice assistant from scratch, we use Home Assistant's battle-tested voice pipeline because it:

✅ **Built-in and maintained** - No custom code to maintain
✅ **Mobile app support** - Control Frey from your phone anywhere
✅ **ESP32 satellites** - Add voice control hardware throughout your home
✅ **Rich integrations** - n8n workflows, automations, dashboards
✅ **Community support** - Thousands of users, extensive documentation
✅ **Mature and stable** - Years of development and testing

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Home Assistant Assist                       │
│                                                              │
│  Wake Word → STT (Whisper) → Conversation (Ollama) →        │
│  TTS (Piper) → Action (Shell Commands / Automations)        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ├─→ Wyoming Services (Whisper, Piper, OpenWakeWord)
                           ├─→ Ollama (Local LLM)
                           └─→ Docker API (Container Control)
```

### Components

All components are already deployed:

1. **Home Assistant** - Voice assistant orchestrator
2. **Wyoming Whisper** - Speech-to-text (STT)
3. **Wyoming Piper** - Text-to-speech (TTS)
4. **OpenWakeWord** - Wake word detection
5. **Ollama** - Local LLM for natural conversation

## Configuration

### 1. Deploy the Stack

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

This deploys all required services and pulls the Ollama model (~2GB).

### 2. Configure Home Assistant

Access Home Assistant at `https://homeassistant.{{ network.domain_name }}`

#### Step 2a: Add Wyoming Integrations

1. Go to **Settings → Devices & Services**
2. Click **Add Integration**, search for **"Wyoming Protocol"**
3. Add each Wyoming service:

| Service | Host | Port | Purpose |
|---------|------|------|---------|
| Whisper | `wyoming-whisper` | 10300 | Speech-to-Text |
| Piper | `piper` | 10200 | Text-to-Speech |
| OpenWakeWord | `openwakeword` | 10400 | Wake Word |

#### Step 2b: Add Ollama Integration

1. Go to **Settings → Devices & Services**
2. Click **Add Integration**, search for **"Ollama"** (or **"LLM" / "Conversation"**)
3. Configure:
   - **Host**: `ollama` (or `http://ollama:11434`)
   - **Model**: `llama3.2:3b`

#### Step 2c: Create Voice Assistant

1. Go to **Settings → Voice assistants**
2. Click **"Add Assistant"**
3. Configure:
   - **Name**: Frey Assistant
   - **Conversation agent**: Ollama (llama3.2:3b)
   - **Speech-to-Text**: Whisper
   - **Text-to-Speech**: Piper
   - **Wake word**: ok_nabu (OpenWakeWord)

#### Step 2d: Enable Shell Commands

1. SSH to your Frey server
2. Edit Home Assistant configuration:
   ```bash
   nano /opt/frey/appdata/homeassistant/configuration.yaml
   ```
3. Add this line:
   ```yaml
   shell_command: !include voice_assistant_config.yaml
   ```
4. Restart Home Assistant:
   ```bash
   docker restart homeassistant
   ```

### 3. Create Automations for Voice Commands

In Home Assistant, go to **Settings → Automations & Scenes → Create Automation**

#### Example: Start Jellyfin via Voice

```yaml
alias: "Voice: Start Jellyfin"
trigger:
  - platform: conversation
    command:
      - "start jellyfin"
      - "turn on jellyfin"
action:
  - service: shell_command.docker_start_jellyfin
  - service: tts.speak
    target:
      entity_id: tts.piper
    data:
      message: "Starting Jellyfin now"
```

#### Example: Check Running Services

```yaml
alias: "Voice: List Services"
trigger:
  - platform: conversation
    command:
      - "what services are running"
      - "list running services"
action:
  - service: shell_command.docker_ps
  - service: tts.speak
    target:
      entity_id: tts.piper
    data:
      message: "Let me check the running services"
```

## Usage

### Voice Commands

Once configured, you can say:

**Service Control:**
- "OK Nabu, start Jellyfin"
- "OK Nabu, stop Sonarr"
- "OK Nabu, restart Radarr"

**Service Status:**
- "OK Nabu, what services are running?"
- "OK Nabu, is Jellyfin running?"

**General Questions:**
- "OK Nabu, what can you do?"
- "OK Nabu, what time is it?"
- Any general questions (answered by Ollama)

### Mobile App

1. Install **Home Assistant Companion** app (iOS/Android)
2. Log in to your Frey instance
3. Go to app **Settings → Assist**
4. Enable voice control
5. Use the mic button or say the wake word

Now you can control Frey from anywhere!

## Model Configuration

### Current Setup (Raspberry Pi 5 16GB)

```yaml
# group_vars/all/main.yml
voice_assistant:
  ollama_model: "llama3.2:3b"  # ~2GB RAM, fast, excellent quality
  wake_word: "ok_nabu"
```

### Alternative Models

| Model | RAM | Speed | Quality | Use Case |
|-------|-----|-------|---------|----------|
| **llama3.2:3b** ✅ | ~2GB | Fast | Excellent | Default (best balance) |
| phi3:mini | ~2.3GB | Very Fast | Good | Faster responses |
| qwen2.5:3b | ~2GB | Fast | Good | Multilingual support |
| llama3.2:1b | ~1GB | Very Fast | Fair | Low RAM / Max speed |

**Change model:**
```bash
# Edit configuration
nano /home/user/frey/group_vars/all/main.yml

# Change ollama_model, then redeploy
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

### Alternative Wake Words

Available wake words in OpenWakeWord:
- `ok_nabu` (default)
- `hey_jarvis` (Iron Man style)
- `alexa` (Amazon Alexa style)
- `hey_mycroft`
- `hey_rhasspy`

Change in configuration and redeploy.

## Advanced Features

### n8n Workflow Integration

Trigger complex n8n workflows via voice:

1. Create n8n workflow with webhook trigger
2. Create Home Assistant automation that calls webhook
3. Use voice command to trigger automation

Example:
```yaml
alias: "Voice: Backup Media"
trigger:
  - platform: conversation
    command: "backup all media"
action:
  - service: rest_command.trigger_n8n_backup
    data:
      workflow: "media_backup"
```

### ESP32 Hardware Satellites

Add dedicated voice hardware throughout your home:

1. Flash ESP32 with ESPHome
2. Add Wyoming satellite integration
3. Place microphone/speaker in any room
4. Say wake word from anywhere - control Frey

See [ESPHome Voice Assistant docs](https://esphome.io/components/voice_assistant.html)

### Custom Intents

Train Home Assistant to understand custom commands:

1. Go to **Settings → Voice assistants → Your assistant**
2. Click **"Manage intents"**
3. Add custom sentences and actions

Example: "Download latest episode of [show name]" → Trigger Sonarr

## Troubleshooting

### Wyoming Services Not Found

**Verify containers are running:**
```bash
docker ps | grep -E "wyoming|openwakeword|piper"
```

**Check service connectivity:**
```bash
# From Home Assistant container
docker exec homeassistant nc -zv wyoming-whisper 10300
docker exec homeassistant nc -zv piper 10200
docker exec homeassistant nc -zv openwakeword 10400
```

### Ollama Integration Fails

**Check Ollama is running:**
```bash
docker logs ollama
```

**Verify model is pulled:**
```bash
docker exec ollama ollama list
```

**Test Ollama manually:**
```bash
docker exec ollama ollama run llama3.2:3b "Hello, are you working?"
```

### Wake Word Not Detecting

**Check OpenWakeWord logs:**
```bash
docker logs openwakeword
```

**Try different wake word:**
```yaml
voice_assistant:
  wake_word: "hey_jarvis"
```

**Test with Home Assistant mobile app first** - if that works, issue is with microphone hardware.

### Shell Commands Not Working

**Check shell_command configuration:**
```bash
cat /opt/frey/appdata/homeassistant/configuration.yaml | grep shell_command
```

**Verify Docker socket access:**
```bash
docker exec homeassistant docker ps
```

If error: Add Docker socket to Home Assistant container volumes.

### Voice Response Too Slow

**Use faster model:**
```yaml
voice_assistant:
  ollama_model: "llama3.2:1b"  # 3x faster than 3b
```

**Or switch to Phi-3:**
```yaml
voice_assistant:
  ollama_model: "phi3:mini"  # Good speed/quality balance
```

## File Locations

- **Configuration**: `/opt/frey/appdata/homeassistant/configuration.yaml`
- **Voice commands**: `/opt/frey/appdata/homeassistant/voice_assistant_config.yaml`
- **Automations**: `/opt/frey/appdata/homeassistant/automations.yaml`
- **Ollama models**: `/opt/frey/appdata/ollama/`
- **Piper voices**: `/opt/frey/appdata/piper/`
- **Whisper models**: `/opt/frey/appdata/wyoming-whisper/`

## Resources

- [Home Assistant Assist Documentation](https://www.home-assistant.io/voice_control/)
- [Wyoming Protocol](https://www.home-assistant.io/integrations/wyoming/)
- [Ollama Integration](https://www.home-assistant.io/integrations/ollama/)
- [OpenWakeWord Models](https://github.com/dscripka/openWakeWord)
- [ESPHome Voice Assistant](https://esphome.io/components/voice_assistant.html)

## Comparison: Home Assistant vs Custom Python

| Feature | Home Assistant Assist | Custom Python |
|---------|----------------------|---------------|
| Code to maintain | ✅ 0 lines | ❌ ~2000 lines |
| Mobile app | ✅ Built-in | ❌ None |
| Hardware satellites | ✅ ESP32 support | ❌ None |
| Automations | ✅ Visual editor | ❌ Code only |
| Maturity | ✅ Production-ready | ❌ Alpha quality |
| Community | ✅ Huge ecosystem | ❌ Solo project |

**Home Assistant is the right choice for this use case.**

## Credits

- [Home Assistant](https://www.home-assistant.io/) - Open source home automation
- [Ollama](https://ollama.ai/) - Local LLM runtime
- [Whisper](https://github.com/openai/whisper) - Speech recognition
- [Piper](https://github.com/rhasspy/piper) - Text-to-speech
- [OpenWakeWord](https://github.com/dscripka/openWakeWord) - Wake word detection
- [Wyoming Protocol](https://github.com/rhasspy/wyoming) - Voice service communication
