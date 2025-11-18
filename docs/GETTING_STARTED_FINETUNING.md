# Getting Started: Create Your Perfect Talking Car AI

## Complete Step-by-Step Guide

This guide walks you through **everything** - from deployment to creating your perfect custom AI assistant with personality.

**Time required**: 1-2 hours for initial setup, then 30 minutes per iteration

**Cost**: $0.00 (completely free!)

---

## Part 1: Initial Deployment (30 minutes)

### Step 1: Deploy the Base System

First, deploy Frey with voice assistant enabled:

```bash
# 1. Configure features
vim group_vars/all/main.yml

# Make sure these are enabled:
voice_assistant:
  enabled: true
  wake_word: "ok_nabu"
  ollama_model: "llama3.2:3b"  # We'll replace this later

rag:
  enabled: true  # For knowledge base queries

task_scheduler:
  enabled: true  # For overnight reasoning tasks
```

```bash
# 2. Deploy with Ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation

# This will take ~10-15 minutes
# It will:
# - Deploy all Docker containers
# - Configure Home Assistant
# - Pull AI models
# - Set up voice pipeline
```

### Step 2: Test Basic Functionality

```bash
# SSH to your Pi
ssh pi@frey.local

# Check all services are running
docker ps | grep -E 'ollama|homeassistant|piper|whisper|openwakeword'

# Test Ollama
docker exec -it ollama ollama run llama3.2:3b
>>> Hello
# Should respond

# Test Home Assistant
curl http://homeassistant.frey:8123
# Should return HTML
```

### Step 3: Configure Home Assistant Voice

1. Open Home Assistant: `http://homeassistant.frey:8123`
2. Complete initial setup wizard if first time
3. Go to: **Settings → Voice assistants**
4. You should see **"Frey Voice Assistant"** already configured (thanks to IaC!)
5. Test it by speaking the wake word: **"Ok Nabu"**

**At this point you have a working voice assistant with the stock llama3.2:3b model!**

---

## Part 2: Customize Your Dataset (30-60 minutes)

Now let's create a dataset customized for YOUR setup and preferences.

### Step 1: Inventory Your Services

List all the Docker services you want to control:

```bash
# SSH to Pi
ssh pi@frey.local

# List all your containers
docker ps --format "{{.Names}}"
```

**Example output:**
```
jellyfin
sonarr
radarr
prowlarr
bazarr
qbittorrent
grafana
prometheus
homeassistant
ollama
```

**Write these down!** You'll use them in your dataset.

### Step 2: Clone the Personality Template

```bash
# On your local machine (where you have the Frey repo)
cd frey/scripts/finetune

# Copy the template
cp frey_personality_dataset.jsonl my_custom_frey.jsonl

# Now edit it
vim my_custom_frey.jsonl
```

### Step 3: Customize for Your Services

For **each service** you want to control, add 3-5 examples:

#### Template for Each Service:

```jsonl
{"input": "Start [SERVICE]", "output": "[PERSONALITY] <function_call>frey_docker_start(service=\"[service_name]\")</function_call> [CONFIRMATION]"}
{"input": "[CASUAL_VARIANT]", "output": "[PERSONALITY] <function_call>frey_docker_start(service=\"[service_name]\")</function_call> [CONFIRMATION]"}
{"input": "Is [SERVICE] running?", "output": "[PERSONALITY] <function_call>frey_docker_status(service=\"[service_name]\")</function_call>"}
{"input": "Restart [SERVICE]", "output": "[PERSONALITY] <function_call>frey_docker_restart(service=\"[service_name]\")</function_call> [CONFIRMATION]"}
{"input": "Stop [SERVICE]", "output": "[PERSONALITY] <function_call>frey_docker_stop(service=\"[service_name]\")</function_call> [CONFIRMATION]"}
```

#### Real Example for Jellyfin:

```jsonl
{"input": "Start Jellyfin", "output": "Certainly! Starting Jellyfin now. <function_call>frey_docker_start(service=\"jellyfin\")</function_call> Your media server will be ready shortly."}
{"input": "Turn on the media server", "output": "Initiating Jellyfin, your media server. <function_call>frey_docker_start(service=\"jellyfin\")</function_call> Coming online now."}
{"input": "Fire up Jellyfin", "output": "Activating Jellyfin. <function_call>frey_docker_start(service=\"jellyfin\")</function_call> Streaming capabilities incoming."}
{"input": "Is Jellyfin running?", "output": "Let me check Jellyfin's status. <function_call>frey_docker_status(service=\"jellyfin\")</function_call>"}
{"input": "Restart Jellyfin", "output": "Restarting Jellyfin now. <function_call>frey_docker_restart(service=\"jellyfin\")</function_call> This should resolve any issues."}
```

### Step 4: Add Your Personality Preferences

Choose your tone and style:

#### Option A: Professional KITT-style
```jsonl
{"input": "Start Jellyfin", "output": "Affirmative. Initiating Jellyfin media server. <function_call>frey_docker_start(service=\"jellyfin\")</function_call> Stand by."}
{"input": "Thanks Frey", "output": "You're welcome. I remain at your service."}
{"input": "Good morning", "output": "Good morning. All systems operational. How may I assist you?"}
```

#### Option B: Friendly Casual
```jsonl
{"input": "Start Jellyfin", "output": "Sure thing! Getting Jellyfin up and running. <function_call>frey_docker_start(service=\"jellyfin\")</function_call>"}
{"input": "Thanks Frey", "output": "No problem! Happy to help anytime."}
{"input": "Good morning", "output": "Morning! Everything's running smoothly. What can I do for you?"}
```

#### Option C: Enthusiastic Helper
```jsonl
{"input": "Start Jellyfin", "output": "Absolutely! Firing up Jellyfin right now! <function_call>frey_docker_start(service=\"jellyfin\")</function_call> Your entertainment awaits!"}
{"input": "Thanks Frey", "output": "My pleasure! I love helping out!"}
{"input": "Good morning", "output": "Good morning! All systems are running perfectly and ready for action!"}
```

**Pick ONE style and stay consistent!**

### Step 5: Add Your Specific Use Cases

Think about how YOU actually talk to your assistant:

**Example - If you often check multiple services:**
```jsonl
{"input": "Is the media stack up?", "output": "Checking the media stack now. <function_call>frey_docker_status(service=\"jellyfin\")</function_call> <function_call>frey_docker_status(service=\"sonarr\")</function_call> <function_call>frey_docker_status(service=\"radarr\")</function_call>"}
{"input": "Check all arr services", "output": "Running diagnostics on all arr services. <function_call>frey_docker_status(service=\"sonarr\")</function_call> <function_call>frey_docker_status(service=\"radarr\")</function_call> <function_call>frey_docker_status(service=\"lidarr\")</function_call> <function_call>frey_docker_status(service=\"prowlarr\")</function_call> <function_call>frey_docker_status(service=\"bazarr\")</function_call>"}
```

**Example - If you use RAG for travel planning:**
```jsonl
{"input": "What should I see in Tokyo?", "output": "Let me search for Tokyo attractions. <function_call>frey_query_knowledge(query=\"Tokyo attractions things to see\")</function_call>"}
{"input": "Where should I eat in Paris?", "output": "Searching for Paris restaurant recommendations. <function_call>frey_query_knowledge(query=\"best restaurants in Paris\")</function_call>"}
{"input": "Tell me about Iceland", "output": "Let me find information about Iceland. <function_call>frey_query_knowledge(query=\"Iceland travel guide information\")</function_call>"}
```

**Example - If you have routines:**
```jsonl
{"input": "Start my morning routine", "output": "Initiating morning routine. <function_call>frey_docker_start(service=\"homeassistant\")</function_call> <function_call>frey_docker_start(service=\"grafana\")</function_call> <function_call>frey_system_info()</function_call> All systems are coming online."}
{"input": "Shut down for the night", "output": "Preparing nighttime shutdown. <function_call>frey_docker_stop(service=\"qbittorrent\")</function_call> <function_call>frey_docker_stop(service=\"jellyfin\")</function_call> Systems powering down. Good night!"}
```

### Step 6: Dataset Size Guidelines

**Minimum (for testing): 30-50 examples**
- Cover basic commands for your most-used services
- Quick to train (~10 min)
- Good for seeing if fine-tuning works

**Recommended (for production): 100-150 examples**
- All your services covered
- Multiple variations per command
- Personality examples
- Edge cases included
- ~15-20 min to train
- **This is the sweet spot!** ✅

**Maximum (diminishing returns): 200+ examples**
- Extensive variations
- Every edge case
- ~30 min to train
- Better, but slower iteration

**Rule of thumb**: Start with 50-100, iterate from there.

### Step 7: Validate Your Dataset

Before training, check your dataset:

```bash
# Count examples
wc -l my_custom_frey.jsonl

# Validate JSON format
python3 -c "
import json
with open('my_custom_frey.jsonl') as f:
    for i, line in enumerate(f, 1):
        try:
            json.loads(line)
        except Exception as e:
            print(f'Line {i}: ERROR - {e}')
            break
    else:
        print('✓ All JSON valid!')
"

# Check for function call format
grep -c "function_call" my_custom_frey.jsonl
# Should match number of lines that need function calls
```

---

## Part 3: Fine-Tune with Google Colab (15-20 minutes)

### Step 1: Prepare for Colab

```bash
# Make sure you have your custom dataset ready
ls -lh my_custom_frey.jsonl

# Optional: Test it locally first
head -5 my_custom_frey.jsonl
```

### Step 2: Open Google Colab

1. Go to: https://colab.research.google.com
2. Sign in with Google account
3. File → New notebook

### Step 3: Set Up GPU

1. Runtime → Change runtime type
2. Hardware accelerator: **GPU**
3. GPU type: **T4** (free tier)
4. Click **Save**

### Step 4: Install Dependencies

**Cell 1:**
```python
# Install Unsloth
%%capture
import torch

# Check GPU
print(f"GPU: {torch.cuda.get_device_name(0)}")
print(f"VRAM: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")

# Install Unsloth (takes ~2 minutes)
!pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"
!pip install --no-deps trl peft accelerate bitsandbytes

print("✓ Installation complete!")
```

**Run this cell** and wait ~2 minutes.

### Step 5: Upload Your Dataset

1. Click the **folder icon** (left sidebar)
2. Click the **upload button**
3. Upload your `my_custom_frey.jsonl` file
4. Wait for upload to complete

**Cell 2 - Verify upload:**
```python
import json

# Check file exists
dataset_file = 'my_custom_frey.jsonl'

with open(dataset_file) as f:
    examples = [json.loads(line) for line in f]

print(f"✓ Dataset loaded: {len(examples)} examples")
print(f"\nFirst example:")
print(f"  Input: {examples[0]['input']}")
print(f"  Output: {examples[0]['output'][:100]}...")
```

### Step 6: Configure Training

**Cell 3 - Configuration:**
```python
# Choose your base model
MODEL = "llama-3.1-8b"  # Recommended for Pi 5
# Other options: "qwen-2.5-7b", "llama-3.1-13b"

# Training settings
NUM_EPOCHS = 3           # How many times to train on dataset
LEARNING_RATE = 2e-4     # Speed of learning
BATCH_SIZE = 2           # Works on free T4 GPU

# Your personality style (optional - just for notes)
PERSONALITY = "Professional KITT-style"  # or "Friendly casual", etc.

print(f"Model: {MODEL}")
print(f"Epochs: {NUM_EPOCHS}")
print(f"Personality: {PERSONALITY}")
```

### Step 7: Load Base Model and Train

**Cell 4 - Load model:**
```python
from unsloth import FastLanguageModel

# Model configuration
MODEL_CONFIGS = {
    "llama-3.1-8b": "unsloth/Meta-Llama-3.1-8B-bnb-4bit",
    "qwen-2.5-7b": "unsloth/Qwen2.5-7B-bnb-4bit",
    "llama-3.1-13b": "unsloth/Meta-Llama-3.1-13B-bnb-4bit",
}

print("Loading base model...")
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name=MODEL_CONFIGS[MODEL],
    max_seq_length=2048,
    dtype=None,
    load_in_4bit=True,
)

# Add LoRA for efficient training
model = FastLanguageModel.get_peft_model(
    model,
    r=16,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                   "gate_proj", "up_proj", "down_proj"],
    lora_alpha=16,
    lora_dropout=0,
    bias="none",
    use_gradient_checkpointing="unsloth",
    random_state=3407,
)

print("✓ Model loaded with LoRA adapters")
```

**Cell 5 - Prepare dataset:**
```python
from datasets import load_dataset

# System prompt for Frey
SYSTEM_PROMPT = """You are Frey, an intelligent AI assistant managing a home server. You have a helpful, friendly personality.

You can control Docker containers, query knowledge bases, and provide system information.

Available functions:
- frey_docker_start(service): Start container
- frey_docker_stop(service): Stop container
- frey_docker_restart(service): Restart container
- frey_docker_status(service): Check status
- frey_list_services(): List all containers
- frey_system_info(): System information
- frey_query_knowledge(query): Query knowledge base

Respond conversationally. Keep it concise for voice output.
Protected services (cannot stop): homeassistant, ollama, traefik"""

def format_prompt(sample):
    """Format for Llama 3.1 chat template"""
    return {"text": f"""<|begin_of_text|><|start_header_id|>system<|end_header_id|>

{SYSTEM_PROMPT}<|eot_id|><|start_header_id|>user<|end_header_id|>

{sample['input']}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

{sample['output']}<|eot_id|>"""}

# Load and format
dataset = load_dataset('json', data_files=dataset_file, split='train')
dataset = dataset.map(format_prompt, remove_columns=dataset.column_names)

print(f"✓ Dataset prepared: {len(dataset)} examples")
```

**Cell 6 - Train! (takes ~10-15 minutes):**
```python
from trl import SFTTrainer
from transformers import TrainingArguments

print("Starting training...")
print("This will take 10-15 minutes. Go grab coffee! ☕")
print("")

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=2048,
    args=TrainingArguments(
        output_dir="./output",
        num_train_epochs=NUM_EPOCHS,
        per_device_train_batch_size=BATCH_SIZE,
        gradient_accumulation_steps=4,
        warmup_steps=5,
        learning_rate=LEARNING_RATE,
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(),
        logging_steps=10,
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="linear",
        seed=3407,
    ),
)

# Train!
trainer.train()

print("\n" + "="*60)
print("✓ Training complete!")
print("="*60)
```

**Wait for this to finish.** You'll see training progress with loss decreasing.

### Step 8: Test Your Model

**Cell 7 - Test before export:**
```python
# Enable fast inference
FastLanguageModel.for_inference(model)

# Test prompts
test_prompts = [
    "Start Jellyfin",
    "Is Sonarr running?",
    "What services are available?",
]

print("Testing your fine-tuned model:\n")

for test_input in test_prompts:
    # Format
    prompt = f"""<|begin_of_text|><|start_header_id|>system<|end_header_id|>

{SYSTEM_PROMPT}<|eot_id|><|start_header_id|>user<|end_header_id|>

{test_input}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

"""

    # Generate
    inputs = tokenizer(prompt, return_tensors="pt").to("cuda")
    outputs = model.generate(**inputs, max_new_tokens=128, temperature=0.7)
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    response = response.split("assistant")[-1].strip()

    print(f"You: {test_input}")
    print(f"Frey: {response}")
    print("-" * 60)
```

**Review the responses!** Do they match your personality? If not, you can adjust your dataset and retrain.

### Step 9: Export to GGUF

**Cell 8 - Export:**
```python
print("Exporting to GGUF format for Raspberry Pi...")
print("Creating Q4_K_M quantization (~4.5GB)")

model.save_pretrained_gguf(
    "frey-model",
    tokenizer,
    quantization_method="q4_k_m",
)

print("✓ Export complete!")
print("\nFiles created:")
!ls -lh frey-model/*.gguf
```

**Cell 9 - Create Modelfile:**
```python
modelfile = f"""# Frey - Your Custom AI Assistant
FROM ./frey-assistant-q4_k_m.gguf

PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.1
PARAMETER num_ctx 2048

SYSTEM {SYSTEM_PROMPT}
"""

with open('frey-model/Modelfile', 'w') as f:
    f.write(modelfile)

print("✓ Modelfile created")
print("\nContents:")
print(modelfile)
```

**Cell 10 - Zip for download:**
```python
!zip -r frey-custom-model.zip frey-model/

print("✓ Created frey-custom-model.zip")
print("\nReady to download!")
print("\nFile size:")
!ls -lh frey-custom-model.zip
```

### Step 10: Download Your Model

1. **Click the folder icon** (left sidebar)
2. **Find `frey-custom-model.zip`**
3. **Right-click → Download**
4. Wait for download (~4.5GB)

**Done!** You now have your custom fine-tuned model!

---

## Part 4: Deploy to Raspberry Pi (10 minutes)

### Step 1: Transfer Files

```bash
# On your local machine
# Extract the zip
unzip frey-custom-model.zip

# Copy to Pi
scp frey-model/frey-assistant-q4_k_m.gguf pi@frey.local:~/
scp frey-model/Modelfile pi@frey.local:~/
```

### Step 2: Import into Ollama

```bash
# SSH to Pi
ssh pi@frey.local

# Import model
docker exec ollama ollama create frey-assistant:custom -f ~/Modelfile

# Wait ~30 seconds for import
# You'll see: "success"

# Verify
docker exec ollama ollama list
# Should show frey-assistant:custom
```

### Step 3: Test Before Deployment

```bash
# Test your model
docker exec -it ollama ollama run frey-assistant:custom

# Try your commands:
>>> Start Jellyfin
>>> Is Sonarr running?
>>> What services are running?
>>> Thanks Frey

# Press Ctrl+D to exit

# If responses look good, proceed to deployment
```

### Step 4: Deploy with Ansible

```bash
# Exit SSH (Ctrl+D)

# On your local machine
cd ~/frey  # or wherever your Frey repo is

# Update configuration
vim group_vars/all/main.yml

# Change this line:
voice_assistant:
  ollama_model: "frey-assistant:custom"  # Was llama3.2:3b

# Save and exit

# Deploy
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation

# This will:
# - Update Home Assistant configuration
# - Restart services with new model
# - Takes ~2-3 minutes
```

### Step 5: Test Voice Assistant

**Wait 2 minutes for Home Assistant to restart, then:**

1. Speak wake word: **"Ok Nabu"**
2. Wait for chime/LED
3. Say: **"Start Jellyfin"**
4. Listen to response - should use YOUR personality!
5. Try more commands:
   - "Is Sonarr running?"
   - "What services are available?"
   - "Thanks Frey"

**If it works - congratulations! You have a custom talking car AI!** 🚗💨

---

## Part 5: Iterate and Improve (Ongoing)

### Week 1: Collect Failures

Use your voice assistant for a week and **note every time it:**
- Doesn't understand a command
- Gives wrong response
- Sounds awkward
- Misses context

**Keep a failures log:**
```
FAILURES.md

1. Said: "Boot up the video server"
   Expected: Start Jellyfin
   Got: "I don't understand"
   → Need to add synonym

2. Said: "Check downloads"
   Expected: Check qBittorrent status
   Got: Wrong interpretation
   → Need to add variant

3. Response: "I will commence starting..."
   Problem: Too formal for my taste
   → Adjust personality
```

### Week 2: Update Dataset

```bash
# Add failures to your dataset
vim my_custom_frey.jsonl

# Add the missing cases:
{"input": "Boot up the video server", "output": "Certainly! Starting Jellyfin. <function_call>frey_docker_start(service=\"jellyfin\")</function_call>"}
{"input": "Check downloads", "output": "Checking qBittorrent status. <function_call>frey_docker_status(service=\"qbittorrent\")</function_call>"}

# Adjust personality if needed
# Replace formal responses with your preferred style

# Now you have v2 of your dataset
cp my_custom_frey.jsonl my_custom_frey_v2.jsonl
```

### Week 3: Retrain (FREE!)

**Repeat the Google Colab process:**
1. Upload `my_custom_frey_v2.jsonl`
2. Run all cells
3. Download new model
4. Deploy to Pi

**Cost: $0.00** (it's free!)

**Time: 20 minutes total**

### Week 4: Perfect!

After 2-3 iterations, you should have:
- ✅ 95%+ accuracy
- ✅ Perfect personality match
- ✅ Understands all your commands
- ✅ Handles edge cases
- ✅ Feels like a real companion

**Then enjoy it!** 🎉

---

## Customization Recipes

### Recipe 1: Add a New Service

When you add a new Docker service:

```jsonl
# Add these 4 lines for the new service
{"input": "Start [NEW_SERVICE]", "output": "[YOUR_STYLE] <function_call>frey_docker_start(service=\"[new_service]\")</function_call> [CONFIRMATION]"}
{"input": "Is [NEW_SERVICE] running?", "output": "[YOUR_STYLE] <function_call>frey_docker_status(service=\"[new_service]\")</function_call>"}
{"input": "Restart [NEW_SERVICE]", "output": "[YOUR_STYLE] <function_call>frey_docker_restart(service=\"[new_service]\")</function_call>"}
{"input": "Stop [NEW_SERVICE]", "output": "[YOUR_STYLE] <function_call>frey_docker_stop(service=\"[new_service]\")</function_call>"}
```

Retrain and deploy. Done!

### Recipe 2: Change Personality

**Make it more casual:**
```jsonl
# Replace formal phrases
{"input": "Thanks", "output": "No problem!"}  # was "My pleasure"
{"input": "Good morning", "output": "Hey! Morning!"}  # was "Good morning. All systems operational"
```

**Make it more professional:**
```jsonl
{"input": "Thanks", "output": "You're welcome. Standing by for further instructions."}
{"input": "Good morning", "output": "Good morning. All systems operational and monitoring status normal."}
```

**Retrain with updated examples.**

### Recipe 3: Add Multi-Language Support

```jsonl
# German
{"input": "Starte Jellyfin", "output": "Natürlich! Starte Jellyfin. <function_call>frey_docker_start(service=\"jellyfin\")</function_call>"}
{"input": "Läuft Sonarr?", "output": "Lass mich Sonarr's Status prüfen. <function_call>frey_docker_status(service=\"sonarr\")</function_call>"}

# French
{"input": "Démarre Jellyfin", "output": "Certainement! Je démarre Jellyfin. <function_call>frey_docker_start(service=\"jellyfin\")</function_call>"}
{"input": "Sonarr fonctionne?", "output": "Je vérifie le statut de Sonarr. <function_call>frey_docker_status(service=\"sonarr\")</function_call>"}
```

**Note**: Consider using qwen-2.5-7b as base model for better multilingual support.

### Recipe 4: Add Context Awareness

```jsonl
# Time-based
{"input": "Good morning", "output": "Good morning! Starting your morning routine. <function_call>frey_docker_start(service=\"homeassistant\")</function_call> <function_call>frey_system_info()</function_call>"}
{"input": "Good night", "output": "Good night! Shutting down non-essential services. <function_call>frey_docker_stop(service=\"qbittorrent\")</function_call> Sleep well!"}

# Sequence awareness
{"input": "Start the media stack", "output": "Initiating full media stack. <function_call>frey_docker_start(service=\"jellyfin\")</function_call> <function_call>frey_docker_start(service=\"sonarr\")</function_call> <function_call>frey_docker_start(service=\"radarr\")</function_call> All services coming online."}
```

### Recipe 5: Add Humor

```jsonl
{"input": "Are you alive?", "output": "I'm as alive as an AI can be! All systems operational and ready to assist."}
{"input": "Tell me a joke", "output": "Why did the Docker container go to therapy? It had too many unresolved dependencies!"}
{"input": "What's your favorite service?", "output": "I don't play favorites, but I must admit Ollama is rather important - it's running my brain right now!"}
```

---

## Troubleshooting

### Problem: Model doesn't understand commands

**Diagnosis:**
```bash
# Test directly
docker exec -it ollama ollama run frey-assistant:custom
>>> [YOUR COMMAND]
# Note the response
```

**Solutions:**
1. **Not enough training examples** - Add more variations
2. **Inconsistent format** - Check function call syntax
3. **Typos in dataset** - Validate JSON again
4. **Need more epochs** - Try 5 instead of 3

**Fix and retrain.**

### Problem: Personality is wrong

**Diagnosis:** Model is too formal/casual/robotic

**Solutions:**
1. Review your dataset examples
2. Make sure personality is consistent across ALL examples
3. Add more conversational examples (greetings, thanks, etc.)
4. Adjust temperature in Modelfile:
   ```
   PARAMETER temperature 0.8  # More creative (was 0.7)
   # or
   PARAMETER temperature 0.5  # More deterministic
   ```

**Retrain with personality tweaks.**

### Problem: Function calls are malformed

**Diagnosis:** Model generates wrong function syntax

**Solutions:**
1. Check your dataset has EXACTLY this format:
   ```
   <function_call>function_name(param="value")</function_call>
   ```
2. Make sure EVERY example that needs function calls has them
3. Add more examples with correct syntax
4. Use more epochs (5 instead of 3)

**Retrain with corrected examples.**

### Problem: Google Colab runs out of memory

**Diagnosis:** OOM error during training

**Solutions:**
1. Use smaller base model:
   ```python
   MODEL = "llama-3.1-8b"  # Instead of 13b
   ```
2. Reduce batch size:
   ```python
   BATCH_SIZE = 1  # Instead of 2
   ```
3. Increase gradient accumulation:
   ```python
   gradient_accumulation_steps=8  # Instead of 4
   ```
4. Try during off-peak hours (Colab gives better GPUs sometimes)

### Problem: Voice assistant still uses old model

**Diagnosis:** Deployment didn't work

**Check:**
```bash
# SSH to Pi
ssh pi@frey.local

# Check what models exist
docker exec ollama ollama list

# Check what Home Assistant is configured to use
docker exec homeassistant cat /config/packages/frey_voice.yaml | grep model

# Check Ollama logs
docker logs ollama
```

**Solutions:**
1. Verify model was imported: `ollama list` should show it
2. Verify config was updated: Check frey_voice.yaml
3. Restart Home Assistant: `docker restart homeassistant`
4. Wait 2 minutes and try again

---

## Advanced Tweaks

### Tweak 1: Adjust Model Temperature

In your Modelfile:
```
# More creative/varied responses
PARAMETER temperature 0.9

# More consistent/predictable
PARAMETER temperature 0.5

# Balanced (default)
PARAMETER temperature 0.7
```

Deploy change:
```bash
ssh pi@frey.local
vim ~/Modelfile
# Update temperature
docker exec ollama ollama create frey-assistant:custom -f ~/Modelfile
docker restart homeassistant
```

### Tweak 2: Adjust Context Window

```
# Longer context (remembers more)
PARAMETER num_ctx 4096

# Standard
PARAMETER num_ctx 2048
```

**Note**: Longer context uses more RAM!

### Tweak 3: Use Different Quantization

**For more quality (uses more RAM):**
```python
# In Colab
model.save_pretrained_gguf("frey-model", tokenizer, quantization_method="q5_k_m")
# Results in ~5.5GB model (higher quality)
```

**For less RAM (lower quality):**
```python
model.save_pretrained_gguf("frey-model", tokenizer, quantization_method="q3_k_m")
# Results in ~3GB model (lower quality, test first!)
```

### Tweak 4: Use Different Base Model

**For better multilingual:**
```python
MODEL = "qwen-2.5-7b"  # Better at non-English
```

**For maximum quality (needs 24GB+ VRAM in Colab):**
```python
MODEL = "llama-3.1-13b"  # Bigger, smarter, slower to train
```

---

## Next Steps Checklist

After completing this guide:

- [ ] Base system deployed and working
- [ ] Created custom dataset with your services
- [ ] Chose your personality style
- [ ] Fine-tuned model on Google Colab
- [ ] Deployed custom model to Pi
- [ ] Tested voice commands
- [ ] Started failure log for iteration
- [ ] Planned first retrain (week 2)

**Congratulations!** You now have a fully custom talking car AI specialized for YOUR exact setup and personality preferences!

## Resources

**In this repo:**
- `scripts/finetune/README.md` - Quick start for Colab
- `scripts/finetune/frey_personality_dataset.jsonl` - Base template
- `scripts/finetune/training_data_template.jsonl` - More examples
- `docs/MODEL_FINETUNING.md` - Technical deep dive
- `docs/AI_ARCHITECTURE.md` - System architecture

**External:**
- Google Colab: https://colab.research.google.com
- Unsloth: https://github.com/unslothai/unsloth
- Ollama models: https://ollama.com/library

**Community:**
- Frey GitHub Discussions (for questions)
- Share your personality dataset (help others!)
- Show off your talking car! 🚗💨

---

## Final Tips

1. **Start small** - 50 examples is enough to see if it works
2. **Be consistent** - Pick ONE personality style and stick to it
3. **Iterate often** - It's free, so don't be afraid to retrain
4. **Test thoroughly** - Use it for a week before next iteration
5. **Have fun** - This is YOUR AI companion, make it perfect for YOU!

**Enjoy your talking car!** 🎉
