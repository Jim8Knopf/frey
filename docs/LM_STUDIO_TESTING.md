# Testing Fine-Tuned Models with LM Studio

## Why Use LM Studio for Testing?

After fine-tuning on Google Colab, you can test your model on your desktop **before** deploying to the Pi:

✅ **Visual chat interface** - Test conversations easily
✅ **Faster iteration** - No need to deploy to Pi for every test
✅ **Side-by-side comparison** - Load multiple models and compare
✅ **Prompt engineering** - Tweak system prompts visually

## Workflow

### Step 1: Download LM Studio

**Download:** https://lmstudio.ai/

Available for:
- Windows
- macOS
- Linux

### Step 2: Download Your Fine-Tuned Model from Colab

After training in Google Colab:

```python
# In Colab - Download the GGUF file
from google.colab import files

# This will download to your computer
files.download("frey-assistant-q4_k_m.gguf")
```

### Step 3: Load in LM Studio

1. Open LM Studio
2. Click **"Load Model"**
3. Select **"Load from file"** (not "Search models")
4. Browse to your downloaded `frey-assistant-q4_k_m.gguf`
5. Click **"Load"**

### Step 4: Test Your Model

**Chat Tab:**
1. Click **"Chat"** in left sidebar
2. Set system prompt to match your Frey assistant:

```
You are Frey, a helpful voice assistant for managing a home server.

You can control Docker containers using function calls in this format:
<function_call>frey_docker_start(service="jellyfin")</function_call>

Available functions:
- frey_docker_start(service="<name>")
- frey_docker_stop(service="<name>")
- frey_docker_restart(service="<name>")
- frey_system_info()
- frey_list_services()

When users request these actions, use the function call format.
Be helpful, concise, and professional.
```

3. **Test various commands:**
   - "Start Jellyfin"
   - "What's the system status?"
   - "Stop all media services"
   - "Thanks Frey"

### Step 5: Compare Models

Load multiple models to compare:
- Your fine-tuned model
- Stock Llama 3.2 3B
- Stock Qwen 2.5 3B

**In Chat settings:**
- Switch between models using dropdown
- Compare how each responds to the same prompt

### Step 6: Refine and Retrain

If your model doesn't behave as expected:

1. **Document the failures** - Save chat transcripts
2. **Add to dataset** - Create new training examples
3. **Retrain on Colab** (FREE!)
4. **Test again in LM Studio**
5. **Deploy to Pi** when satisfied

## When to Deploy to Pi

Only deploy after you've confirmed in LM Studio that:
- ✅ Model understands function call syntax
- ✅ Personality matches your expectation
- ✅ Handles your most common commands correctly
- ✅ Edge cases are handled appropriately

## LM Studio Settings for Frey Model

**Inference Settings (match Ollama config):**

```
Temperature: 0.7
Top P: 0.9
Context Length: 4096
GPU Layers: Auto (or 0 if testing CPU performance)
```

**These match your Ollama deployment:**
```yaml
# From frey_voice.yaml
options:
  temperature: 0.7
  top_p: 0.9
  num_ctx: 4096
```

## Exporting from LM Studio to Ollama

Once satisfied, you can export the model in Ollama format:

**Option 1: Use the GGUF directly**
```bash
# On Pi
docker cp frey-assistant-q4_k_m.gguf ollama:/tmp/

docker exec ollama sh -c 'cat > /tmp/Modelfile << EOF
FROM /tmp/frey-assistant-q4_k_m.gguf
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER num_ctx 4096
EOF'

docker exec ollama ollama create frey-assistant -f /tmp/Modelfile
```

**Option 2: Transfer via Ansible** (follow main guide)

## Tips

### Compare Response Quality

**Stock Model:**
> "Sure, I'll start Jellyfin for you."

**Your Fine-Tuned Model:**
> "Certainly! Starting Jellyfin now. <function_call>frey_docker_start(service=\"jellyfin\")</function_call> Your media server will be ready in a moment."

The fine-tuned version should:
- Use personality ("Certainly!" like KITT)
- Include proper function call
- Add helpful context

### Test Edge Cases

- **Ambiguous commands:** "Turn on the server" (which service?)
- **Invalid requests:** "Stop Home Assistant" (should refuse)
- **Casual chat:** "Thanks Frey" (should be friendly, not robotic)
- **Multiple actions:** "Start Jellyfin and Sonarr"

### Performance Testing

LM Studio shows:
- **Tokens/second** - Should be ~10-20 on a decent laptop
- **RAM usage** - ~5-6GB for Q4_K_M quantized 7B-8B models
- **Load time** - How fast model loads

This helps predict Pi performance (Pi 5 is slower, ~3-5 tokens/sec).

## Troubleshooting

### Model loads but gives nonsense responses

**Problem:** GGUF might be corrupted during download

**Solution:**
1. Re-download from Colab
2. Verify file size matches (should be ~4.5GB for Q4_K_M 7B-8B models)
3. Try loading in LM Studio again

### Function calls aren't formatted correctly

**Problem:** Model didn't learn the pattern well

**Solution:**
1. Add more function call examples to dataset (aim for 15-20 per function)
2. Vary the phrasing more
3. Retrain with more epochs (try 5 instead of 3)

### Personality is too generic

**Problem:** Not enough personality examples in dataset

**Solution:**
1. Add more conversational examples
2. Strengthen system prompt in LM Studio
3. Include personality in **every** response example during training

## LM Studio vs Ollama: Quick Reference

| Task | Tool | Why |
|------|------|-----|
| **Training** | Google Colab | FREE GPU |
| **Testing/Development** | LM Studio | Visual interface |
| **Production (Pi)** | Ollama | Headless, Docker-friendly |
| **Dataset Creation** | LM Studio | Interactive testing |
| **Voice Assistant** | Ollama | Home Assistant integration |

## Recommended Workflow

```
┌─────────────────┐
│ Google Colab    │  Fine-tune model (FREE)
│ (Training)      │
└────────┬────────┘
         │
         ▼ Download GGUF
┌─────────────────┐
│ LM Studio       │  Test & refine
│ (Your Desktop)  │  Compare models
└────────┬────────┘  Iterate dataset
         │
         │ Satisfied?
         ▼
┌─────────────────┐
│ Ollama          │  Production deployment
│ (Raspberry Pi)  │  Voice assistant
└─────────────────┘
```

## Next Steps

1. **Install LM Studio** on your desktop/laptop
2. **Fine-tune** your first model on Google Colab (follow main guide)
3. **Test** in LM Studio before deploying to Pi
4. **Iterate** until perfect (retraining is FREE!)
5. **Deploy** to Pi only when you're happy with results

This saves time and prevents deploying untested models to your Pi!

---

**See Also:**
- [GETTING_STARTED_FINETUNING.md](GETTING_STARTED_FINETUNING.md) - Complete fine-tuning workflow
- [AI_QUICKSTART.md](AI_QUICKSTART.md) - Quick reference
- [MODEL_FINETUNING.md](MODEL_FINETUNING.md) - Technical details
