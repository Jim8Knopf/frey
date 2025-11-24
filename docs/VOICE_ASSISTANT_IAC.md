# Voice Assistant - Infrastructure as Code Setup

## Overview

The Frey voice assistant is **fully configured via Ansible** - no manual UI configuration required! This document explains how the automated setup works.

## What Gets Deployed Automatically

When you run the Ansible playbook with voice_assistant enabled, the following is automatically configured:

### 1. Docker Containers
- **Home Assistant**: Main automation hub
- **OpenWakeWord**: Wake word detection ("ok_nabu")
- **Whisper (Wyoming)**: Speech-to-text
- **Piper (Wyoming)**: Text-to-speech
- **Ollama**: LLM for conversation and function calling

### 2. Home Assistant Configuration Files

All configuration files are deployed automatically to `/opt/frey/appdata/homeassistant/`:

**Main configuration** (`configuration.yaml`):
- Enables packages for modular configuration
- Configures HTTP trusted proxies
- Sets up recorder, logger, TTS

**Voice package** (`packages/frey_voice.yaml`):
- Ollama conversation agent with full system prompt
- Shell commands for Docker control
- Scripts for function calling (start/stop/restart/status)
- RAG knowledge base queries (if enabled)
- Assist pipeline configuration
- Wyoming integrations (wake word, STT, TTS)
- Voice command logging automation

**Supporting files**:
- `automations.yaml` - For UI-created automations
- `scripts.yaml` - For UI-created scripts
- `scenes.yaml` - For UI-created scenes
- `secrets.yaml` - For sensitive values

### 3. System Scripts
- **frey-docker-control**: Smart Docker container control with fuzzy matching
- Deployed to `/usr/local/bin/frey-docker-control`

### 4. Ollama Models
Automatically pulled during deployment:
- `llama3.2:3b` - Primary model for voice + RAG
- `nomic-embed-text` - Embeddings for RAG (if enabled)
- `qwen2.5:14b` - Reasoning model (if enabled)

## Configuration Variables

All configuration is done in `group_vars/all/main.yml`:

```yaml
voice_assistant:
  enabled: true
  wake_word: "ok_nabu"
  ollama_model: "llama3.2:3b"

rag:
  enabled: true  # For document-based Q&A

task_scheduler:
  enabled: true  # For overnight reasoning tasks
```

## How the IaC Works

### Packages Architecture

Home Assistant supports "packages" - a way to organize configuration into logical groups. The Frey voice assistant uses this approach:

**Main config includes packages**:
```yaml
homeassistant:
  packages: !include_dir_named packages/
```

**Voice package** (`packages/frey_voice.yaml`) contains:
- Conversation agent configuration
- Shell commands
- Scripts for function calling
- Pipeline configuration
- Wyoming integrations

This approach:
- ✅ Keeps voice config separate from other HA config
- ✅ Allows version control of voice settings
- ✅ Enables automated deployment
- ✅ Doesn't conflict with UI-created automations

### Function Calling Architecture

The system uses a **script bridge pattern**:

1. **User speaks**: "Hey Nabu, start Jellyfin"
2. **Ollama understands intent** and parameters
3. **Ollama calls script**: `script.frey_docker_start` with `service: "jellyfin"`
4. **Script calls shell command**: `shell_command.frey_docker` with `action: "start"`, `service: "jellyfin"`
5. **Shell command executes**: `/usr/local/bin/frey-docker-control start jellyfin`
6. **Result returns** through the chain
7. **Ollama speaks response**: "I've started Jellyfin"

This architecture:
- ✅ Works with Home Assistant's conversation agent
- ✅ Provides clear separation of concerns
- ✅ Easy to debug (check logs at each layer)
- ✅ Fully configurable via YAML

### Smart Model Loading

Ollama is configured to only load one model at a time:

```yaml
environment:
  - OLLAMA_NUM_PARALLEL=1
  - OLLAMA_MAX_LOADED_MODELS=1
  - OLLAMA_KEEP_ALIVE=10m
```

Models auto-load on demand:
- Voice command → llama3.2:3b loads
- RAG query → Same model, different context
- Overnight task → qwen2.5:14b loads (unloads in morning)

## Deployment Workflow

### Initial Deployment

```bash
# 1. Configure in group_vars/all/main.yml
vim group_vars/all/main.yml

# 2. Deploy with Ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation

# 3. Wait for containers to start (~2 minutes)
docker ps | grep -E 'homeassistant|ollama|piper|whisper|openwakeword'

# 4. Wait for Home Assistant to load config (~1 minute)
docker logs homeassistant -f

# 5. Access Home Assistant
open http://homeassistant.frey:8123

# 6. Test voice assistant
# Say: "Hey Nabu"
# Then: "What services are running?"
```

### Configuration Updates

When you modify voice configuration:

```bash
# 1. Edit configuration
vim roles/automation/templates/homeassistant/packages/frey_voice.yaml.j2

# 2. Re-deploy
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation

# 3. Home Assistant automatically restarts (via handler)
# Configuration reloaded automatically
```

The Ansible handler automatically restarts Home Assistant when configuration changes are detected.

## What You DON'T Need To Do

❌ No manual Home Assistant UI configuration
❌ No manual integration setup
❌ No manual voice pipeline creation
❌ No manual function definition
❌ No manual wake word configuration

Everything is **Infrastructure as Code**!

## Verification

### Check Configuration is Loaded

```bash
# SSH to your Pi
ssh pi@frey.local

# Check Home Assistant logs for successful config load
docker logs homeassistant 2>&1 | grep -i "frey_voice\|conversation\|ollama"

# Should see:
# - Loading package frey_voice
# - Setup of ollama conversation platform
# - Wyoming integrations loaded
```

### Check Scripts are Available

In Home Assistant:
1. Developer Tools → Services
2. Search for "frey"
3. Should see:
   - `script.frey_docker_start`
   - `script.frey_docker_stop`
   - `script.frey_docker_restart`
   - `script.frey_docker_status`
   - `script.frey_list_services`
   - `script.frey_system_info`
   - `script.frey_query_knowledge` (if RAG enabled)

### Check Voice Pipeline

1. Settings → Voice assistants
2. Should see "Frey Voice Assistant" pipeline
3. Components should show:
   - Wake word: OpenWakeWord (ok_nabu)
   - STT: Wyoming Whisper
   - Conversation: Ollama (llama3.2:3b)
   - TTS: Piper (en_US-lessac-medium)

### Test Voice Commands

Say the wake word: "Hey Nabu" or "Ok Nabu"
- LED should indicate wake word detected

Then say a command:
- "What services are running?"
- "Start Jellyfin"
- "Is Sonarr running?"
- "What's the system status?"

If RAG is enabled:
- "What are the best restaurants in Tokyo?"

## Customization

### Change Wake Word

Edit `group_vars/all/main.yml`:

```yaml
voice_assistant:
  wake_word: "hey_jarvis"  # or alexa, hey_mycroft, hey_rhasspy
```

Re-deploy:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

### Change LLM Model

Edit `group_vars/all/main.yml`:

```yaml
voice_assistant:
  ollama_model: "phi3:mini"  # or qwen2.5:3b, llama3.2:1b
```

Re-deploy and the new model will be pulled automatically.

### Change TTS Voice

Edit `group_vars/all/main.yml`:

```yaml
homeassistant:
  services:
    piper:
      default_voice: "en_GB-alba-medium"  # British accent
```

Available voices: https://github.com/rhasspy/piper/blob/master/VOICES.md

### Add Custom Shell Commands

Edit `roles/automation/templates/homeassistant/packages/frey_voice.yaml.j2`:

```yaml
shell_command:
  # ... existing commands ...

  my_custom_command: "/path/to/my/script.sh {{ '{{' }} param {{ '}}' }}"
```

Add corresponding script:

```yaml
script:
  my_custom_script:
    alias: "My Custom Action"
    fields:
      param:
        description: "Parameter description"
    sequence:
      - service: shell_command.my_custom_command
        data:
          param: "{{ '{{' }} param {{ '}}' }}"
```

Update Ollama system prompt to tell it about the new command.

### Modify System Prompt

The system prompt tells Ollama how to use the voice assistant. Edit it in:

`roles/automation/templates/homeassistant/packages/frey_voice.yaml.j2`

Look for the `conversation:` section and modify the `prompt:` field.

## Troubleshooting

### Configuration not loading

```bash
# Check for YAML syntax errors
docker exec homeassistant python3 -m homeassistant --script check_config
```

### Scripts not showing up

```bash
# Check if package was loaded
docker logs homeassistant 2>&1 | grep frey_voice

# Check for errors
docker logs homeassistant 2>&1 | grep -i error
```

### Ollama not responding

```bash
# Check Ollama is running
docker ps | grep ollama

# Check model is loaded
curl http://ollama.frey:11434/api/ps

# Check Ollama logs
docker logs ollama -f
```

### Voice commands not working

```bash
# Check each component separately

# 1. Wake word
docker logs openwakeword -f
# Say "Ok Nabu" - should see detection

# 2. STT
docker logs wyoming-whisper -f
# Speak - should see transcription

# 3. Conversation (Ollama)
docker logs homeassistant 2>&1 | grep conversation
# Should see requests to Ollama

# 4. TTS
docker logs piper -f
# Should see synthesis requests
```

### Handler not restarting HA

If Home Assistant doesn't auto-restart after config changes:

```bash
# Manual restart
docker restart homeassistant

# Check handler was triggered
# Look for "RUNNING HANDLER [automation : Restart Home Assistant]" in Ansible output
```

## Architecture Benefits

### Why This Approach is Better

**Traditional approach** (manual UI config):
- ❌ Manual setup required for each deployment
- ❌ Configuration not version controlled
- ❌ Hard to replicate across systems
- ❌ Easy to forget steps
- ❌ No automated testing possible

**IaC approach** (this implementation):
- ✅ One-command deployment
- ✅ All config in version control
- ✅ Reproducible across systems
- ✅ Self-documenting (Jinja2 templates)
- ✅ Can be tested in CI/CD
- ✅ Easy to roll back changes

### Comparison to Other Projects

Most Home Assistant voice assistant projects require:
1. Installing Home Assistant
2. Manually configuring integrations via UI
3. Manually creating voice pipeline
4. Manually defining scripts
5. Manually configuring wake word
6. Manually setting up Ollama

Frey does all this in **one Ansible command** ✅

## Advanced Topics

### Multiple Voice Assistants

To add multiple voice assistants (different languages, models, etc):

1. Create additional packages:
   - `packages/frey_voice_german.yaml.j2`
   - `packages/frey_voice_spanish.yaml.j2`

2. Each package can have different:
   - Ollama models
   - TTS voices
   - System prompts
   - Shell commands

3. Deploy with Ansible - all loaded automatically

### Integration with External Services

Add external service calls in shell_command:

```yaml
shell_command:
  notify_phone: "curl -X POST https://ntfy.sh/frey -d '{{ '{{' }} message {{ '}}' }}'"

  control_lights: "curl -X POST http://hue-bridge/api/... -d '{{ '{{' }} state {{ '}}' }}'"
```

### Conditional Features

Use Jinja2 conditionals to enable features based on configuration:

```yaml
{% if features.media | default(false) %}
shell_command:
  play_media: "curl http://jellyfin.frey/..."
{% endif %}
```

### Security Hardening

For production use:

1. Enable Home Assistant authentication
2. Use HTTPS (Traefik TLS)
3. Restrict shell command execution
4. Use Ansible Vault for secrets
5. Enable fail2ban for HA login attempts

## References

- [Home Assistant Packages](https://www.home-assistant.io/docs/configuration/packages/)
- [Home Assistant Conversation](https://www.home-assistant.io/integrations/conversation/)
- [Home Assistant Assist](https://www.home-assistant.io/voice_control/)
- [Wyoming Protocol](https://github.com/rhasspy/wyoming)
- [Ollama](https://ollama.ai/)

## Next Steps

- Read [AI_ARCHITECTURE.md](AI_ARCHITECTURE.md) for multi-modal AI system details
- Read [AI_QUICKSTART.md](AI_QUICKSTART.md) for quick setup guide
- Check [VOICE_ASSISTANT.md](VOICE_ASSISTANT.md) for usage examples
