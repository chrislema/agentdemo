# Sync Claude Code Configuration

Sync the latest Claude Code configuration (agents, skills, commands, docs, CLAUDE.md) from the central repository.

## Bootstrap (One-Time Setup)

This command should be installed globally so it's available in any project:

```bash
mkdir -p ~/.claude/commands
curl -o ~/.claude/commands/sync-config.md https://raw.githubusercontent.com/chrislema/lema-claude-code-config/main/.claude/commands/sync-config.md
```

After this one-time setup, `/sync-config` works in any project.

## Instructions

1. Create a temporary directory and clone the config repo:
```bash
TEMP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/chrislema/lema-claude-code-config.git "$TEMP_DIR"
```

2. Ensure the local directory structure exists:
```bash
mkdir -p .claude/agents .claude/skills .claude/commands docs
```

3. Copy the configuration files:
```bash
cp -r "$TEMP_DIR/.claude/agents/"* .claude/agents/ 2>/dev/null || true
cp -r "$TEMP_DIR/.claude/skills/"* .claude/skills/ 2>/dev/null || true
cp -r "$TEMP_DIR/.claude/commands/"* .claude/commands/ 2>/dev/null || true
cp -r "$TEMP_DIR/docs/"* docs/ 2>/dev/null || true
cp "$TEMP_DIR/CLAUDE.md" ./CLAUDE.md 2>/dev/null || true
cp "$TEMP_DIR/settings.local.sample.json" ./settings.local.sample.json 2>/dev/null || true
cp "$TEMP_DIR/.claude/settings.local.json" ./.claude/settings.local.json 2>/dev/null || true
```

4. Clean up the temporary directory:
```bash
rm -rf "$TEMP_DIR"
```

5. Confirm what was synced by listing the synced directories and CLAUDE.md.

6. Remind the user to run `/setup-mcp` to check and install required MCP servers (core-memory).

7. Note: For automatic CORE Memory integration, copy `settings.local.sample.json` to `~/.claude/settings.local.json` (or merge with existing settings).
