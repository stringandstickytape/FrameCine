# Scene control over the dev link

Idea #10 in `docs/ideas.md`. The PC, or an AI session on it, can list the live scene, add nodes, change properties,
load glTF models and run GDScript snippets in the running app, all over the dev link (`control-protocol.md`). Every
change passes the permission ring and shows a toast with undo (`permission-ring.md`).

The commands are in `app/scripts/dev/scene_commands.gd`. `list_tree` is in `builtin_commands.gd`.

## Commands

| Command | Parameters | Level | Does |
|---|---|---|---|
| `list_tree` | `path` = `/root`, `depth` = 3, `properties` = false | read | the node tree |
| `get_prop` | `node`, `property` = `""` | read | one property or sub-path (`mesh:size`), or all editor-visible properties |
| `spawn` | `type` = Node3D, `scene`, `parent`, `name`, `properties` | change | adds an engine class or a scene file. Returns its path. |
| `set_prop` | `node`, `property`, `value` | change | sets a property or sub-path. Returns the new value. |
| `call` | `node`, `method`, `args` = [] | change | calls a method. Returns what it returns. |
| `free` | `node` | change | removes a node. It is kept for undo until the undo is dropped. |
| `load_gltf` | `path` or `data` (base64), `parent`, `name`, `position` = [0, 1.2, -2], `scale` = 1 | change | loads a glTF or GLB at runtime. Returns its path and node count. |
| `run` | `code` | code | runs a GDScript snippet. Returns its value. |

**Secrets.** `get_prop`, `set_prop` and `call` refuse private members (`_name`), names with a secret word (key, pin,
password, ...), a masked text field's text, and `call` the generic accessors. See "Secrets never go over the link" in
`control-protocol.md`.

**Node paths.** A path is absolute (`/root/Main/VideoScreen`), or relative to the main scene (`VideoScreen`,
`Remote/Box`). Spawned and loaded nodes go under the main scene's `Remote` node unless `parent` is given. `Remote` is
made on first use, so `list_tree Remote` shows everything the PC added. `reload app` clears it.

**Values** are JSON and are converted to the property's type:

| JSON | Becomes |
|---|---|
| `[x, y, z]`, `[x, y]`, `[x, y, z, w]` | a vector or quaternion, by the property's type |
| `[r, g, b]`, `[r, g, b, a]`, `"#rrggbb"` | a Color |
| `"res://..."`, `"user://..."`, an absolute path | the loaded resource, for an object property |
| `{"class": "BoxMesh", "size": [1, 2, 1]}` | a new resource with those properties, nested as deep as needed |
| other text, for a property that is not text | read with `str_to_var()`, for example `"Transform3D(...)"` |

Results come back the same way: vectors become lists, and objects become `"<Class:path or id>"`.

## Examples

```
L="python tools/listener.py"
$L send spawn type=MeshInstance3D name=Box properties='{"position": [0, 1.4, -1.5],
    "mesh": {"class": "BoxMesh", "size": [0.3, 0.3, 0.3]},
    "material_override": {"class": "StandardMaterial3D", "shading_mode": 0, "albedo_color": "#ff8800"}}'
$L send set_prop Remote/Box position '[0.5, 1.6, -2]'
$L send call Remote/Box rotate_y '[0.5]'
$L send load_gltf path=/home/steamos/models/room.glb name=Room position='[0, 0, 0]'
$L send load_gltf --b64 data=C:/models/chair.glb name=Chair       # a file on the PC, sent inline
$L send run 'return main.env_id'
$L send run 'var b = remote.get_node("Box")
b.scale *= 2
return b.scale'
$L send screenshot views='["third"]'                                  # see the result
$L send undo                                                         # take the last change back
```

**Lighting.** The environments have no lights; every surface is unlit. A spawned mesh with a default, lit material
renders black. Give it a material with `"shading_mode": 0` (unshaded), as above, or add a light with `spawn`.

## run: GDScript snippets

The snippet becomes the body of a function `run()` in a new script that extends `RefCounted`. Each line is indented
once. Without a `return`, the result is null. These names are in scope:

| Name | Is |
|---|---|
| `main` | the main scene (`scripts/main.gd`) |
| `tree` | the SceneTree |
| `remote` | the main scene's `Remote` node |
| `dev` | the dev node (`scripts/dev/dev_tools.gd`) |

A snippet may `await`, for example `await tree.create_timer(0.5).timeout`. Its reply then comes when it finishes. A
snippet that does not compile is refused. The compile error arrives as an `error` event.

`run` is the `code` level. It needs `--dev-code` on the command line, or `remote_code = true` under `[dev]`, in
addition to the change permission. A snippet can do anything the app can do, so turn it on only on a LAN you trust.

## Undo

`spawn` and `load_gltf` undo by freeing the node. `set_prop` undoes by setting the old value back. `free` undoes by
putting the node back where it was. `call` and `run` can't be undone; their toast says so by leaving out the undo
hint.

## Tested

On the desktop only, on 2026-10-31, with the stock 4.7.2 Windows build, headless and rendered. The test covered:

- spawn with a nested BoxMesh;
- `set_prop` on `position` and on `mesh:material`, with a new material and a colour from `#ff8800`;
- `get_prop` sub-paths, `call rotate_y`, and `free` with its undo;
- refusals for `free` on `/root/DevHost` and on the main scene;
- `run` with a value, with several lines, with `await`, and with a syntax error;
- a GLB written by a snippet, then loaded from its path and inline with `--b64`;
- a screenshot that shows both objects and the toast.

Not tested on the device: everything here in XR, and the cost of loading a large glTF on the main thread. A large
model will drop frames while it loads.
