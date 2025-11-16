# Voice Assistant Quick Start Guide

Get your Frey voice assistant up and running in minutes!

## TL;DR

```bash
# 1. Deploy the voice assistant
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation

# 2. Check it's running
docker logs -f voice-assistant

# 3. Say "OK Nabu" and start talking!
```

## Prerequisites

✅ Raspberry Pi 5 with 16GB RAM (8GB minimum)
✅ Microphone connected (USB or 3.5mm)
✅ Speakers/headphones for audio output
✅ Frey system already deployed

## Quick Setup

### 1. Enable Voice Assistant

The voice assistant is **already enabled** by default in your configuration:

```yaml
# group_vars/all/main.yml
voice_assistant:
  deploy: true
  wake_word: "ok_nabu"
  ollama_model: "llama3.2:3b"
```

### 2. Deploy

Run the automation playbook:

```bash
cd /home/user/frey
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

This will:
- ✅ Deploy OpenWakeWord, Whisper, Piper, and Voice Assistant
- ✅ Pull the Llama 3.2 3B model (~2GB download)
- ✅ Configure all services
- ✅ Start the voice pipeline

**First deployment takes 5-10 minutes** due to model download.

### 3. Verify Services

Check all voice services are running:

```bash
docker ps | grep -E "voice|piper|whisper|openwakeword|ollama"
```

You should see:
- ✅ voice-assistant
- ✅ openwakeword
- ✅ piper
- ✅ wyoming-whisper
- ✅ ollama

### 4. Test Audio

**Test microphone:**
```bash
docker exec -it voice-assistant arecord -l
```

**Test speakers:**
```bash
docker exec -it voice-assistant aplay -l
```

### 5. Monitor Logs

Watch the assistant start:

```bash
docker logs -f voice-assistant
```

Look for:
```
====================================
Frey Voice Assistant
====================================
✓ Dependencies installed
✓ Audio devices found
🎤 Frey Assistant is ready!
Wake word: 'ok_nabu'
Model: llama3.2:3b
====================================
```

## First Conversation

### Wake the Assistant

Say clearly: **"OK Nabu"**

You should hear: *"Yes, how can I help?"*

### Try These Commands

**Check services:**
- "What services are running?"
- "Is Jellyfin running?"

**Control services:**
- "Start Sonarr"
- "Stop Radarr"

**System info:**
- "What's the CPU usage?"
- "How much memory is free?"

**General:**
- "What can you do?"
- "What time is it?"

## Troubleshooting

### Wake Word Not Detected

**Check audio input:**
```bash
# Test microphone is detected
docker exec -it voice-assistant python3 -c "
import pyaudio
p = pyaudio.PyAudio()
print(f'Audio devices: {p.get_device_count()}')
for i in range(p.get_device_count()):
    info = p.get_device_info_by_index(i)
    print(f'{i}: {info[\"name\"]} (inputs: {info[\"maxInputChannels\"]})')
"
```

**Try different wake word:**
```yaml
# group_vars/all/main.yml
voice_assistant:
  wake_word: "hey_jarvis"  # or "alexa"
```

Then redeploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

### Service Not Starting

**Check logs:**
```bash
docker logs voice-assistant
```

**Common fixes:**

1. **Missing audio devices:**
   - Ensure microphone is plugged in
   - Check `/dev/snd` exists: `ls -la /dev/snd/`

2. **Dependencies not installed:**
   - Wait for first-run installation (see logs)
   - Or restart container: `docker restart voice-assistant`

3. **Ollama model not pulled:**
   - Check: `docker exec ollama ollama list`
   - Pull manually: `docker exec ollama ollama pull llama3.2:3b`

### Slow Responses

**Switch to faster model:**
```yaml
voice_assistant:
  ollama_model: "llama3.2:1b"  # Faster, slightly less accurate
```

**Or use Phi-3:**
```yaml
voice_assistant:
  ollama_model: "phi3:mini"  # Best speed/quality balance
```

### Poor Recognition

**Upgrade Whisper model:**
```yaml
homeassistant:
  services:
    wyoming_whisper:
      model: "base-int8"  # Better quality, slower
```

## Advanced Configuration

### Change Wake Word

Available options:
- `ok_nabu` (default)
- `hey_jarvis`
- `alexa`
- `hey_mycroft`
- `hey_rhasspy`

Edit `group_vars/all/main.yml`:
```yaml
voice_assistant:
  wake_word: "hey_jarvis"
```

### Change Voice

Available voices:
- `en_US-lessac-medium` (default, clear American)
- `en_AU-southern-female` (Australian)
- `de_DE-thorsten-medium` (German)

Edit `group_vars/all/main.yml`:
```yaml
voice_assistant:
  piper_voice: "en_AU-southern-female"
```

### Adjust Sensitivity

Make it more/less sensitive to sound:

```yaml
voice_assistant:
  audio:
    silence_threshold: 300  # Lower = more sensitive (default: 500)
    silence_duration: 2.0   # Longer pause before stopping (default: 1.5)
```

## Useful Commands

### Check Service Status
```bash
# All voice services
docker ps | grep -E "voice|piper|whisper|wake"

# Just the assistant
docker ps | grep voice-assistant

# Check if running
docker inspect voice-assistant --format='{{.State.Status}}'
```

### View Logs
```bash
# Live logs
docker logs -f voice-assistant

# Last 50 lines
docker logs --tail 50 voice-assistant

# With timestamps
docker logs -f --timestamps voice-assistant
```

### Restart Services
```bash
# Restart just the assistant
docker restart voice-assistant

# Restart all automation services
docker compose -f /opt/frey/stacks/automation/docker-compose.yml restart
```

### Manage Ollama Models
```bash
# List installed models
docker exec ollama ollama list

# Pull a model
docker exec ollama ollama pull llama3.2:1b

# Remove a model
docker exec ollama ollama rm llama3.2:3b

# Check model info
docker exec ollama ollama show llama3.2:3b
```

### Update Voice Assistant Code
```bash
# Re-run just the voice assistant deployment
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation

# Then restart
docker restart voice-assistant
```

## Performance Tips

### For Raspberry Pi 5 (16GB)
✅ Use `llama3.2:3b` - optimal balance
✅ Whisper `tiny-int8` or `base-int8`
✅ Multiple Piper voices OK

### For Raspberry Pi 5 (8GB)
⚠️ Use `llama3.2:1b` or `phi3:mini`
⚠️ Whisper `tiny-int8` only
⚠️ Single Piper voice

### For Raspberry Pi 4 or 5 (4GB)
❌ Voice assistant not recommended
❌ Use Home Assistant voice pipeline instead

## Next Steps

1. **Read full documentation:** `docs/VOICE_ASSISTANT.md`
2. **Customize commands:** Edit `/opt/frey/appdata/voice-assistant/system_commands.py`
3. **Train custom wake word:** Place model in `/opt/frey/appdata/openwakeword/custom_models/`
4. **Enable more features:**
   ```yaml
   voice_assistant:
     capabilities:
       home_automation: true  # Control Home Assistant devices
       media_control: true    # Control Jellyfin playback
   ```

## Support

**Logs show errors?** Check `/docs/VOICE_ASSISTANT.md` troubleshooting section

**Feature requests?** Open an issue on GitHub

**Questions?** Check the full documentation first!

## Remember

- Wake word: **"OK Nabu"** (or your configured word)
- Be clear and speak at normal volume
- Wait for "Yes, how can I help?" before speaking
- Pause briefly before ending your command
- Check logs if something doesn't work: `docker logs -f voice-assistant`

**Enjoy your local voice assistant! 🎤**
