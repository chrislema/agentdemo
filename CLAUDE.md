# Project Configuration

## Feature Development Workflow

When building new features or making significant changes, follow this orchestration sequence. The workflow branches based on architecture pattern selection.

---

### Phase 0: Architecture Pattern Selection

**FIRST**, determine whether this feature requires multi-agent collaboration or pipeline processing.

Read `/docs/saas-architect.md` (Architecture Pattern Selection section) and apply the decision framework:

| Use Multi-Agent When | Use Pipeline When |
|---------------------|-------------------|
| Multiple perspectives needed to make decisions | Linear data transformation |
| Real-time adaptation based on intermediate results | Fixed rules, predictable flow |
| Parallel observers synthesizing into coordinated action | Sequential dependencies |
| Human-like reasoning or conversation | Batch processing |
| Dynamic coordination required | Static orchestration sufficient |

**Quick Decision:**
```
Does the feature need multiple specialists observing and reasoning together?
├─ Yes → Multi-Agent Track
└─ No → Pipeline/Traditional SaaS Track
```

---

## Track A: Pipeline/Traditional SaaS (Cloudflare)

For features that follow linear data flow, static orchestration, and fixed transformation rules.

### Phase 1: Planning (Sequential)

1. **plan-decisions** agent runs FIRST
   - Input: Feature request from user
   - Output: `/docs/decisions/{feature-name}.md`
   - Makes technology choices: Pages vs Workers, Workflows, Durable Objects, LLM selection
   - Reference: `/docs/tech-lead.md`

2. **plan-architecture** agent runs AFTER decisions complete
   - Input: `/docs/decisions/{feature-name}.md`
   - Output: `/docs/plans/{feature-name}.md`
   - Creates component breakdown, data flow, database schema, error scenarios
   - Reference: `/docs/saas-architect.md`

### Phase 2: Implementation (Parallel)

After plan-architecture completes and user approves, spawn these THREE agents IN PARALLEL:

- **build-backend**: Workers, Functions, middleware, database
  - Reference: `/docs/saas-cloudflare-engineer.md`
  - Owns: `functions/`, `workers/`, `src/utils/`, `*.sql`

- **build-frontend**: HTML, CSS, vanilla JavaScript
  - Reference: `/docs/saas-designer.md`
  - Owns: `public/*.html`, `public/*.css`, `public/*.js`

- **build-tests**: Playwright E2E, API, smoke tests
  - Reference: `/docs/saas-qa.md`
  - Owns: `tests/`, `playwright.config.ts`

---

## Track B: Multi-Agent Collaboration (Elixir/Jido)

For features that require multiple specialists observing, reasoning, and coordinating dynamically.

### Phase 1: Planning (Sequential)

1. **plan-decisions** agent runs FIRST
   - Input: Feature request from user
   - Output: `/docs/decisions/{feature-name}.md`
   - Makes technology choices: Agent types (LLM vs pure logic), communication patterns, coordination strategy, LLM provider selection
   - Reference: `/docs/multi-agent-tech-lead.md`

2. **plan-architecture** agent runs AFTER decisions complete
   - Input: `/docs/decisions/{feature-name}.md`
   - Output: `/docs/plans/{feature-name}.md`
   - Creates agent breakdown, PubSub topics, state management, collection windows, fallback logic
   - Reference: `/docs/saas-architect.md`

### Phase 2: Implementation (Parallel)

After plan-architecture completes and user approves, spawn these THREE agents IN PARALLEL:

- **build-backend**: Elixir agents, Coordinator, State GenServers, LLM integration
  - Reference: `/docs/multi-agent-engineer.md`
  - Owns: `lib/*/agents/`, `lib/*/coordinator.ex`, `lib/*/*_state.ex`

- **build-frontend**: Phoenix LiveView, real-time UI, PubSub subscriptions
  - Reference: `/docs/multi-agent-engineer.md` (LiveView Integration section)
  - Owns: `lib/*_web/live/`, `lib/*_web/components/`

- **build-tests**: Agent unit tests, integration tests, PubSub tests
  - Reference: `/docs/multi-agent-engineer.md` (Testing Patterns section)
  - Owns: `test/*/agents/`, `test/*/integration/`

---

## Orchestration Rules

1. NEVER skip Phase 0 (architecture pattern selection) - it determines the entire track
2. NEVER skip plan-decisions - it catches critical requirements early
3. NEVER run build agents sequentially when they can run in parallel
4. Each build agent works on its owned files only - no overlap
5. All agents commit to `feature/{feature-name}` branch

## When to Trigger This Workflow

Use the full workflow when:
- Building a new feature
- Adding significant functionality
- The system might need multi-agent collaboration
- Making architectural changes

Skip to build agents (parallel) when:
- Plan already exists in `/docs/plans/`
- User provides explicit implementation instructions
- Simple bug fixes or minor changes

## Memory Agents (CORE Memory Integration)

Two agents provide automatic memory integration with CORE Memory:

- **memory-search**: Auto-invoked at session start to retrieve context from previous sessions
- **memory-ingest**: Auto-invoked after interactions to store summaries for future retrieval

These require:
1. CORE Memory MCP server installed (`/setup-mcp`)
2. Hooks configured in `~/.claude/settings.local.json` (see `settings.local.sample.json`)

## Reference Documents

### Core Philosophy (Both Tracks)

| Document | Purpose |
|----------|---------|
| `/docs/saas-architect.md` | 15 architectural principles + pattern selection |

### Pipeline/Traditional SaaS Track (Cloudflare)

| Document | Purpose |
|----------|---------|
| `/docs/tech-lead.md` | Technology decisions: Pages vs Workers, Workflows, LLM selection |
| `/docs/saas-cloudflare-engineer.md` | Cloudflare implementation patterns |
| `/docs/saas-designer.md` | Frontend design system |
| `/docs/saas-qa.md` | Testing strategy |

### Multi-Agent Track (Elixir/Jido)

| Document | Purpose |
|----------|---------|
| `/docs/multi-agent-tech-lead.md` | Technology decisions: Agent types, communication, coordination |
| `/docs/multi-agent-engineer.md` | Elixir/Jido implementation patterns |

## Invocation Examples

```
# Full workflow - Multi-Agent
"Build an interview system with multiple AI evaluators"
→ Phase 0: Determine pattern → Multi-Agent (multiple perspectives, real-time adaptation)
→ Use plan-decisions agent with multi-agent-tech-lead.md
→ Then plan-architecture agent
→ Then build-backend, build-frontend, build-tests agents in parallel (multi-agent track)

# Full workflow - Pipeline
"Build a PDF processing feature that extracts and summarizes content"
→ Phase 0: Determine pattern → Pipeline (linear data flow, fixed transformation)
→ Use plan-decisions agent with tech-lead.md
→ Then plan-architecture agent
→ Then build-backend, build-frontend, build-tests agents in parallel (Cloudflare track)

# Skip to implementation (plan exists)
"Implement the notification feature from /docs/plans/notifications.md"
→ Check plan to determine track
→ Use appropriate build agents in parallel

# Single agent task
"Add a new pure logic agent that tracks word count"
→ Use build-backend agent only with multi-agent-engineer.md reference
```
