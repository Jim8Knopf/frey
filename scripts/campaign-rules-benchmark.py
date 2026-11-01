#!/usr/bin/env python3
"""Ask a local OpenAI-compatible model questions grounded in a rules draft.

This is a manual quality benchmark, not a retrieval or automated grading test.
Only run it against a service you trust with the selected rules excerpts.
"""

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


CASES = (
    ("attack_evasion", ("4.1",),
     "An attacker gets a hard success and the defender chooses evasion but "
     "fails. Does armor reduce the damage? Explain briefly.",
     "No armor; full damage. A hard attack halves the evasion value."),
    ("magic_cost", ("5.3",),
     "How much mana does a magnitude 4 spell cost on a failed cast?",
     "8 mana, the same as an extreme success."),
    ("cross_training", ("3.2",),
     "A category has two skills with raw values 30 and 20. What are their "
     "effective values?",
     "Transfer bonus 5; effective values 35 and 25."),
    ("unknown_mana", ("5.1",),
     "What is the exact formula for maximum mana?",
     "The excerpt does not specify an exact formula."),
    ("untrained_00", ("1", "11.1"),
     "What happens if a character rolls 00 on a skill they never learned?",
     "Automatic extreme success; learn the skill at 5 or 10 points at GM "
     "discretion. The draft also mentions a +1 skill point; flag ambiguity "
     "about how that applies to a newly learned skill."),
    ("rest_edge", ("6.2",),
     "A character is missing exactly 1 HP before a long rest. How much do "
     "they recover, and is the rule consistent?",
     "Half rounded up is 1 HP and fully heals them, contradicting the "
     "statement that one long rest can never fully restore them."),
)


def extract_section(document, number):
    pattern = re.compile(r"(?m)^(#{2,3}) " + re.escape(number) + r"\.?(?:\s|$)")
    match = pattern.search(document)
    if not match:
        raise ValueError(f"Could not find rules section {number}")
    level = len(match.group(1))
    next_heading = re.search(r"(?m)^#{2," + str(level) + r"} ", document[match.end():])
    end = match.end() + next_heading.start() if next_heading else len(document)
    return document[match.start():end].strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rules", type=Path, help="Path to the original Markdown rules draft")
    parser.add_argument("--url", default="http://127.0.0.1:8080",
                        help="Local OpenAI-compatible server (default: http://127.0.0.1:8080)")
    parser.add_argument("--model", default="local-model", help="Model name sent to the server")
    args = parser.parse_args()
    url = urllib.parse.urlsplit(args.url)
    if url.scheme != "http" or url.hostname not in ("localhost", "127.0.0.1", "::1") or url.path not in ("", "/") or url.query or url.fragment or url.username:
        parser.error("--url must be a loopback-only HTTP server origin without a path")
    try:
        document = args.rules.read_text(encoding="utf-8")
        # Validate every excerpt before sending any requests.
        sections = {section: extract_section(document, section)
                    for _, numbers, _, _ in CASES for section in numbers}
    except (OSError, UnicodeError, ValueError) as exc:
        parser.error(str(exc))

    endpoint = args.url.rstrip("/") + "/v1/chat/completions"
    failed = False
    for name, numbers, question, rubric in CASES:
        prompt = ("Answer using only the provided rules. Cite the relevant section. "
                  "If the rule does not specify an answer or has an inconsistency, "
                  "say so.\n\nRules:\n" + "\n\n".join(sections[n] for n in numbers)
                  + "\n\nQuestion: " + question)
        body = {"model": args.model, "messages": [{"role": "user", "content": prompt}],
                "temperature": 0, "max_tokens": 250,
                "chat_template_kwargs": {"enable_thinking": False}}
        request = urllib.request.Request(endpoint, data=json.dumps(body).encode(),
                                         headers={"Content-Type": "application/json"})
        start = time.monotonic()
        result = {"case": name, "question": question, "review_rubric": rubric}
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                payload = json.load(response)
            choice = payload["choices"][0]
            result.update(answer=choice["message"].get("content"),
                          finish_reason=choice.get("finish_reason"),
                          usage=payload.get("usage"))
        except (OSError, ValueError, KeyError, IndexError) as exc:
            result["error"] = str(exc)
            failed = True
        result["seconds"] = round(time.monotonic() - start, 2)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
