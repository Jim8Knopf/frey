# Frey Fine-Tuning - Google Colab (FREE!)

## Quick Start: Fine-Tune for FREE

**No GPU? No problem!** Use Google Colab's FREE GPU to fine-tune your talking car AI.

### Option 1: Use Google Colab (Recommended - FREE!)

1. **Go to Google Colab**: https://colab.research.google.com
2. **Create new notebook** or upload your own
3. **Enable GPU**: Runtime → Change runtime type → GPU (T4)
4. **Copy this code into cells and run**:

```python
# Cell 1: Install Unsloth
%%capture
import torch
!pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"
!pip install --no-deps trl peft accelerate bitsandbytes

# Cell 2: Upload your dataset
# Click folder icon → upload frey_personality_dataset.jsonl

# Cell 3: Load model and fine-tune
from unsloth import FastLanguageModel
from datasets import load_dataset
from trl import SFTTrainer
from transformers import TrainingArguments

# Load base model
model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/Meta-Llama-3.1-8B-bnb-4bit",
    max_seq_length=2048,
    load_in_4bit=True,
)

# Add LoRA
model = FastLanguageModel.get_peft_model(
    model, r=16,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
)

# Load dataset
dataset = load_dataset('json', data_files='frey_personality_dataset.jsonl', split='train')

def format_prompt(sample):
    return {"text": f"""<|begin_of_text|><|start_header_id|>system<|end_header_id|>

You are Frey, an AI assistant for home automation. You're helpful, professional, and have a friendly personality like KITT.<|eot_id|><|start_header_id|>user<|end_header_id|>

{sample['input']}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

{sample['output']}<|eot_id|>"""}

dataset = dataset.map(format_prompt, remove_columns=dataset.column_names)

# Train!
trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=dataset,
    dataset_text_field="text",
    max_seq_length=2048,
    args=TrainingArguments(
        output_dir="./output",
        num_train_epochs=3,
        per_device_train_batch_size=2,
        learning_rate=2e-4,
        logging_steps=10,
    ),
)

trainer.train()

# Cell 4: Export to GGUF
model.save_pretrained_gguf("frey-model", tokenizer, quantization_method="q4_k_m")

# Cell 5: Download
!zip -r frey-model.zip frey-model/
# Download frey-model.zip from file browser
```

5. **Wait ~15 minutes** while it trains
6. **Download** the `frey-model.zip` file
7. **Deploy to your Pi** (see below)

### Option 2: Use Your Own GPU

```bash
# Install dependencies
pip install -r requirements.txt

# Fine-tune
python3 finetune_frey_model.py \
  --model llama-3.1-8b \
  --dataset frey_personality_dataset.jsonl \
  --epochs 3
```

## Deploy to Raspberry Pi

```bash
# Extract (if using Colab)
unzip frey-model.zip

# Copy to Pi
scp frey-model/frey-assistant-q4_k_m.gguf pi@frey.local:~/
scp frey-model/Modelfile pi@frey.local:~/  # If created

# Import into Ollama
ssh pi@frey.local
docker exec ollama ollama create frey-assistant:q4 -f ~/Modelfile

# Or create Modelfile manually:
cat > ~/Modelfile << 'EOF'
FROM ./frey-assistant-q4_k_m.gguf
PARAMETER temperature 0.7
PARAMETER top_p 0.9
SYSTEM You are Frey, a helpful AI assistant for home automation with a friendly personality.
EOF

docker exec ollama ollama create frey-assistant:q4 -f ~/Modelfile

# Test it
docker exec -it ollama ollama run frey-assistant:q4
>>> Hey Frey, start Jellyfin
```

## Customize Your Dataset

Edit `frey_personality_dataset.jsonl` to add your own examples:

```jsonl
{"input": "Your command here", "output": "Frey's response with <function_call>function_name(param=\"value\")</function_call>"}
```

**Tips:**
- Include variations of commands
- Add your specific services
- Mix personality with functionality
- Include 50-200 examples for best results

## Documentation

- **Full Guide**: `../../docs/PERFECT_FINETUNING_GUIDE.md` (if exists)
- **Technical Details**: `../../docs/MODEL_FINETUNING.md`
- **Templates**: `frey_personality_dataset.jsonl`, `training_data_template.jsonl`

## Why Google Colab?

- ✅ **FREE** GPU (T4, sometimes V100/A100)
- ✅ **No setup** required
- ✅ **Fast** (~15 minutes)
- ✅ **Easy** to use
- ✅ **Perfect** for iteration

## Cost Comparison

| Method | Time | Cost |
|--------|------|------|
| **Google Colab FREE** | 15-20 min | **$0.00** ✅ |
| Vast.ai GPU rental | 15 min | $0.18 |
| Lambda Labs | 15 min | $0.40 |
| Own GPU | 10-30 min | Hardware cost |

**Winner: Google Colab** for most users!

## Next Steps

1. Fine-tune with personality template
2. Deploy and test
3. Note what doesn't work
4. Add those cases to dataset
5. Retrain (it's free!)
6. Repeat until perfect

Enjoy your talking car! 🚗💨
