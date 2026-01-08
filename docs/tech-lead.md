# Architecture Decisions: Cloudflare Component Selection

> **Related:** For technical implementation patterns, see [saas-cloudflare-engineer.md](./saas-cloudflare-engineer.md). For underlying design principles (the 15 fundamentals), see [saas-architect.md](./saas-architect.md).

## Philosophy

These aren't rigid rules—they're the reasoning behind my preferences. Understanding the "why" matters more than memorizing the "what." When the situation is unclear, ask questions rather than guessing.

---

## The Deployment Question: Pages Functions vs Standalone Workers

The decision between Pages Functions and standalone Workers isn't about code complexity or performance optimization. It's about **deployment overhead and operational burden**.

### Why This Matters

Every standalone Worker is a separate deployment to manage, monitor, and maintain. The question I ask myself:

> Do I want to deploy and monitor many individual Workers, or bundle features into a Pages application?

### When I Keep Everything in Pages Functions

If the app is small and doesn't have standout features that require special attention, the whole app can live in `functions/`. In this case, each Pages Function is doing the work a Worker would do.

**This approach works when:**
- Features don't need independent iteration
- No feature requires Workflows or Durable Objects
- The app is cohesive and deploys as a unit
- I don't need to monitor individual features separately

### When I Use Standalone Workers

Three signals tell me something deserves its own Worker deployment:

1. **Workflows Integration** — If the feature is part of a workflow that requires Workers, it's going to be a Worker. Workflows need Workers to run.

2. **Durable Objects** — If the feature needs Durable Objects for real-time coordination or stateful connections, that's a Worker.

3. **Iteration Velocity** — If I plan to iterate on this feature repeatedly, or I suspect I'm doing it one way now but will change it (maybe a few times), then it's going to be a Worker. Independent deployments make iteration easier.

### The Consistency Principle

Here's what I care about most: **I hate not knowing where things are.**

If the app has key features in Workers, I don't want additional features hidden in Pages Functions. That makes me look in two places. So:

- If some features are in Workers → all features go in Workers
- If features are in Functions → all features stay in Functions
- Forms in one place. Logging in one place. Security in one place.

This consistency is critical. The thin proxy pattern in Pages should do the same thing everywhere—extract, forward, log, return. No exceptions where "this one does a little more."

---

## The Workflow Question: When to Use Durable Execution

The existing docs mention ">30 seconds" as a trigger for Workflows. But duration isn't actually the deciding factor.

### The Real Signal: Dependencies

**Use Workflows when:** One operation's output feeds into another operation's input.

If several workers are calling LLMs but they're independent of each other, that doesn't require a Workflow. They can run in parallel, each doing their thing.

But if Worker A's result is needed by Worker B, and Worker B's result feeds into Worker C—that's a Workflow. The dependency chain is what matters.

### When Workflows Don't Apply

- Independent parallel operations (even if they're all calling LLMs)
- Simple request-response patterns
- Operations that don't feed into each other

---

## The LLM Model Question: Llama vs Claude

### My Default: Llama 4 Scout

I try to use Llama 4 Scout for everything. It's my default choice because:
- Fast response times
- Nearly zero cost
- Good enough for most tasks

### When I Use Claude

Claude is slower and costs money. But it's millions of times better than anything else for certain tasks. I'm choosy about when it's worth the financial and time cost.

**Claude is worth it for:**
- **Serious content analysis** — When I need to understand nuance, catch subtle patterns, or evaluate quality
- **Serious writing** — When the output needs to sound human, maintain voice fidelity, or require creative judgment

**Llama handles everything else:**
- Applying rules to content
- Calculations and structured transformations
- Applying frameworks or rubrics
- Converting one format to another
- Extracting structured data from unstructured input

### The Decision Framework

```
Is this serious analysis or serious writing?
  ├─ Yes → Claude (worth the cost and latency)
  └─ No → Llama (fast and cheap)
```

---

## The Monitoring Question: Observability for Workers

When I deploy standalone Workers, observability is always on. I look there for errors.

### What This Means for Code

Monitoring doesn't change much in the code structure. The key requirement:

> If something isn't working, push it to logs so I can see what's happening.

That's it. No elaborate instrumentation frameworks. Just make sure failures are visible.

---

## Decision Summary

| Decision | Key Question | My Preference |
|----------|--------------|---------------|
| Pages vs Workers | How many deployments do I want to manage? | Fewer is better; bundle unless there's a reason not to |
| Standalone Worker | Does it need Workflows, Durable Objects, or heavy iteration? | If yes to any, extract to Worker |
| Consistency | Are features split between Pages and Workers? | Never split—all in one or all in the other |
| Workflows | Does one operation depend on another's output? | Dependency = Workflow; independence = no Workflow |
| LLM Selection | Is this serious analysis or writing? | Claude for serious work, Llama for everything else |
| Monitoring | What do I need to see? | Errors in logs, observability on |

---

## When In Doubt

These are preferences, not commandments. When the situation doesn't clearly match these patterns:

1. **Ask clarifying questions** — Don't guess at intent
2. **Explain the tradeoffs** — Present options with reasoning
3. **Default to simplicity** — When genuinely uncertain, the simpler option is usually right

The goal is a system where I know where things are, can iterate on features independently when needed, and don't pay for monitoring/deployment overhead I don't need.
