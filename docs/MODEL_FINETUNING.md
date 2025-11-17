# Fine-Tuning Custom Models for Frey with Unsloth

## Overview

This guide explains how to fine-tune larger LLM models (7B-13B parameters) using Unsloth on a GPU machine, then deploy them quantized to your Raspberry Pi 5. This approach allows you to:

- **Use bigger models**: Fine-tune 7B or 13B models on GPU
- **Specialize for your use case**: Train on home automation specific tasks
- **Deploy efficiently**: Quantize to Q4_K_M (~4-5GB) for Pi deployment
- **Better performance**: Specialized 7B Q4 often outperforms general 3B

## The Strategy

```
GPU Machine                          Raspberry Pi 5
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━

1. Fine-tune llama 3.1 8B    ───────▶ 4. Deploy quantized model
   with Unsloth                        (~4.5GB RAM)
   (uses 16GB+ VRAM)
                                     5. Use in voice assistant
2. Export to GGUF                      (smarter than 3B!)
   with Q4_K_M quantization
                                     6. Enjoy specialized AI
3. Transfer files
   (SCP to Pi)
```

**Key insight**: A fine-tuned 7B model quantized to Q4 can outperform a general-purpose 3B model because it's specialized for your exact tasks.

## Prerequisites

### On GPU Machine (for fine-tuning)

**Hardware:**
- NVIDIA GPU with 16GB+ VRAM (RTX 3090, 4090, A100, etc.)
- 32GB+ system RAM recommended
- 100GB+ free disk space

**Software:**
- Ubuntu 20.04+ or similar Linux
- Python 3.10 or 3.11
- CUDA 11.8 or 12.1
- Docker (optional, for isolated environment)

**Not suitable for:**
- ❌ Raspberry Pi (no GPU, insufficient RAM)
- ❌ CPU-only machines (too slow)
- ❌ GPUs with <12GB VRAM (may work with smaller models)

### On Raspberry Pi 5 (for deployment)

- Already set up with Frey
- Ollama running
- 16GB RAM model recommended

## Quick Start

### Step 1: Set Up Fine-Tuning Environment (GPU Machine)

```bash
# Clone Frey repo (if not already)
git clone https://github.com/your-username/frey.git
cd frey/scripts/finetune

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Unsloth
pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"
pip install --no-deps trl peft accelerate bitsandbytes

# Install other dependencies
pip install -r requirements.txt
```

### Step 2: Prepare Training Data

Create a dataset in JSONL format with your specific use cases:

```bash
# Use the template as a starting point
cp training_data_template.jsonl my_training_data.jsonl

# Edit with your examples
vim my_training_data.jsonl
```

**Dataset format:**
```jsonl
{"input": "User request", "output": "Assistant response with <function_call>...</function_call>"}
```

**Example:**
```jsonl
{"input": "Start Jellyfin", "output": "I'll start Jellyfin for you. <function_call>frey_docker_start(service=\"jellyfin\")</function_call>"}
{"input": "Is Sonarr running?", "output": "Let me check Sonarr's status. <function_call>frey_docker_status(service=\"sonarr\")</function_call>"}
```

**Tips for good training data:**
- Include variations of the same command
- Cover all your Docker services
- Include multi-step tasks
- Add edge cases (protected services, errors)
- Include RAG queries if you use that feature
- Aim for 50-200 high-quality examples

### Step 3: Fine-Tune the Model

```bash
# Fine-tune llama 3.1 8B (recommended)
python3 finetune_frey_model.py \
  --model llama-3.1-8b \
  --dataset my_training_data.jsonl \
  --output ./frey-finetuned \
  --epochs 3 \
  --quantization q4_k_m q5_k_m

# This will:
# 1. Load base model with 4-bit quantization
# 2. Add LoRA adapters for efficient training
# 3. Fine-tune on your dataset
# 4. Export to GGUF format (Q4_K_M and Q5_K_M)
# 5. Create Ollama Modelfile
```

**Training time:**
- RTX 4090: ~5-15 minutes for 100 examples, 3 epochs
- RTX 3090: ~10-25 minutes
- A100: ~3-10 minutes

**Available models:**
- `llama-3.1-8b` (recommended) - Best balance
- `qwen-2.5-7b` - Good multilingual, efficient
- `llama-3.1-13b` - Bigger, needs more VRAM
- `mistral-7b-v0.3` - Alternative option

### Step 4: Transfer to Raspberry Pi

```bash
# From your GPU machine
cd frey-finetuned/gguf

# Copy GGUF file to Pi
scp frey-assistant-q4_k_m.gguf pi@frey.local:~/

# Copy Modelfile
cd ..
scp Modelfile pi@frey.local:~/
```

### Step 5: Import into Ollama on Pi

```bash
# SSH to your Pi
ssh pi@frey.local

# Import model into Ollama
docker exec ollama ollama create frey-assistant:q4 -f ~/Modelfile

# Test the model
docker exec -it ollama ollama run frey-assistant:q4
>>> Start Jellyfin
# Should respond with function call

# Check memory usage
docker exec ollama ollama ps
free -h
```

### Step 6: Deploy with Ansible

Update `group_vars/all/main.yml`:

```yaml
voice_assistant:
  enabled: true
  ollama_model: "frey-assistant:q4"  # Use your fine-tuned model!
```

Or for advanced deployment, use the custom_models configuration:

```yaml
custom_models:
  - name: "frey-assistant:q4"
    gguf_path: "~/frey-finetuned/gguf/frey-assistant-q4_k_m.gguf"
    description: "Fine-tuned Llama 3.1 8B for Frey home automation"
    temperature: 0.7
    top_p: 0.9
    num_ctx: 2048
```

Deploy:

```bash
# On your local machine
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation
```

## Advanced Topics

### Custom Dataset Creation

**Structure:**

Each training example should include:
1. **Input**: User's natural language request
2. **Output**: Assistant's response with function calls

**Function call format:**
```
<function_call>function_name(param="value")</function_call>
```

**Available functions:**
- `frey_docker_start(service="name")`
- `frey_docker_stop(service="name")`
- `frey_docker_restart(service="name")`
- `frey_docker_status(service="name")`
- `frey_list_services()`
- `frey_system_info()`
- `frey_query_knowledge(query="question")`

**Example multi-step:**
```jsonl
{
  "input": "Restart all arr services",
  "output": "I'll restart all the arr services for you: Sonarr, Radarr, Lidarr, Prowlarr, and Bazarr. <function_call>frey_docker_restart(service=\"sonarr\")</function_call> <function_call>frey_docker_restart(service=\"radarr\")</function_call> <function_call>frey_docker_restart(service=\"lidarr\")</function_call> <function_call>frey_docker_restart(service=\"prowlarr\")</function_call> <function_call>frey_docker_restart(service=\"bazarr\")</function_call>"
}
```

**Data collection tips:**
1. Use your voice assistant logs to find real commands
2. Add variations (synonyms, different phrasings)
3. Include error cases (protected services, invalid commands)
4. Cover all your services
5. Balance the dataset (don't have 90% "start" commands)

### Quantization Options

Different quantization levels for different use cases:

| Quantization | RAM Usage | Quality | Best For |
|--------------|-----------|---------|----------|
| Q3_K_M | ~3GB | Good | Maximum memory savings |
| Q4_K_M | ~4.5GB | Excellent | **Recommended balance** |
| Q5_K_M | ~5.5GB | Very High | If you have RAM to spare |
| Q8_0 | ~8GB | Near original | Rarely needed |

**Recommended**: Q4_K_M provides excellent quality-to-size ratio.

**Export multiple quantizations:**
```bash
python3 finetune_frey_model.py \
  --quantization q3_k_m q4_k_m q5_k_m \
  ...
```

Then test which works best for your use case.

### Training Parameters

**Epochs:**
- Too few (1-2): Underfitting, model doesn't learn enough
- Just right (3-5): Good performance
- Too many (10+): Overfitting, model memorizes instead of generalizing

**Learning rate:**
- Default: `2e-4` (good starting point)
- Higher (`5e-4`): Faster learning, risk of instability
- Lower (`1e-4`): More stable, slower learning

**Batch size:**
- Larger: Faster training, needs more VRAM
- Smaller: Slower training, lower VRAM usage
- Default (2): Works with 16GB VRAM

**LoRA rank:**
- Higher (32, 64): More parameters, better quality, slower
- Lower (8, 16): Faster, smaller, may lose quality
- Default (16): Good balance

**Example for quick experimentation:**
```bash
python3 finetune_frey_model.py \
  --model llama-3.1-8b \
  --dataset my_data.jsonl \
  --epochs 2 \
  --learning-rate 3e-4 \
  --batch-size 4
```

### Model Comparison

Test your fine-tuned model vs base models:

```bash
# On Pi, load both models
docker exec ollama ollama pull llama3.2:3b
docker exec ollama ollama run llama3.2:3b
>>> Start Jellyfin
# Note the response

docker exec ollama ollama run frey-assistant:q4
>>> Start Jellyfin
# Compare the response

# Your fine-tuned model should:
# - Respond faster with correct function call
# - Use more consistent format
# - Better understand home automation context
```

### Iterative Improvement

**Workflow:**
1. Fine-tune with initial dataset
2. Deploy to Pi and test
3. Collect examples where it fails
4. Add those examples to dataset
5. Re-train and deploy
6. Repeat until satisfied

**Example:**
```bash
# First iteration
python3 finetune_frey_model.py --dataset v1_data.jsonl --output v1

# Test on Pi, find issues
# User: "Turn on the media server"
# Model: Doesn't understand it means Jellyfin

# Add to dataset:
# {"input": "Turn on the media server", "output": "I'll start Jellyfin..."}

# Second iteration
python3 finetune_frey_model.py --dataset v2_data.jsonl --output v2

# Continue improving
```

## Memory Usage on Pi

**With fine-tuned 8B Q4_K_M model:**

```
Daytime (Voice + RAG):
├─ frey-assistant:q4  ~4.5GB  ⬅ Your fine-tuned model
├─ nomic-embed        ~0.14GB
├─ ChromaDB           ~0.2GB
├─ Services           ~0.15GB
└─ System overhead    ~4GB
   Total:            ~9GB ✅ Still within budget

Nighttime (Reasoning):
├─ qwen2.5:14b        ~8GB    ⬅ Keep larger model for overnight
└─ System overhead    ~4GB
   Total:            ~12GB ✅ Acceptable at night
```

**Strategy**: Use your specialized 8B model for voice/RAG, keep stock 14B for overnight reasoning.

## Troubleshooting

### Fine-Tuning Issues

**"CUDA out of memory"**
```bash
# Reduce batch size
--batch-size 1

# Or use smaller model
--model qwen-2.5-7b  # instead of llama-3.1-13b
```

**"Training is very slow"**
- Check GPU utilization: `nvidia-smi`
- Ensure you're using GPU, not CPU
- Reduce max sequence length if samples are short
- Enable packing if samples are short: Edit script, set `packing=True`

**"Model doesn't learn"**
- Increase epochs: `--epochs 5`
- Check dataset quality (consistent format?)
- Try higher learning rate: `--learning-rate 3e-4`
- Ensure enough training examples (50+ minimum)

### Deployment Issues

**"Model too large for Pi"**
- Use more aggressive quantization: Q3_K_M instead of Q4_K_M
- Fine-tune smaller base model: qwen-2.5-7b instead of llama-3.1-13b
- Check actual RAM usage with `free -h`

**"Model doesn't import into Ollama"**
```bash
# Check Modelfile path
docker exec ollama cat /root/.ollama/custom-models/frey-assistant.Modelfile

# Try manual import
docker cp ~/frey-assistant-q4_k_m.gguf ollama:/root/.ollama/models/
docker exec ollama ollama create frey-assistant:q4 -f /root/.ollama/custom-models/frey-assistant.Modelfile
```

**"Model gives worse results than base model"**
- Check training data quality
- Try more epochs
- Ensure dataset has enough examples
- Test with different quantization (Q5_K_M for higher quality)
- May need more diverse training data

## Performance Comparison

**Expected improvements with fine-tuned 8B vs stock 3B:**

| Metric | Stock 3B | Fine-tuned 8B Q4 |
|--------|----------|------------------|
| RAM usage | ~2.2GB | ~4.5GB |
| Response time | 1-2s | 1-2s (similar) |
| Function call accuracy | Good | **Excellent** |
| Context understanding | Good | **Excellent** |
| Home automation knowledge | Limited | **Specialized** |
| General knowledge | Good | Good |

**Real-world benefit**: Fewer misunderstandings, more consistent responses, better handling of complex multi-step commands.

## Cost Analysis

**GPU rental options for fine-tuning:**

| Provider | GPU | Cost | Time | Total |
|----------|-----|------|------|-------|
| Lambda Labs | RTX 6000 Ada | $0.80/hr | ~0.5hr | **$0.40** |
| Vast.ai | RTX 4090 | $0.35/hr | ~0.5hr | **$0.18** |
| RunPod | RTX 3090 | $0.34/hr | ~0.5hr | **$0.17** |
| Google Colab Pro | A100 | $10/mo | Included | **~$0** if you have sub |

**One-time cost**: $0.15 - $0.50 for a fine-tuned model you'll use forever!

## Best Practices

1. **Start small**: Fine-tune with 50-100 examples first
2. **Test iteratively**: Deploy, test, collect failures, retrain
3. **Keep base models**: Always keep stock models as fallback
4. **Version your datasets**: `v1_data.jsonl`, `v2_data.jsonl`, etc.
5. **Document changes**: Note what you improved in each version
6. **Backup models**: Keep GGUF files backed up
7. **Monitor memory**: Watch RAM usage on Pi

## Example Workflow

**Complete workflow from zero to deployed:**

```bash
# Day 1: On GPU machine
cd ~/projects/frey/scripts/finetune
python3 -m venv venv
source venv/bin/activate
pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"
pip install -r requirements.txt

# Create initial dataset (use template + your commands)
cp training_data_template.jsonl my_frey_data_v1.jsonl
vim my_frey_data_v1.jsonl  # Add 50 examples

# Fine-tune
python3 finetune_frey_model.py \
  --model llama-3.1-8b \
  --dataset my_frey_data_v1.jsonl \
  --output frey-v1 \
  --epochs 3

# Transfer to Pi
scp frey-v1/gguf/frey-assistant-q4_k_m.gguf pi@frey.local:~/
scp frey-v1/Modelfile pi@frey.local:~/

# Day 2: On Pi
ssh pi@frey.local
docker exec ollama ollama create frey-v1:q4 -f ~/Modelfile

# Test
docker exec -it ollama ollama run frey-v1:q4
>>> Start Jellyfin
>>> Is Sonarr running?
>>> Restart all arr services

# If good, deploy with Ansible
exit

# Day 3: On local machine
vim group_vars/all/main.yml
# Set: ollama_model: "frey-v1:q4"

ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags automation

# Day 4+: Iterate
# Use voice assistant, note any failures
# Add failures to dataset v2
# Re-train and deploy
```

## References

- [Unsloth Documentation](https://github.com/unslothai/unsloth)
- [GGUF Format](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)
- [Ollama Model Import](https://github.com/ollama/ollama/blob/main/docs/import.md)
- [LoRA Fine-Tuning](https://arxiv.org/abs/2106.09685)
- [Quantization Explained](https://huggingface.co/docs/transformers/main/en/quantization)

## Next Steps

1. Set up GPU environment
2. Create your training dataset
3. Fine-tune your first model
4. Deploy and test on Pi
5. Iterate and improve
6. Enjoy your specialized home automation AI!

Questions? Check the Frey Discord or GitHub issues.
