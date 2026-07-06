# Window layout tuning log

Use this file during your first week with the auto-tiler and named layouts.
Each time you manually fix a window, add a row below — that becomes the next code change.

| Date | Symptom | App / window | Fix applied manually | Module to change |
|------|---------|--------------|----------------------|------------------|
| | e.g. Finder info panel got tiled | Finder | Floated it | windows.lua excludedApps |
| | e.g. Ghostty slow to position | Ghostty | Waited longer | layouts.lua launchWait |
| | | | | |

## Quick reference

| Knob | File | Default |
|------|------|---------|
| Tile gap | modules/windows.lua | 6px |
| Stack ratio (built-in) | modules/windows.lua | 0.60 |
| Ultrawide aspect threshold | modules/windows.lua | 2.0 |
| Layout placement pause | modules/layouts.lua | 2500ms |
| App launch wait | modules/layouts.lua | 0.45s |

## Verification

Reload config (`⌘⌃R`), then in Hammerspoon Console:

```lua
require('modules.verify').run()
```
