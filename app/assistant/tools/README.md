# The assistant's optional clients

Two Python files (3.8+, standard library only) that the headset serves at `/tools/` on the assistant API
(`docs/assistant.md`, "Optional clients"). Nothing in the app runs them; an assistant or an agent does.

- `assistant.py`: a command line and a small client for the API. It checks the headset's pin on every connection.
  `--config` takes a JSON file (`pair --save`) or a curl config with the token and the pin (an agent's
  `.assistant-link`).
- `mcp_server.py`: an MCP server over stdio (needs `assistant.py` beside it). Its tools are the service's commands,
  one per command in `GET /describe`: the description, the parameters as the input schema, read-only for level read,
  and "Off now" with the switch's name while the viewer has not allowed that level. It follows the event stream and
  tells the client when the list changes (a switch, or the app restarting). A few tools are made here because they are
  more than one call: `get_status`, `wait_for_viewer_message`, `get_recent_viewer_messages`, `answer_viewer`,
  `look_at_room` (the snapshot as an image).

A command added to the app is a tool with no change here. An agent on the headset gets a copy of both in its
`.player/mcp/` folder, declared in its own MCP config (`scripts/agents/agent_terminal.gd`).

Tests: `tools/assistant/test_mcp_server.py` (against a stand-in service) and `tools/assistant/test_assistant.py`
(the app on 127.0.0.1).
