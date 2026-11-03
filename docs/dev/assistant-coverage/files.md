# Assistant coverage: the Files tab

Every control of the Files tab and of what hangs off it (the places, network hosts and shares, media servers, the
Browser place, the Queue, Favourites, Search, the Library, the agents' entries and the Android apps place), with
the registry command that does the same, its consumer level (`"assistant"` in the spec), or why there is none.
The commands run the code the buttons run, and the tab follows when it shows the place a command changed.

Code: `app/scripts/dev/files_commands.gd` (hosts, favourites, queue, search, library, saved pages, the tab),
`app/scripts/agents/local_agents.gd` (`register_commands`: the agents' rows), `app/scripts/android/android_apps.gd`
(`register_commands`: the Android apps place), `app/scripts/dev/browse_commands.gd` (places, listings, discovery).
Test: `app/tests/test_assistant_coverage_files.gd`.

Commands from `assistant_commands.gd` that the core change moves into the registry are listed with "(core)". Their
handlers are not duplicated here.

## Rules

- **Logins go in, never out.** `host_add` and `host_edit` take a user name and a password, as the host form does.
  `hosts` only says whether a login is saved (`login: true`), never the user name or the password. No reply,
  summary, print line or `describe` holds a login. The test checks every reply and summary for the passwords and
  user names it saved. `list_dir network://` gives paths only.
- **Destructive actions keep the UI's semantics.** `host_remove` is the host form's Delete host. The form asks
  nothing, so the command asks nothing either, and undo puts the host back with its login. `remove_place` (core)
  still asks the viewer on a card. No command deletes or overwrites a file, because the Files tab has no such
  action. `copy_to_library` (core) refuses a file that is already there.
- **A paired assistant's call** (`ctx.client` set) gets the assistant's rules: `host_add`, `host_edit` (a new host
  name) and `media_servers url` only reach hosts on this network (`AssistantFetch.host_refusal`), and
  `open_in_corner` only opens what `open` would (`AssistantCommands.open_refusal`). The dev link has no such limits.
- **An agent and its own session.** `agent_restart` of the calling agent (its row's `client` equals `ctx.client`) is
  refused unless `self: true` is passed: a restart ends the session that asked. The parameter description says to
  pass it only when the viewer asked. An agent may hide or show its own pane (`agent_hide`, `agent_show`), because
  it keeps working either way. `agents` says which agent is calling (`you`).
- **Android app names are the user's folder names.** Nothing in code or docs names an app.

## Places column

| Control | Command (consumer level) |
|---|---|
| The list of places | `places` (read) |
| Library | `library` (read): the view from the NFOs. `list_dir` (read): the plain folder. `files_show` (files): on the pane |
| Test patterns | `list_dir stub://` (read) |
| Network | `hosts` (read), `list_dir network://` (read) |
| Media servers | `list_dir upnp://` (read) |
| Browser | `web_pages` (read). The desktop windows: excluded (below) |
| Queue | `queue` (read) |
| Favourites | `favourites` (read) |
| Search | `search` (read) |
| An agent's place (Claude Code, Codex) | `agents` (read). Pressing a running agent's place shows its pane: `agent_show` (apps) |
| Android apps | `android_status` (read) |
| Home, Device home, Videos, Downloads, From assistant, saved folders, removable media, /mnt | `places` and `list_dir` (read) |
| A place added by an assistant | `add_place`, `remove_place` (files, core; a card asks the viewer) |

## The bar above the list

| Control | Command (consumer level) |
|---|---|
| The folder's title and item count | `list_dir` (read) |
| Add host | `host_add` (files) |
| Edit hosts (a mode), then a host | `host_edit`, `host_remove` (files). The mode itself is UI only |
| Edit pages, then a page | `web_page_remove` (files) |
| Edit queue, then a file | `queue_remove` (control) |
| Edit favourites, then one | `favourite_remove` (files) |
| Favourite (a folder) | `favourite_add`, `favourite_remove` (files) |
| In corner, then a video | `open_in_corner` (control). Swap, close and size belong to playback (`pip_*`) |
| Shuffle | `queue_shuffle` (control) |
| Repeat: off / one / all | `queue_repeat` (control) |
| Play on | `queue_play_on` (control) |
| Gapless | `gapless` (control) |
| Clear upcoming | `queue_clear_upcoming` (control) |

## Rows

| Place | Control | Command (consumer level) |
|---|---|---|
| Any folder | A folder, `..` | `list_dir` (read) for the assistant's own browsing. `files_show` (files) to show the viewer |
| Any folder | A video or picture | `open` (control, core) |
| Network | A saved host | `list_dir smb://host/share` (read) |
| Network | + Add host..., the host form's Save | `host_add` (files). Saving an existing host is `host_edit` (files) |
| Network | The host form's Delete host | `host_remove` (files) |
| Network | The host form's Cancel | None: nothing changes |
| Network | The host form's Show password | Excluded: it shows a password |
| Network | Find hosts on this network | `discover_hosts` (read) |
| Network | Found: a host | `host_add` (files) with its name or address |
| Media servers | Look again for media servers | `media_servers` (files). `url` adds one by its description URL |
| Media servers | A server, a folder | `list_dir upnp://...` (read) |
| Media servers | A video | `open` with its http:// URL (control, core) |
| Browser | Stop showing | `stop_showing` (control) |
| Browser | + Open a web page or a stream: Open | `browse` (control, core): a card asks the viewer |
| Browser | + Open a web page or a stream: Play (a stream URL) | `open` (control, core): media servers on this network only |
| Browser | The web page form's Save | `web_page_save` (files) |
| Browser | The web page form's Remove | `web_page_remove` (files) |
| Browser | A saved page | `browse` (control, core) |
| Browser | Desktop windows: the list and a window | Excluded: the other windows' titles are not the assistant's to read, and it may not open a captured window (`open_refusal`) |
| Queue | A file | `queue_jump` (control) |
| Favourites | + Add the playing file | `favourite_add` with no path (files) |
| Favourites | A favourite | `open` (control, core) or `list_dir` (read) |
| Search | The query row and its form | `search` (read). `files_show {query}` (files) shows it on the pane |
| Search | A result | `open` (control, core) or `list_dir` (read) |
| Library | A poster, a season | `library` (read) |
| Library | An episode, a film's Play | `open` (control, core) |
| Library | (a copy's card) Cancel | `copy_cancel` (files, core). The copy itself: `copy_to_library` (files, core) |
| From assistant | (a download's card) Cancel | `fetch_cancel` (files, core). The download: `fetch` (files, core) |
| An agent | The state line | `agents` (read) |
| An agent | Start, briefed on the player | `agent_start` (apps) |
| An agent | Start plain, no briefing | `agent_start {plain: true}` (apps) |
| An agent | Show on the controller | `agent_show` (apps) |
| An agent | Restart, briefed on the player | `agent_restart` (apps). The caller itself only with `self: true` |
| An agent | Restart plain, no briefing | `agent_restart {plain: true}` (apps) |
| An agent | Hide from the controller | `agent_hide` (apps) |
| An agent | Put it on the big screen | `agent_big_screen` (apps) |
| An agent | The install card's Install / No | Excluded: the viewer's consent. `agent_start` of an agent that is not installed only puts the card up (`asked_to_install: true`) |
| Android apps | What is missing, how to add an app, the status line | `android_status` (read): `missing`, `apps`, `state`, `step`, `error` |
| Android apps | An app | `android_start` (apps) |
| Android apps | Cancel (a start), Stop (the app on show), the card's Cancel | `android_stop` (apps) |
| Android apps | B on an Android window | `android_back` (apps) |

## Excluded, and why

- **The desktop windows in the Browser place.** Listing them gives the titles of whatever else is on the desktop,
  and opening one shows the viewer's screen. An assistant's `open` refuses captured windows for the same reason.
- **Show password.** It shows a saved password.
- **The edit modes** (Edit hosts, Edit pages, Edit queue, Edit favourites). These are UI states. The actions done
  in them have commands.
- **The on-pane keyboard and typing into a form** (`type_text`, dev only). Each form's action has its own command
  with named parameters.
- **`open_url`** (dev only): it opens any web page without asking. The assistant's `browse` asks on a card.
- **The agents' install card answer.** Installing software is the viewer's decision.

## Tests

`app/tests/test_assistant_coverage_files.gd` runs each command through `DevCommands.execute` against the real main
scene. A gate stands in for the consumer API and sets `ctx.client`. The test checks:

- the effect, the read-back and the tab following;
- undo;
- the refusals: a host on another network, a saved host again, the playing file out of the queue, `open_in_corner`
  of a host that is not saved, an agent restarting itself without `self`, an Android app that is not there;
- that no reply or summary holds a login it saved;
- that every command of the area is tagged with its level and describes each parameter;
- that no `code` command is tagged.

Stand-ins: the window capture (as in `test_local_agents.gd`), a home folder for the agents and the Android apps, and
the made-up Library of `library_fixture.gd`. The real flows of the agents and the Android apps stay in
`test_local_agents.gd` and `test_android_apps.gd`. `agent_big_screen` is checked for its tag only, because it
captures a real terminal window.
