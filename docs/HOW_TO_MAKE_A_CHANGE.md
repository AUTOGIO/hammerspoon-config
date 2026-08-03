# How to change something (step by step)

This guide is for someone who has never coded.
You will change **one line**, save, and see a message on screen.

Time needed: about 5 minutes.

---

## What you need

1. A Mac with **Hammerspoon** installed and running (dragon icon in the menu bar).
2. This folder open in **Cursor**: `~/.hammerspoon`
3. An adult nearby if you get stuck (optional, but smart).

---

## Words you will see

| Word | Meaning |
|------|---------|
| Folder | A box that holds files |
| File | A document the computer can read |
| Save | Store your change (`⌘S`) |
| Reload | Tell Hammerspoon to read the files again |
| Alert | The small message that pops up on screen |

Keyboard tip: `⌘` = Command key (next to the space bar).

---

## The example (safe practice)

We will change the welcome message Hammerspoon shows when it starts.

**Before:** `WE ARE READY, MOTHER FUCKER`  
**After:** `Hello from my Mac!`

Nothing else will break if you follow the steps exactly.

---

## Steps

### Step 1 — Open the project

1. Open **Cursor**.
2. Open the folder: **File → Open Folder…**
3. Choose: `/Users/YOUR_NAME/.hammerspoon`  
   (YOUR_NAME is your Mac account name.)

You should see folders like `modules`, `docs`, `scripts`.

---

### Step 2 — Open the right file

1. In the left file list, click **`init.lua`** (it is at the top level, not inside a folder).
2. Scroll to the **last line**. It looks like this:

```lua
hs.alert.show('WE ARE READY, MOTHER FUCKER')
```

That line means: “show a little alert that says WE ARE READY, MOTHER FUCKER.”

---

### Step 3 — Make the change

1. Click inside the quotes.
2. Delete the words `WE ARE READY, MOTHER FUCKER`.
3. Type: `Hello from my Mac!`

The line should now look like this:

```lua
hs.alert.show('Hello from my Mac!')
```

**Rules for this example:**
- Keep the single quotes `'…'`
- Keep the parentheses `(…)`
- Change **only** the words inside the quotes

---

### Step 4 — Save

Press **⌘S** (Command + S).

You should see a small alert soon. That means Hammerspoon reloaded.

If nothing happens, do Step 5.

---

### Step 5 — Reload (if needed)

Press **⌘⌃R**  
(Command + Control + R)

or

1. Click the **Hammerspoon** icon in the menu bar (top of the screen).
2. Choose **Reload Config**.

---

### Step 6 — Check that it worked

You should see a popup that says:

**Hello from my Mac!**

If you see that → you did it. Nice work.

---

### Step 7 — Put it back (optional)

If you want the old message again:

1. Change the line back to:

```lua
hs.alert.show('WE ARE READY, MOTHER FUCKER')
```

2. Save with **⌘S**.

---

## If something goes wrong

| Problem | What to try |
|---------|-------------|
| No popup at all | Is Hammerspoon running? Look for its icon in the menu bar. |
| Red error in Hammerspoon Console | You may have deleted a quote. Put `'Hello from my Mac!'` back exactly. |
| Cursor cannot find the folder | Ask an adult to open `~/.hammerspoon` for you. |
| You are scared you broke it | Reload config. If needed, undo with **⌘Z**, then save. |

To open the Console: click the Hammerspoon menu icon → **Console**.

---

## Where things live (simple map)

```
.hammerspoon/
  init.lua      ← start here (the “main switch”)
  modules/      ← the real automation pieces
  docs/         ← guides (like this one)
  scripts/      ← helper scripts
  archive/      ← old stuff (do not touch)
  runtime/      ← computer notes (do not touch)
```

**Golden rule:** change one small thing, save, check. Then change the next thing.

---

## Next challenge (when you are ready)

Open the big guide with **⌘⌃H**, or open this file in a browser:

`docs/USER_GUIDE.html`

Try only things you understand. If a hotkey looks scary, skip it.

---

## Parent / helper note

This repo is a live Hammerspoon config. Edits to `init.lua` and `modules/` reload automatically. Prefer tiny text changes first. Layout rules for bigger cleanup: see `AGENTS.md`.
