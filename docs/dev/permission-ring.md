# The permission ring for remote changes

Idea #23 in `docs/ideas.md`. Every command from the PC passes a gate, and every change that goes through shows a toast
in the headset with a way to undo it. The code is `app/scripts/dev/permission_ring.gd` and
`app/scripts/dev/remote_toast.gd`.

## The gate

Each command has a level (`control-protocol.md`, "Commands"). For `set`, the level is the setting's own level.

| Level | Allowed when |
|---|---|
| read | always |
| control: play, pause, seek, open, next, menu, volume, screen, mode | unless `remote_changes = "deny"` |
| change: the scene, `set` of settings files, `reload` | `remote_changes = "allow"`, or inside an allowed window |
| code: `run` | as change, and also `--dev-code` or `remote_code = true` |

The settings live under `[dev]` in `settings.cfg`:

```
[dev]
remote_changes="ask"    ; ask (default), allow, deny
remote_code=false
```

- **ask**, the default. Change-level commands are refused until the user opens an allowed window. Start the app with
  `--dev-allow=MINUTES` to open one.
- **allow.** Change-level commands always go through.
- **deny.** Only reads go through.

The PC can't raise its own permissions. `set` refuses to write the `[dev]` section, so it can't change
`remote_changes`, `remote_code` or the listener address. The only ways to grant more are on the headset: its settings
file, its command line, or later a gesture.

**Hold grip to allow for an hour** needs the headset and the pane. It is left to the pane's owner. The hook is:

```
preload("res://scripts/dev/dev_host.gd").instance().permissions.allow_for(3600)
```

`revoke()` closes the window again.

A refused command gets an error reply that says how to allow it. The headset shows "Refused remote <command>".

## The toast and undo

Every remote command that changed something shows a line in the headset, such as "Remote: volume 0.6 (undo: PC or
Ctrl+Z)". Reads show nothing. The toast is a `Label3D` placed 1.2 m ahead and 0.35 m below eye level, where the head
looks when it appears. It is not head-locked: it stays where it appeared, and it fades after 4 s. The last three lines
stack.

A change can be undone three ways:

- **From the PC:** `send undo` takes back the latest change. `send undo id=N` takes back change N. `send permissions`
  lists the recent changes with their ids and states (`done`, `undone`, `refused`).
- **On a desktop:** Ctrl+Z.
- **From the pane, later.** The ring emits `remote_change(entry)` for each change, undo and refusal. The entry is
  `{id, summary, command, state, undoable, t}`. The pane can show it with an Undo button that calls
  `permissions.undo(id)`. Until the pane does, the world-space toast is the fallback.

The ring keeps the last 20 changes. When a freed node's undo is dropped, the node is freed for good.

## Tested

On the desktop only, on 2026-10-31, with the stock 4.7.2 Windows build. The test covered:

- in ask mode, `spawn` refused with the message, and `set volume` (control level) allowed;
- with `--dev-allow=60`, the scene commands went through;
- `run` refused without `--dev-code`, and allowed with it;
- `set dev/remote_changes allow` refused;
- undo of a material change and of a `free`;
- the history in `permissions`;
- the toast in a rendered screenshot.

Not tested on the device: where the toast sits in XR, and whether it is readable there.
