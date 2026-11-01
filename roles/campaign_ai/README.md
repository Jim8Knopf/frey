# Campaign assistant

This first version offers the llama.cpp chat UI at
`https://campaign-ai.hub.frey` through Frey sign-in, limited to `frey_admins`
and `notes`. It uses Qwen3 1.7B Q4_K_M, a small local model; expect mistakes
and review every draft. Paste ideas or attach supported text files, then copy
reviewed Markdown into SilverBullet. The assistant does not automatically
read or write SilverBullet, or remember the whole campaign across new chats.

The model container has no Docker socket, credentials, notes, photos, or
external network. A minimal reverse proxy connects it to Frey's existing
authenticated proxy. Only the model file directory is mounted, read-only. No
agent tools or MCP servers are enabled. Conversations may be stored in the
browser; protect the device and clear its site data when appropriate.

The first deployment starts a background download of approximately 1.28 GB.
It verifies the pinned SHA-256 before starting the model. The UI returns an
error until the download finishes. Check progress with:

```sh
systemctl status frey-campaign-ai-download.service
sudo journalctl -u frey-campaign-ai-download.service -n 30
ls -lh /opt/frey/appdata/campaign-ai/models/
```

From the Frey project directory on the admin computer, run
`bash scripts/campaign-ai-ready-check.sh` to check download status and, once
downloaded, model readiness and its configured isolation. It exits with status
2 while the file is still downloading. The check does not test sign-in or the
quality of an answer.

If a download fails or Frey reboots, a systemd timer retries the partial
download. Check it with `systemctl status frey-campaign-ai-download.timer`.
You can also retry immediately with `sudo systemctl restart
frey-campaign-ai-download.service`. After the model is downloaded, the timer
skips the service and does not restart a model that you have stopped. Model
downloads require internet, but inference runs offline after download. The
model container uses at most two CPUs and 3 GiB RAM; it starts on reboot once
installed. Administrators can stop or start it in Dockge. An Ansible deploy
also starts it when the verified model file exists. This initial version does
not yet offer start/stop controls to ordinary notes-group users.

For a useful first prompt, try:

> Organize the following campaign ideas into small Markdown pages for
> SilverBullet. Use descriptive page titles and `[[wiki links]]`. Preserve my
> ideas; label suggestions, uncertainties and contradictions clearly. Do not
> invent established facts. Propose an index page and list open questions.

The model has a limited context window. Work with short sections rather than
uploading a whole campaign at once; verify that text from PDFs is actually
extracted. Uploaded documents and model output are not automatically saved as
campaign pages. Give each new draft a human review before putting it in Notes.

Deploy with `ansible-playbook playbooks/site.yml --tags pki,identity,campaign_ai,dashy,monitoring`
after a focused check, and repeat to verify idempotence. Run
`bash scripts/campaign-ai-check.sh` to check anonymous access. Also verify
group restrictions, model isolation and a real response after the download
completes. On Android, trust the Frey CA and use the browser.
