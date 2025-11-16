# Frey Voice Assistant

A local, privacy-focused voice assistant for managing your Frey server via voice commands. Think of it as your own self-hosted Alexa for system administration.

## Overview

The Frey Voice Assistant provides a complete voice interaction pipeline running entirely on your Raspberry Pi 5:

- **Wake Word Detection**: Say "OK Nabu" to activate
- **Speech-to-Text**: Powered by Whisper (highly accurate)
- **Natural Language Understanding**: Powered by Llama 3.2 3B via Ollama
- **System Control**: Start/stop Docker services, check system status
- **Text-to-Speech**: Natural voice responses via Piper TTS

**Everything runs locally** - no cloud services, no data leaving your network.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Voice Pipeline                           │
│                                                              │
│  1. Wake Word    →  2. Listen    →  3. Transcribe           │
│  (OpenWakeWord)     (PyAudio)       (Whisper)                │
│                                                              │
│  ↓                                                           │
│                                                              │
│  4. Understand   →  5. Execute   →  6. Respond              │
│  (Llama 3.2)        (Commands)      (Piper TTS)             │
└─────────────────────────────────────────────────────────────┘
```

### Components

1. **OpenWakeWord** - Listens for "OK Nabu" wake word
2. **Whisper** - Converts speech to text (STT)
3. **Ollama (Llama 3.2 3B)** - Understands intent and generates responses
4. **System Command Handler** - Executes Docker and system commands
5. **Piper TTS** - Converts responses to natural speech

## Configuration

### Enable Voice Assistant

The voice assistant is configured in `group_vars/all/main.yml`:

```yaml
voice_assistant:
  deploy: true  # Set to false to disable

  # Wake word (available: ok_nabu, hey_jarvis, alexa, hey_mycroft)
  wake_word: "ok_nabu"

  # LLM model for Raspberry Pi 5 (16GB RAM)
  # Recommended: llama3.2:3b (fast, good quality)
  # Alternatives: phi3:mini, qwen2.5:3b, llama3.2:1b
  ollama_model: "llama3.2:3b"

  # Text-to-Speech voice
  piper_voice: "en_US-lessac-medium"

  # System capabilities
  capabilities:
    docker_control: true      # Allow starting/stopping containers
    service_status: true      # Allow checking service status
    system_info: true         # Allow system information queries
    media_control: false      # Future: Jellyfin control
    home_automation: false    # Future: Home Assistant integration
```

### Model Recommendations for Raspberry Pi 5

| Model | Size | Speed | Quality | RAM Usage |
|-------|------|-------|---------|-----------|
| **llama3.2:3b** ✅ | 3B | Fast | Excellent | ~2GB |
| phi3:mini | 3.8B | Very Fast | Good | ~2.3GB |
| qwen2.5:3b | 3B | Fast | Good | ~2GB |
| llama3.2:1b | 1B | Very Fast | Fair | ~1GB |

**Avoid 7B+ models** - they will be very slow on the Pi 5.

### Wake Word Options

Available wake words:
- `ok_nabu` (Default - best general option)
- `hey_jarvis` (Iron Man style)
- `alexa` (Amazon Alexa style)
- `hey_mycroft` (Mycroft AI style)
- `hey_rhasspy` (Rhasspy assistant style)

You can also train custom wake words by placing models in `/opt/frey/appdata/openwakeword/custom_models/`.

## Deployment

### Initial Setup

1. **Configure** the voice assistant in `group_vars/all/main.yml` (see above)

2. **Deploy** using Ansible:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
   ```

3. **Verify** services are running:
   ```bash
   docker ps | grep -E "voice-assistant|openwakeword|piper|whisper|ollama"
   ```

4. **Check logs**:
   ```bash
   docker logs -f voice-assistant
   ```

### Model Pulling

The Ollama model is automatically pulled during deployment. To manually pull or change models:

```bash
# Pull a specific model
docker exec ollama ollama pull llama3.2:3b

# List available models
docker exec ollama ollama list

# Remove a model
docker exec ollama ollama rm llama3.2:3b
```

## Usage

### Basic Voice Commands

**Service Control:**
- "Start Jellyfin"
- "Stop Sonarr"
- "Restart Radarr"

**Service Status:**
- "Is Jellyfin running?"
- "What services are running?"
- "Check status of Portainer"

**System Information:**
- "What's the CPU usage?"
- "How much memory is available?"
- "What's the disk usage?"

**Conversation:**
- "What can you do?"
- "Tell me about yourself"
- "What time is it?"

### Example Interactions

```
You: "OK Nabu"
Frey: "Yes, how can I help?"

You: "Start Jellyfin"
Frey: "Starting Jellyfin now. Jellyfin has been started."

You: "What's the CPU usage?"
Frey: "CPU usage is 15.3%. Memory usage is 4.2GB of 16GB. Disk usage is 45%."

You: "Is Sonarr running?"
Frey: "Sonarr is running."
```

## Service Aliases

The voice assistant understands various service names:

| You Say | Service Name |
|---------|-------------|
| "Jellyfin" / "Jelly Fin" | jellyfin |
| "Sonar" / "Sonarr" | sonarr |
| "Radar" / "Radarr" | radarr |
| "Bazaar" / "Bazarr" | bazarr |
| "Audiobook Shelf" | audiobookshelf |
| "Torrent" / "qBittorrent" | qbittorrent |
| "Home Assistant" | homeassistant |
| "Traffic" / "Traefik" | traefik |

## Troubleshooting

### Voice Assistant Not Starting

**Check logs:**
```bash
docker logs voice-assistant
```

**Common issues:**
- Audio devices not accessible → Check container has `/dev/snd` access
- Services not ready → Wait 30-60s after stack starts
- Python dependencies missing → Container will auto-install on first run

### Wake Word Not Detecting

**Verify OpenWakeWord is running:**
```bash
docker logs openwakeword
```

**Test audio input:**
```bash
docker exec -it voice-assistant python3 -c "import pyaudio; p = pyaudio.PyAudio(); print(f'Audio devices: {p.get_device_count()}')"
```

**Try different wake word:**
Edit `group_vars/all/main.yml` and change `wake_word` to `hey_jarvis` or `alexa`.

### Speech Recognition Poor Quality

**Upgrade Whisper model:**
Edit `group_vars/all/main.yml`:
```yaml
homeassistant:
  services:
    wyoming_whisper:
      model: "base-int8"  # Change from tiny-int8
```

**Note:** Larger models are more accurate but slower.

### LLM Responses Too Slow

**Switch to faster model:**
```yaml
voice_assistant:
  ollama_model: "llama3.2:1b"  # Faster, slightly lower quality
```

Or use phi3:mini for best speed/quality balance.

### Command Not Executing

**Check Docker socket access:**
```bash
docker exec voice-assistant ls -la /var/run/docker.sock
```

**Verify command handler:**
```bash
docker logs voice-assistant | grep "Docker client initialized"
```

**Check service name:**
Use `docker ps` to verify exact container names.

## Advanced Configuration

### Custom Wake Words

1. Train your custom wake word using OpenWakeWord trainer
2. Place the `.tflite` model file in `/opt/frey/appdata/openwakeword/custom_models/`
3. Update configuration:
   ```yaml
   voice_assistant:
     wake_word: "your_custom_word"
   ```

### Audio Configuration

Adjust audio settings in `group_vars/all/main.yml`:

```yaml
voice_assistant:
  audio:
    sample_rate: 16000          # Audio quality (Hz)
    silence_threshold: 500      # Sensitivity (lower = more sensitive)
    silence_duration: 1.5       # Seconds of silence before stopping
```

### Adding New Capabilities

Edit `/opt/frey/appdata/voice-assistant/system_commands.py` to add custom commands.

Example - Add weather command:
```python
def get_weather(self) -> str:
    """Get current weather."""
    # Your weather API integration here
    return "The weather is sunny, 22 degrees."
```

## Security Considerations

### Protected Services

The voice assistant **cannot** stop these critical services:
- voice-assistant (itself)
- ollama
- piper
- wyoming-whisper
- openwakeword

This prevents accidental self-shutdown.

### Docker Socket Access

The assistant has **read-only** access to Docker socket for security. It can:
- ✅ List containers
- ✅ Start/stop containers
- ✅ Check container status
- ❌ Remove containers
- ❌ Modify Docker daemon
- ❌ Access host filesystem (except /dev/snd)

### Privacy

All processing happens **locally**:
- ✅ No cloud API calls
- ✅ No data sent to external services
- ✅ Voice recordings not stored
- ✅ Fully offline capable

## Performance Tuning

### Raspberry Pi 5 Optimization

**For 16GB RAM:**
- Use `llama3.2:3b` (recommended)
- Whisper: `tiny-int8` or `base-int8`
- Can run multiple Piper voices

**For 8GB RAM:**
- Use `llama3.2:1b` or `phi3:mini`
- Whisper: `tiny-int8` only
- Single Piper voice recommended

**For 4GB RAM:**
- Voice assistant not recommended
- Consider Home Assistant voice pipeline instead

### CPU Usage

Monitor CPU usage:
```bash
docker stats voice-assistant ollama piper wyoming-whisper
```

If CPU is consistently >80%:
1. Switch to smaller model (`llama3.2:1b`)
2. Reduce Whisper model size (`tiny-int8`)
3. Increase silence detection threshold (fewer false triggers)

## Integration

### Home Assistant

The voice assistant can be integrated with Home Assistant for smart home control (future feature).

Enable in configuration:
```yaml
voice_assistant:
  capabilities:
    home_automation: true
```

### n8n Workflows

Trigger n8n workflows via voice:
```yaml
voice_assistant:
  capabilities:
    workflow_trigger: true
```

## Roadmap

Planned features:
- [ ] Home Assistant device control
- [ ] Jellyfin media playback control
- [ ] n8n workflow triggers
- [ ] Multi-user voice profiles
- [ ] Spotify/Music control
- [ ] Calendar integration
- [ ] Reminder/Timer functionality

## Architecture Details

### Voice Pipeline Flow

1. **Continuous Wake Word Monitoring**
   - 100ms audio chunks sent to OpenWakeWord
   - ~5-10ms latency per check
   - Low CPU usage when idle

2. **Activation & Recording**
   - Wake word detected → Play acknowledgment
   - Start recording with silence detection
   - Max 10 seconds, auto-stop after 1.5s silence

3. **Speech-to-Text**
   - Send WAV audio to Whisper
   - Transcription typically 2-5 seconds
   - Returns text string

4. **Intent Recognition**
   - Send transcribed text to Llama 3.2
   - LLM analyzes intent and extracts parameters
   - Returns structured command or conversational response
   - Processing: 1-3 seconds on Pi 5

5. **Command Execution**
   - If system command → Execute via Docker API
   - Return result to LLM for response generation

6. **Text-to-Speech**
   - Send response text to Piper
   - Generate audio (typically <1 second)
   - Play through speakers

**Total latency:** ~5-12 seconds from speech to response

## File Locations

- **Configuration:** `/home/user/frey/group_vars/all/main.yml`
- **Docker Compose:** `/opt/frey/stacks/automation/docker-compose.yml`
- **Python Code:** `/opt/frey/appdata/voice-assistant/`
- **Ollama Models:** `/opt/frey/appdata/ollama/`
- **Piper Voices:** `/opt/frey/appdata/piper/`
- **Whisper Models:** `/opt/frey/appdata/wyoming-whisper/`
- **Wake Word Models:** `/opt/frey/appdata/openwakeword/`

## Contributing

To improve the voice assistant:

1. **Enhance LLM prompts:** Edit `ollama_client.py.j2` system prompt
2. **Add service aliases:** Edit `system_commands.py.j2` service_aliases dict
3. **Improve wake word detection:** Adjust OpenWakeWord sensitivity
4. **Add new capabilities:** Extend `SystemCommandHandler` class

## Support

For issues or questions:
- Check logs: `docker logs -f voice-assistant`
- Review troubleshooting section above
- Check Frey GitHub issues: https://github.com/Jim8Knopf/frey/issues

## Credits

Built with:
- [Ollama](https://ollama.ai/) - Local LLM runtime
- [Whisper](https://github.com/openai/whisper) - Speech recognition
- [Piper](https://github.com/rhasspy/piper) - Text-to-speech
- [OpenWakeWord](https://github.com/dscripka/openWakeWord) - Wake word detection
- [Wyoming Protocol](https://github.com/rhasspy/wyoming) - Voice service communication
