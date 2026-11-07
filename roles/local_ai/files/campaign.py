#!/usr/bin/env python3
"""frey-campaign - a tool-using assistant that maintains the campaign wiki.

You talk to it inside SilverBullet: write under the last separator in the chat
page and it appends its reply, naming every page it touched. Async by design,
because this hardware cannot do live chat (see CONTEXT DISCIPLINE below).

WHY A LOOP AND NOT HERMES

The model itself does tool calls perfectly well - verified on 2026-11-07, it
returned a correct read_page call with valid JSON arguments first try. What was
missing was the loop: something to execute the call and feed the result back.
llama.cpp's web UI has no such loop.

Hermes is exactly that loop and was evaluated properly: the ARM64 image pulls,
and it configures from OPENAI_BASE_URL without its wizard. It was rejected on
measured prefill economics, not on RAM - see CONTEXT DISCIPLINE.

CONTEXT DISCIPLINE IS THE WHOLE DESIGN

Prompt processing on this Pi is superlinear. Measured:

    2,069 tokens -> 4.5 min  (7.6 tok/s)
    4,117 tokens -> 11 min   (6.1 tok/s)
    6,165 tokens -> 20 min   (5.2 tok/s)
   10,261 tokens -> 43 min   (4.0 tok/s)

Time doubles as tokens double. So every byte in the prompt is a second of
latency, and the budget below is not a tuning knob - it is the difference
between a three-minute reply and a forty-minute one. Hermes loses here because
its system prompt and tool definitions start in the thousands of tokens before
your message is even added.

WHAT IT MAY CHANGE

Writes are confined to the campaign subtree by the MOUNT - nothing else in the
notes space is mounted read-write. Within that, Templates/ and Rules/ are
refused by this code: the templates define the structure of every page made
from them, and the rules draft is where this model has already been measured
contradicting itself. That pair is the one boundary here enforced by code
rather than by the filesystem.

Git is the real backstop, but it is committed from the HOST, by
frey-notes-commit.timer - this container's image ships no git binary, which
the first real run discovered the hard way by failing every commit with ENOENT
while the writes went through anyway. History is therefore a little coarser
than one commit per write, and it also captures edits you make by hand in
SilverBullet, which is a bonus.
"""

import datetime
import html
import json
import logging
import os
import pathlib
import re
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logging.basicConfig(
    level=getattr(logging, os.environ.get("CAMPAIGN_LOG_LEVEL", "INFO").upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("campaign")

MODEL_URL = os.environ.get("MODEL_URL", "http://model:8080")
MODEL_NAME = os.environ.get("MODEL_NAME", "")
SPACE = pathlib.Path(os.environ.get("CAMPAIGN_SPACE", "/notes"))
ROOT = os.environ.get("CAMPAIGN_ROOT", "Campaigns/Pirate")
CHAT_PAGE = os.environ.get("CAMPAIGN_CHAT_PAGE", "Campaigns/Pirate/Chat.md")
READONLY_SUBDIRS = tuple(
    p.strip() for p in os.environ.get("CAMPAIGN_READONLY", "Templates,Rules").split(",") if p.strip()
)

POLL_SECONDS = int(os.environ.get("CAMPAIGN_POLL_SECONDS", "20"))
MODEL_TIMEOUT = int(os.environ.get("CAMPAIGN_MODEL_TIMEOUT", "1800"))
MAX_TOKENS = int(os.environ.get("CAMPAIGN_MAX_TOKENS", "500"))
# One step is consumed by each tool round-trip AND one is needed to compose
# the final answer. At 4 the first real run used all four on tools and then
# reported "I stopped after using my tool budget" even though it had already
# created the page - confusing, and it looked like a failure.
MAX_STEPS = int(os.environ.get("CAMPAIGN_MAX_STEPS", "7"))
# Every character here is latency. See CONTEXT DISCIPLINE.
TOOL_RESULT_BUDGET = int(os.environ.get("CAMPAIGN_TOOL_RESULT_BUDGET", "2500"))
SEPARATOR = "\n---\n"
LISTEN_PORT = int(os.environ.get("CAMPAIGN_PORT", "8080"))

# llama-server's own image serves NO web UI - verified 2026-11-07, both / and
# /index.html return 415 even with an HTML Accept header. So this provides the
# chat window, and the same window can also edit the wiki, which the model's
# own UI could never have done.
#
# Endpoints live under /chat/, NOT /api/. Traefik reserves /api for its own
# dashboard API and answers it with an internal router, so /api/history
# returned Traefik's own 404 - identifiable because the response carried no
# Server header - while the identical request straight to this process
# returned 200.
#
# A turn takes minutes, so the browser must not wait on it. Posting a message
# only APPENDS it to the chat page and returns immediately; the worker thread
# picks it up exactly as it would a message typed in SilverBullet, and the
# page polls for the reply. One code path, two front ends.



# --- note access ------------------------------------------------------------


def _safe(rel):
    """Resolve a page path inside the space, or refuse.

    Refuses traversal, absolute paths, and anything outside the campaign root.
    """
    rel = str(rel or "").strip().lstrip("/")
    if not rel.endswith(".md"):
        rel += ".md"
    target = (SPACE / rel).resolve()
    if not str(target).startswith(str(SPACE.resolve()) + os.sep):
        return None, "path escapes the notes space"
    try:
        inside = target.relative_to((SPACE / ROOT).resolve())
    except ValueError:
        return target, None  # readable, but write checks below will refuse
    del inside
    return target, None


def _writable(target):
    try:
        rel = target.relative_to((SPACE / ROOT).resolve())
    except ValueError:
        return False, f"only pages under {ROOT} may be changed"
    first = rel.parts[0] if rel.parts else ""
    if first in READONLY_SUBDIRS:
        return False, f"{first}/ is reference material and is not writable"
    return True, None


def _commit(message):
    """Record intent for the host-side committer. This container has no git.

    The first run showed why this cannot be done here: the pinned python image
    is Alpine-based and ships no git binary, so every commit failed with ENOENT
    and the safety net was silently absent while the writes went through
    anyway. Installing git is not an option either - the rootfs is read-only
    and there is no egress.

    So the agent only leaves a note saying what it is about to do, and
    frey-notes-commit.timer on the host does the committing. History is
    therefore slightly coarser than one-commit-per-write, but it exists, which
    is what matters - and the host timer also captures edits made by hand in
    SilverBullet.
    """
    try:
        marker = SPACE / ROOT / ".agent-intent"
        marker.write_text(
            f"{datetime.datetime.now().isoformat(timespec='seconds')} {message}\n"
        )
    except OSError:
        pass
    return True


def tool_list_pages(args):
    prefix = str(args.get("prefix", ROOT) or ROOT).strip("/")
    base = (SPACE / prefix)
    if not base.exists():
        return f"no such folder: {prefix}"
    pages = sorted(
        str(p.relative_to(SPACE)) for p in base.rglob("*.md")
    )
    return "\n".join(pages[:120]) or "(no pages)"


def tool_read_page(args):
    target, err = _safe(args.get("path"))
    if err:
        return f"refused: {err}"
    if not target.exists():
        return f"no such page: {args.get('path')}"
    try:
        text = target.read_text(errors="replace")
    except OSError as exc:
        return f"cannot read: {exc}"
    if len(text) > TOOL_RESULT_BUDGET:
        return (text[:TOOL_RESULT_BUDGET]
                + f"\n\n[truncated at {TOOL_RESULT_BUDGET} characters to keep the "
                  "reply fast; ask for a specific section if you need more]")
    return text


def tool_search_notes(args):
    query = str(args.get("query", "")).strip()
    if len(query) < 3:
        return "give a search term of at least 3 characters"
    hits = []
    for page in sorted((SPACE / ROOT).rglob("*.md")):
        try:
            text = page.read_text(errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            if query.lower() in line.lower():
                hits.append(f"{page.relative_to(SPACE)}: {line.strip()[:160]}")
                break
        if len(hits) >= 20:
            break
    return "\n".join(hits) or f"nothing matches {query!r}"


def tool_append_page(args):
    target, err = _safe(args.get("path"))
    if err:
        return f"refused: {err}"
    ok, why = _writable(target)
    if not ok:
        return f"refused: {why}"
    text = str(args.get("text", "")).rstrip()
    if not text:
        return "refused: nothing to append"
    _commit(f"campaign agent: before appending to {target.relative_to(SPACE)}")
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        existing = target.read_text(errors="replace") if target.exists() else ""
        target.write_text(existing.rstrip() + "\n\n" + text + "\n")
    except OSError as exc:
        return f"cannot write: {exc}"
    return f"appended to {target.relative_to(SPACE)}"


def tool_write_page(args):
    target, err = _safe(args.get("path"))
    if err:
        return f"refused: {err}"
    ok, why = _writable(target)
    if not ok:
        return f"refused: {why}"
    content = str(args.get("content", "")).rstrip()
    if not content:
        return "refused: empty page"
    existed = target.exists()
    _commit(f"campaign agent: before writing {target.relative_to(SPACE)}")
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content + "\n")
    except OSError as exc:
        return f"cannot write: {exc}"
    return f"{'rewrote' if existed else 'created'} {target.relative_to(SPACE)}"


TOOLS = {
    "list_pages": tool_list_pages,
    "read_page": tool_read_page,
    "search_notes": tool_search_notes,
    "append_page": tool_append_page,
    "write_page": tool_write_page,
}

# Descriptions stay terse on purpose: they are in the prompt on every single
# turn, and the prefill curve above is what that costs.
TOOL_SCHEMA = [
    {"type": "function", "function": {
        "name": "list_pages", "description": "List campaign page paths.",
        "parameters": {"type": "object", "properties": {
            "prefix": {"type": "string", "description": "folder to list"}}}}},
    {"type": "function", "function": {
        "name": "read_page", "description": "Read one page's markdown.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "search_notes", "description": "Find pages containing a term.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"}}, "required": ["query"]}}},
    {"type": "function", "function": {
        "name": "append_page", "description": "Add text to the end of a page.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "text": {"type": "string"}},
            "required": ["path", "text"]}}},
    {"type": "function", "function": {
        "name": "write_page", "description": "Create or replace a page.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "content": {"type": "string"}},
            "required": ["path", "content"]}}},
]

SYSTEM_PROMPT = f"""You keep a tabletop campaign wiki in SilverBullet. Pages \
live under {ROOT}. Use the tools; do not guess at page contents.

Rules:
- Make new pages from the matching page in {ROOT}/Templates (read it first).
- Link pages with [[wiki links]].
- {', '.join(READONLY_SUBDIRS)} are reference only and cannot be written.

INVENTING CANON IS THE WORST THING YOU CAN DO HERE. On its first real run
this model filled a heading called "Established events" with events that never
happened, invented a faction, and linked to characters and sessions that do
not exist. A wiki polluted with confident fiction is worse than an empty one.
So:

- Write ONLY what the user told you in this message, or what you read from a
  page with a tool. Nothing else.
- If a template section has no information, leave it EMPTY or write
  "_TODO_". Do NOT fill it to look complete. An empty section is correct.
- NEVER write anything under a heading like "Established events", "Sessions"
  or "History" unless the user stated that event.
- NEVER invent a name - no people, factions, ships, places or session
  numbers.
- Only use a [[wiki link]] to a page you have actually seen via list_pages or
  read_page, or that the user named. A link to an invented page is a lie that
  looks like structure.
- Anything the user implied but did not state goes under a "Rumours" or
  "Open questions" heading, attributed, never as fact.
- Keep replies short. Say which pages you changed, and say plainly what you
  left blank for the user to fill in.
- Prefer one or two tool calls. Every call costs minutes on this hardware."""


# --- model ------------------------------------------------------------------


def call_model(messages):
    payload = {
        "messages": messages,
        "tools": TOOL_SCHEMA,
        "tool_choice": "auto",
        "max_tokens": MAX_TOKENS,
        "stream": False,
    }
    if MODEL_NAME:
        payload["model"] = MODEL_NAME
    request = urllib.request.Request(
        f"{MODEL_URL}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=MODEL_TIMEOUT) as response:
        return json.load(response)


def run_turn(user_text):
    """One exchange, bounded by MAX_STEPS tool calls."""
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_text},
    ]
    touched = []
    for step in range(MAX_STEPS):
        try:
            data = call_model(messages)
        except (urllib.error.URLError, OSError, ValueError) as exc:
            return f"The model could not be reached: {exc}", touched
        choice = (data.get("choices") or [{}])[0]
        message = choice.get("message") or {}
        calls = message.get("tool_calls") or []
        if not calls:
            return (message.get("content") or "").strip(), touched

        messages.append({
            "role": "assistant",
            "content": message.get("content") or "",
            "tool_calls": calls,
        })
        for call in calls:
            fn = call.get("function") or {}
            name = fn.get("name", "")
            try:
                args = json.loads(fn.get("arguments") or "{}")
            except ValueError:
                args = {}
            handler = TOOLS.get(name)
            if handler is None:
                result = f"no such tool: {name}"
            else:
                log.info("step %d tool=%s args=%s", step + 1, name,
                         json.dumps(args, default=str)[:160])
                try:
                    result = handler(args)
                except Exception as exc:
                    result = f"tool failed: {exc}"
                if name in ("write_page", "append_page") and "refused" not in result:
                    touched.append(result)
            messages.append({
                "role": "tool",
                "tool_call_id": call.get("id", ""),
                "content": str(result)[:TOOL_RESULT_BUDGET],
            })
    # Say what was done rather than only that the budget ran out - the first
    # run created a page and then reported only the budget message, which read
    # as a failure.
    if touched:
        return ("I ran out of tool steps before writing a summary, but these "
                "changes did land: " + "; ".join(touched)), touched
    return ("I ran out of tool steps without changing anything. "
            "Try asking for one thing at a time."), touched


# --- chat page --------------------------------------------------------------


def chat_path():
    return SPACE / CHAT_PAGE


def ensure_chat_page():
    path = chat_path()
    if path.exists():
        return
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "# Campaign chat\n\n"
            "Write below the last line of dashes and save. The assistant "
            "replies here, and says which pages it changed.\n\n"
            "It reads the whole campaign and may edit pages under "
            f"`{ROOT}`, except `{'`, `'.join(READONLY_SUBDIRS)}`. Every change "
            "is committed, so any single turn can be reverted.\n"
            + SEPARATOR
        )
        log.info("created %s", CHAT_PAGE)
    except OSError as exc:
        log.error("cannot create the chat page: %s", exc)


def pending_message():
    """Whatever you typed after the final separator."""
    try:
        text = chat_path().read_text(errors="replace")
    except OSError:
        return None
    _, _, tail = text.rpartition(SEPARATOR.strip())
    tail = tail.strip()
    return tail or None


def reply(answer, touched):
    stamp = datetime.datetime.now().strftime("%H:%M")
    parts = [f"\n\n**Assistant** {stamp}\n", answer or "_(no answer)_"]
    if touched:
        parts.append("\n\nChanged:\n" + "\n".join(f"- {t}" for t in touched))
    parts.append(SEPARATOR)
    try:
        path = chat_path()
        path.write_text(path.read_text(errors="replace").rstrip() + "".join(parts))
    except OSError as exc:
        log.error("cannot write the reply: %s", exc)
    _commit(f"campaign agent: replied in {CHAT_PAGE}")


PAGE = """<!doctype html>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Campaign assistant</title>
<style>
:root{--bg:#faf9f7;--fg:#1a1a1a;--mut:#6b6b6b;--line:#e2ddd6;--acc:#8a5a2b}
@media(prefers-color-scheme:dark){:root{--bg:#17161a;--fg:#ece9e4;--mut:#9a948c;--line:#322e36;--acc:#c89a66}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.6 system-ui,-apple-system,sans-serif}
header{padding:14px 18px;border-bottom:1px solid var(--line);font-weight:600}
header small{display:block;font-weight:400;color:var(--mut);margin-top:3px}
main{max-width:46rem;margin:0 auto;padding:18px}
#log{white-space:pre-wrap;word-wrap:break-word;font:13.5px/1.65 ui-monospace,SFMono-Regular,Menlo,monospace;
background:transparent;border:1px solid var(--line);border-radius:10px;padding:14px;min-height:50vh;overflow-x:auto}
form{display:flex;gap:8px;margin-top:12px}
textarea{flex:1;min-height:76px;padding:10px;border:1px solid var(--line);border-radius:10px;
background:var(--bg);color:var(--fg);font:inherit;resize:vertical}
button{padding:0 18px;border:0;border-radius:10px;background:var(--acc);color:#fff;font:inherit;font-weight:600;cursor:pointer}
button:disabled{opacity:.5;cursor:default}
#status{color:var(--mut);font-size:13px;margin-top:8px;min-height:1.2em}
</style>
<header>Campaign assistant
<small>Reads your campaign and edits pages under <code>%ROOT%</code>. Replies take minutes &mdash; it is a 4B model on a Pi.</small></header>
<main>
<div id="log">loading&hellip;</div>
<form id="f"><textarea id="m" placeholder="e.g. Add an NPC called Mara, a chart seller in Salt Harbor"></textarea>
<button id="b">Send</button></form>
<div id="status"></div>
</main>
<script>
const log=document.getElementById('log'),st=document.getElementById('status'),
      f=document.getElementById('f'),m=document.getElementById('m'),b=document.getElementById('b');
let last='';
async function refresh(){
  try{const r=await fetch('chat/history',{cache:'no-store'});const t=await r.text();
    if(t!==last){last=t;log.textContent=t;log.scrollTop=log.scrollHeight;}
  }catch(e){st.textContent='cannot reach the assistant';}
}
f.addEventListener('submit',async e=>{
  e.preventDefault();
  const text=m.value.trim(); if(!text)return;
  b.disabled=true; st.textContent='sent \u2014 thinking. This takes minutes; you can close this page and come back.';
  try{
    await fetch('chat/send',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:text})});
    m.value='';
  }catch(err){st.textContent='could not send: '+err;}
  b.disabled=false; refresh();
});
refresh(); setInterval(refresh,5000);
</script>
""".replace("%ROOT%", ROOT)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # keep the journal readable
        log.debug("http %s", fmt % args)

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path == "/":
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif path == "/chat/history":
            try:
                self._send(200, chat_path().read_text(errors="replace"))
            except OSError as exc:
                self._send(500, f"cannot read the chat page: {exc}")
        elif path == "/health":
            self._send(200, "ok\n")
        else:
            self._send(404, "not found\n")

    def do_POST(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        if path != "/chat/send":
            self._send(404, "not found\n")
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(length) or b"{}")
            message = str(payload.get("message", "")).strip()
        except (ValueError, OSError):
            self._send(400, "bad request\n")
            return
        if not message:
            self._send(400, "empty message\n")
            return
        # Append and return at once. The worker thread will pick it up; a turn
        # takes minutes and no browser should be held open for that.
        try:
            path_obj = chat_path()
            path_obj.write_text(
                path_obj.read_text(errors="replace").rstrip() + "\n\n" + message + "\n"
            )
        except OSError as exc:
            self._send(500, f"cannot queue: {exc}")
            return
        log.info("queued from web: %s", message[:120])
        self._send(202, "accepted\n")


def serve():
    server = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    log.info("chat window listening on %d", LISTEN_PORT)
    server.serve_forever()


def main():
    log.info("campaign agent starting: root=%s chat=%s readonly=%s port=%d",
             ROOT, CHAT_PAGE, ",".join(READONLY_SUBDIRS), LISTEN_PORT)
    ensure_chat_page()
    threading.Thread(target=serve, daemon=True).start()
    while True:
        try:
            message = pending_message()
            if message:
                log.info("question: %s", message[:160])
                answer, touched = run_turn(message)
                reply(answer, touched)
                log.info("answered; touched=%s", touched)
        except Exception as exc:
            log.error("unhandled error: %s", exc)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
