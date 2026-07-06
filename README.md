# Hammerspoon config (live)

This directory is the **active** Hammerspoon configuration loaded at runtime.

- **Path:** `~/.hammerspoon/`
- **Reload:** `⌘⌃R` or save any file here (path watcher)
- **Guide:** `⌘⌃H` or open `USER_GUIDE.html`

The Time Machine backup copy under `/Volumes/.timemachine/.../.hammerspoon/` is read-only. Edit files here, not in the backup workspace.

## Git

This folder is version-controlled. After changes:

```bash
cd ~/.hammerspoon
git status
git add -A
git commit -m "your message"
```

## Verify

```lua
require('modules.verify').run()
```
