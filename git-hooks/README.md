# 🔒 Git Hooks Setup

**Manual Setup (2 commands):**

```bash
git config core.hooksPath git-hooks
chmod +x git-hooks/*
```

**What this does:**
- Tells Git to use hooks from the `git-hooks/` directory
- Makes all hook scripts executable

**Hooks included:**
- `pre-commit`: Auto-encrypts `secrets.yml` if unencrypted
- `post-commit`: Reminds you secrets are encrypted

That's it! Your hooks are now active. 🎯