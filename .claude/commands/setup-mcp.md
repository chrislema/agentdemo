# Setup MCP Servers and CORE Memory Integration

Check and install required MCP servers, and configure hooks for automatic memory integration.

## Instructions

### Part 1: MCP Server Installation

1. Check if core-memory MCP server is already configured:
```bash
claude mcp get core-memory 2>/dev/null && echo "INSTALLED" || echo "NOT_INSTALLED"
```

2. If NOT_INSTALLED, add the core-memory server:
```bash
claude mcp add --transport http --scope user core-memory "https://mcp.getcore.me/api/v1/mcp?source=Claude-Code"
```

3. Verify the MCP installation:
```bash
claude mcp list
```

### Part 2: Settings Hooks Configuration

4. Check if `~/.claude/settings.local.json` exists:
```bash
ls -la ~/.claude/settings.local.json 2>/dev/null && echo "EXISTS" || echo "NOT_EXISTS"
```

5. If NOT_EXISTS and `settings.local.sample.json` is in the current project, copy it:
```bash
mkdir -p ~/.claude
cp settings.local.sample.json ~/.claude/settings.local.json
```

6. If EXISTS, show the user the current contents and ask if they want to merge the hooks from `settings.local.sample.json`. The hooks section needed is:
```json
{
  "hooks": {
    "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "echo 'Searching CORE Memory for context...'"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "echo 'Memory agents available for search and ingest'"}]}]
  }
}
```

7. Report final status:
   - MCP server: installed/already installed
   - Settings hooks: created/already exists/merged
