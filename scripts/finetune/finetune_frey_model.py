#!/usr/bin/env python3
"""
Frey AI Model Fine-Tuning with Unsloth
Fine-tune larger models for home automation, then quantize for Raspberry Pi deployment

Requirements:
- GPU machine (NVIDIA with 16GB+ VRAM recommended)
- Python 3.10+
- CUDA 11.8 or 12.1

Installation:
    pip install "unsloth[colab-new] @ git+https://github.com/unslothai/unsloth.git"
    pip install --no-deps trl peft accelerate bitsandbytes

Usage:
    python3 finetune_frey_model.py --model llama-3.1-8b --dataset ./training_data.jsonl
"""

import argparse
import json
from pathlib import Path
from typing import List, Dict
import torch
from datasets import load_dataset
from unsloth import FastLanguageModel
from trl import SFTTrainer
from transformers import TrainingArguments

# Model configurations optimized for home automation
MODEL_CONFIGS = {
    "llama-3.1-8b": {
        "model_name": "unsloth/Meta-Llama-3.1-8B-bnb-4bit",
        "max_seq_length": 2048,
        "target_ram": "~4.5GB (Q4_K_M)",
        "recommended": True,
    },
    "llama-3.1-13b": {
        "model_name": "unsloth/Meta-Llama-3.1-13B-bnb-4bit",
        "max_seq_length": 2048,
        "target_ram": "~7GB (Q4_K_M)",
        "recommended": False,
    },
    "qwen-2.5-7b": {
        "model_name": "unsloth/Qwen2.5-7B-bnb-4bit",
        "max_seq_length": 4096,
        "target_ram": "~4GB (Q4_K_M)",
        "recommended": True,
    },
    "mistral-7b-v0.3": {
        "model_name": "unsloth/mistral-7b-v0.3-bnb-4bit",
        "max_seq_length": 2048,
        "target_ram": "~4GB (Q4_K_M)",
        "recommended": False,
    }
}

# System prompt for Frey home automation
FREY_SYSTEM_PROMPT = """You are Frey, a helpful voice assistant for managing a home server running Docker services.

You can control Docker containers using function calls. Available functions:
- frey_docker_start(service): Start a container
- frey_docker_stop(service): Stop a container
- frey_docker_restart(service): Restart a container
- frey_docker_status(service): Check container status
- frey_list_services(): List all containers
- frey_system_info(): Get system information
- frey_query_knowledge(query): Query the knowledge base

Available services include: jellyfin, sonarr, radarr, bazarr, lidarr, prowlarr, qbittorrent,
portainer, traefik, homeassistant, grafana, prometheus, and more.

Respond conversationally and confirm actions. Keep responses concise for voice output.
Protected services (cannot be stopped): homeassistant, ollama, traefik"""


def load_training_data(dataset_path: Path) -> Dict:
    """Load training dataset in JSONL format"""
    if not dataset_path.exists():
        raise FileNotFoundError(f"Dataset not found: {dataset_path}")

    dataset = load_dataset('json', data_files=str(dataset_path), split='train')
    print(f"Loaded {len(dataset)} training examples")
    return dataset


def format_frey_prompt(sample: Dict) -> Dict:
    """Format training sample for instruction fine-tuning"""

    # Llama 3.1 chat template
    conversation = f"""<|begin_of_text|><|start_header_id|>system<|end_header_id|>

{FREY_SYSTEM_PROMPT}<|eot_id|><|start_header_id|>user<|end_header_id|>

{sample['input']}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

{sample['output']}<|eot_id|>"""

    return {"text": conversation}


def finetune_model(
    model_name: str,
    dataset_path: Path,
    output_dir: Path,
    num_epochs: int = 3,
    learning_rate: float = 2e-4,
    batch_size: int = 2,
):
    """Fine-tune model using Unsloth"""

    config = MODEL_CONFIGS.get(model_name)
    if not config:
        raise ValueError(f"Unknown model: {model_name}. Choose from: {list(MODEL_CONFIGS.keys())}")

    print(f"Fine-tuning {model_name}")
    print(f"Model: {config['model_name']}")
    print(f"Target RAM after quantization: {config['target_ram']}")
    print(f"Max sequence length: {config['max_seq_length']}")

    # Load base model with 4-bit quantization
    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=config['model_name'],
        max_seq_length=config['max_seq_length'],
        dtype=None,  # Auto-detect
        load_in_4bit=True,
    )

    # Add LoRA adapters for efficient fine-tuning
    model = FastLanguageModel.get_peft_model(
        model,
        r=16,  # LoRA rank
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                       "gate_proj", "up_proj", "down_proj"],
        lora_alpha=16,
        lora_dropout=0,  # Optimized for inference
        bias="none",
        use_gradient_checkpointing="unsloth",  # Memory efficient
        random_state=3407,
    )

    # Load and format dataset
    dataset = load_training_data(dataset_path)
    dataset = dataset.map(format_frey_prompt, remove_columns=dataset.column_names)

    # Training arguments
    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=num_epochs,
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=4,
        warmup_steps=5,
        learning_rate=learning_rate,
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(),
        logging_steps=10,
        optim="adamw_8bit",
        weight_decay=0.01,
        lr_scheduler_type="linear",
        seed=3407,
        save_strategy="epoch",
        save_total_limit=2,
    )

    # Initialize trainer
    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=dataset,
        dataset_text_field="text",
        max_seq_length=config['max_seq_length'],
        args=training_args,
        packing=False,  # Can enable for efficiency if samples are short
    )

    # Train
    print("\nStarting training...")
    trainer.train()

    print(f"\nTraining complete! Model saved to {output_dir}")
    return model, tokenizer


def export_to_gguf(
    model,
    tokenizer,
    output_path: Path,
    quantization_methods: List[str] = None,
):
    """Export fine-tuned model to GGUF format with various quantizations"""

    if quantization_methods is None:
        # Default quantizations optimized for Pi 5
        quantization_methods = [
            "q4_k_m",  # Best balance: ~4-5GB RAM
            "q5_k_m",  # Higher quality: ~5-6GB RAM
            "q3_k_m",  # Most aggressive: ~3GB RAM (if quality is acceptable)
        ]

    print(f"\nExporting to GGUF format: {output_path}")

    for method in quantization_methods:
        print(f"\nQuantizing with {method.upper()}...")
        output_file = output_path / f"frey-assistant-{method}.gguf"

        model.save_pretrained_gguf(
            str(output_file.parent),
            tokenizer,
            quantization_method=method,
        )

        size_mb = output_file.stat().st_size / (1024 * 1024)
        print(f"✓ Saved: {output_file.name} ({size_mb:.1f} MB)")

    print(f"\n✓ All quantizations exported to {output_path}")


def create_ollama_modelfile(
    gguf_path: Path,
    output_path: Path,
    model_name: str = "frey-assistant",
):
    """Create Ollama Modelfile for the fine-tuned model"""

    modelfile_content = f"""# Frey Fine-Tuned Home Automation Assistant
FROM {gguf_path}

# Temperature settings for consistent responses
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.1

# Context window
PARAMETER num_ctx 2048

# System prompt
SYSTEM {FREY_SYSTEM_PROMPT}
"""

    modelfile_path = output_path / "Modelfile"
    with open(modelfile_path, 'w') as f:
        f.write(modelfile_content)

    print(f"\n✓ Created Modelfile: {modelfile_path}")
    print(f"\nTo import into Ollama:")
    print(f"  ollama create {model_name} -f {modelfile_path}")

    return modelfile_path


def main():
    parser = argparse.ArgumentParser(description="Fine-tune Frey home automation model")
    parser.add_argument(
        "--model",
        type=str,
        default="llama-3.1-8b",
        choices=list(MODEL_CONFIGS.keys()),
        help="Base model to fine-tune"
    )
    parser.add_argument(
        "--dataset",
        type=Path,
        required=True,
        help="Path to training dataset (JSONL format)"
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("./frey-finetuned"),
        help="Output directory for fine-tuned model"
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=3,
        help="Number of training epochs"
    )
    parser.add_argument(
        "--learning-rate",
        type=float,
        default=2e-4,
        help="Learning rate"
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=2,
        help="Batch size per GPU"
    )
    parser.add_argument(
        "--export-gguf",
        action="store_true",
        default=True,
        help="Export to GGUF after training"
    )
    parser.add_argument(
        "--quantization",
        type=str,
        nargs="+",
        default=["q4_k_m", "q5_k_m"],
        help="Quantization methods to export"
    )

    args = parser.parse_args()

    # Create output directory
    args.output.mkdir(parents=True, exist_ok=True)

    # Fine-tune
    model, tokenizer = finetune_model(
        model_name=args.model,
        dataset_path=args.dataset,
        output_dir=args.output,
        num_epochs=args.epochs,
        learning_rate=args.learning_rate,
        batch_size=args.batch_size,
    )

    # Export to GGUF
    if args.export_gguf:
        gguf_output = args.output / "gguf"
        gguf_output.mkdir(exist_ok=True)

        export_to_gguf(
            model,
            tokenizer,
            gguf_output,
            quantization_methods=args.quantization,
        )

        # Create Ollama Modelfile
        for method in args.quantization:
            gguf_file = gguf_output / f"frey-assistant-{method}.gguf"
            if gguf_file.exists():
                create_ollama_modelfile(
                    gguf_path=gguf_file,
                    output_path=args.output,
                    model_name=f"frey-assistant:{method}",
                )

    print("\n" + "="*60)
    print("✓ Fine-tuning complete!")
    print("="*60)
    print(f"\nNext steps:")
    print(f"1. Copy GGUF files to your Pi:")
    print(f"   scp {args.output}/gguf/*.gguf pi@frey.local:~/")
    print(f"2. Copy Modelfile to your Pi:")
    print(f"   scp {args.output}/Modelfile pi@frey.local:~/")
    print(f"3. Import into Ollama on Pi:")
    print(f"   ssh pi@frey.local")
    print(f"   docker exec ollama ollama create frey-assistant -f ~/Modelfile")
    print(f"4. Update group_vars/all/main.yml:")
    print(f"   voice_assistant:")
    print(f"     ollama_model: 'frey-assistant:q4_k_m'")
    print(f"5. Deploy with Ansible")


if __name__ == "__main__":
    main()
