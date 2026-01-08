# Architectural Philosophy: Building Debuggable Systems

## Core Premise

**Systems should be optimized for the 2 AM production incident where you're half-asleep, users are angry, and you need to understand what's wrong and fix it quickly.**

Everything flows from this premise: small blast radius, explicit state, rich context, recovery by design, and built-in observability.

This philosophy prioritizes **explainability + recoverability + security** over "fire-and-forget" automation.

> **Related Documentation:**
> - **Pipeline/Traditional SaaS:** [tech-lead.md](./tech-lead.md) → [saas-cloudflare-engineer.md](./saas-cloudflare-engineer.md)
> - **Multi-Agent Collaboration:** [multi-agent-tech-lead.md](./multi-agent-tech-lead.md) → [multi-agent-engineer.md](./multi-agent-engineer.md)

---

## Architecture Pattern Selection: Pipeline vs Multi-Agent

Before applying the 15 principles, determine which architectural pattern fits your problem. This decision shapes everything downstream.

### When to Use Pipeline/Traditional Architecture

Pipeline architecture treats computation as a series of transformations: Input → Step 1 → Step 2 → Step 3 → Output.

**Use Pipeline When:**

| Signal | Example |
|--------|---------|
| **Linear data flow** | PDF upload → extract text → summarize → store |
| **Fixed transformation rules** | Apply template, validate schema, format output |
| **Predictable orchestration** | Same steps every time, no runtime decisions |
| **Single concern per request** | Generate invoice, send email, process payment |
| **Batch processing** | Nightly report generation, data migration |
| **No real-time adaptation needed** | Rules don't change based on intermediate results |

**Pipeline Characteristics:**
- Steps are deterministic and composable
- Errors halt or retry the pipeline
- State flows forward, never backward
- Orchestration is static (defined at design time)
- Each step has one job

**Example Pipeline:**
```
User Upload → Validate → Transform → Enrich → Store → Notify
     ↓            ↓          ↓          ↓        ↓        ↓
   (fail)      (fail)     (fail)     (fail)   (fail)   (fail)
     ↓            ↓          ↓          ↓        ↓        ↓
   [Recovery Queue - retry or manual intervention]
```

### When to Use Multi-Agent Collaboration

Multi-agent architecture treats computation as a conversation between specialists who observe, reason, and coordinate.

**Use Multi-Agent When:**

| Signal | Example |
|--------|---------|
| **Multiple perspectives needed** | Interviewer + evaluator + timekeeper + grader |
| **Real-time adaptation** | Adjust questions based on answer quality |
| **Parallel observation** | Multiple agents watch same event, contribute insights |
| **Dynamic coordination** | Central coordinator synthesizes inputs, makes decisions |
| **Human-like reasoning** | "Given what I've observed, what should happen next?" |
| **Emergent behavior desired** | System behavior arises from agent interactions |

**Multi-Agent Characteristics:**
- Agents have distinct roles and expertise
- Communication is event-driven (publish/subscribe)
- Decisions emerge from synthesizing observations
- Some agents use LLMs, others use pure logic
- Coordination can be centralized or emergent
- State is shared but agents maintain local context

**Example Multi-Agent System:**
```
                    ┌─────────────────┐
                    │   Coordinator   │ ← Synthesizes observations, decides
                    │   (LLM-powered) │
                    └────────┬────────┘
                             │ directives
         ┌───────────────────┼───────────────────┐
         ↓                   ↓                   ↓
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Timekeeper  │     │DepthExpert │     │   Grader    │
│(pure logic) │     │(LLM-powered)│     │(pure logic) │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                           │ observations
                    ┌──────┴──────┐
                    │  PubSub Bus │
                    └─────────────┘
```

### Decision Framework

Ask these questions in order:

```
1. Does the system need to adapt behavior based on intermediate results?
   ├─ No → Pipeline (static orchestration is sufficient)
   └─ Yes → Continue...

2. Are multiple perspectives required to make good decisions?
   ├─ No → Pipeline (single logic path works)
   └─ Yes → Continue...

3. Should different concerns observe the same events simultaneously?
   ├─ No → Pipeline (sequential processing works)
   └─ Yes → Multi-Agent

4. Is human-like reasoning or conversation a core requirement?
   ├─ No → Pipeline (rules and transforms suffice)
   └─ Yes → Multi-Agent
```

### Hybrid Approaches

Some systems combine both patterns:

- **Pipeline with Agent Steps:** Most steps are transforms, but one step involves agent reasoning
- **Agents Triggering Pipelines:** Coordinator decides to launch a pipeline for batch work
- **Pipeline Feeding Agents:** Data pipeline prepares context, then agents take over for interaction

The key is clarity: know which pattern governs each part of your system.

### Pattern Selection Summary

| Factor | Pipeline | Multi-Agent |
|--------|----------|-------------|
| **Data flow** | Linear, forward-only | Event-driven, bidirectional |
| **Orchestration** | Static, defined at design time | Dynamic, emerges at runtime |
| **Decision making** | Rules and conditions | Observation and reasoning |
| **Error handling** | Halt, retry, or skip | Adapt, compensate, or escalate |
| **State** | Flows through steps | Shared via events |
| **Concurrency** | Sequential or fan-out | Parallel observers |
| **Best for** | Data processing, workflows | Conversations, collaboration |

**Once you've chosen your pattern, the 15 principles below apply to both.** The principles are about building debuggable systems—the pattern determines how components are organized.

---

## The 15 Fundamental Principles

### 1. Granularity & Blast Radius

**Principle:** Composition over Complexity

**Question:** How small should each component be?

**Answer:** Small enough that failure affects minimal scope, big enough to be coherent.

**In Practice:**
- Each function/service does ONE thing
- Each module has ONE responsibility
- Failures are isolated, not cascading
- You can understand any single component in 5 minutes

**Why It Matters:**
When something breaks at 2 AM, you need to quickly identify which piece failed without understanding the entire system. Small components = small debugging surface area.

**Anti-Pattern:**
```
BAD: Monolithic function that does auth + validation + business logic + external API calls + logging
GOOD: Five separate functions, each with clear purpose, composed together
```

**Decision Framework:**
- Can you explain what this component does in one sentence?
- If this fails, will it take down unrelated functionality?
- Can you test this in isolation?

If "no" to any of these, your component is too large.

---

### 2. Error Handling Strategy

**Principle:** Errors are Data, Not Control Flow

**Question:** Where should error handling logic live?

**Answer:** Errors are handled at boundaries, not inline.

**In Practice:**
- Business logic throws, it doesn't catch
- Boundaries catch and handle appropriately
- Recovery is a separate concern
- Don't scatter try-catch throughout your code

**Why It Matters:**
Mixing error handling with business logic makes code unreadable and makes it impossible to change error handling strategy without touching business logic.

**Architecture Pattern:**
```
Business Logic Layer
    ↓ (throws errors)
Boundary Layer (API handler, proxy)
    ↓ (catches, logs, enriches)
Recovery Layer (cron, retry workers)
    ↓ (handles permanent failures)
```

**Anti-Pattern:**
```javascript
// BAD: Nested try-catch throughout business logic
async function processOrder(order) {
  try {
    const validated = await validateOrder(order);
    try {
      const charged = await chargePayment(validated);
      try {
        const shipped = await shipOrder(charged);
        return shipped;
      } catch (shipError) {
        await refundPayment(charged);
        log.error(shipError);
        return { error: "Shipping failed" };
      }
    } catch (paymentError) {
      log.error(paymentError);
      return { error: "Payment failed" };
    }
  } catch (validationError) {
    log.error(validationError);
    return { error: "Validation failed" };
  }
}

// GOOD: Business logic throws, boundary catches
async function processOrder(order) {
  const validated = await validateOrder(order);  // throws
  const charged = await chargePayment(validated); // throws
  const shipped = await shipOrder(charged);       // throws
  return shipped;
}

// Error handling at boundary
async function handleOrderRequest(req, res) {
  try {
    const result = await processOrder(req.body);
    res.json({ success: true, result });
  } catch (error) {
    logError(error, { orderId: req.body.id });
    res.status(500).json({
      error: error.message,
      orderId: req.body.id,
      retryable: isRetryableError(error)
    });
  }
}
```

---

### 3. Trust Boundaries

**Principle:** Explicit Trust Zones with Clear Entry Points

**Question:** Where do you verify vs where do you trust?

**Answer:** Verify once at entry, trust within boundaries.

**In Practice:**
- Authenticate at the edge
- Pass verified identity through the system
- Don't re-verify inside trusted boundaries
- Make trust boundaries explicit in architecture

**Why It Matters:**
Re-verification wastes resources and makes it unclear where security decisions happen. If you authenticate in multiple places, which one is authoritative?

**Architecture Pattern:**
```
UNTRUSTED
    ↓
[Authentication Boundary]
    ↓
TRUSTED
(context flows through)
    ↓
[Authorization Boundary]
    ↓
PERMITTED
(business logic)
```

**Anti-Pattern:**
```
BAD:
- Every function checks authentication
- Database queries include "AND user_id = ?"
- Unclear who is responsible for security decisions

GOOD:
- Single authentication layer at entry point
- Verified user context flows through system
- Authorization checks at capability boundaries only
```

**Decision Framework:**
- Authentication: Who are you? (verify once)
- Authorization: Can you do this? (check at boundaries)
- Business logic: Assume permission, execute

---

### 4. State Management Philosophy

**Principle:** Single Source of Truth with Derived Views

**Question:** Where does truth live?

**Answer:** Database is canonical, everything else is derived.

**In Practice:**
- State machines in database, not code
- No local state in services
- Caches are optimization, not truth
- If unsure about state, query the source

**Why It Matters:**
When debugging, you need ONE place to look to understand current state. If state is scattered across services, caches, and local variables, debugging is impossible.

**State Machine Pattern:**
```sql
CREATE TABLE jobs (
  id TEXT PRIMARY KEY,
  status TEXT CHECK (status IN ('pending', 'processing', 'complete', 'stuck')),
  payload JSON,
  result JSON,
  error_info JSON,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

**Anti-Pattern:**
```
BAD:
- Order status in application memory
- Cache contains authoritative state
- Multiple services maintain their own state

GOOD:
- Database contains authoritative state
- Services query for current state
- Caches are invalidated when state changes
```

**Decision Framework:**
- Can multiple services arrive at different conclusions about state?
- If your service crashes, is state lost?
- Can you query "what is the state of all pending jobs?"

If "yes", "yes", "no" respectively, your state management is wrong.

---

### 5. Fail Fast vs Fail Gracefully

**Principle:** Explicit Failure is Better Than Implicit Degradation

**Question:** When something goes wrong, should you continue or stop?

**Answer:** Fail fast with rich context, recover later.

**In Practice:**
- Invalid state? Return error immediately
- Limits exceeded? Don't silently degrade
- Unclear situation? Mark as "stuck" rather than guess
- Recovery is a separate process

**Why It Matters:**
Silent failures create mysterious behavior. Users don't know what's wrong, developers can't debug, problems compound.

**Response Pattern:**
```javascript
// BAD: Silent degradation
if (subscription.expired) {
  return generateLowQualityResult(input); // Just reduce quality
}

// GOOD: Explicit failure with context
if (subscription.expired) {
  throw new SubscriptionExpiredError({
    message: "Subscription expired",
    expiredAt: subscription.expiresAt,
    renewUrl: "/billing",
    currentState: subscription.status
  });
}
```

**Decision Framework:**
- Can you continue safely? → Continue
- Can you recover automatically? → Retry
- Uncertain or dangerous? → Fail fast
- User can fix it? → Explain how
- System can fix it later? → Mark for recovery

---

### 6. Context Enrichment Philosophy

**Principle:** Errors are User Interface

**Question:** How much context should errors contain?

**Answer:** Enough that users know what to do next.

**In Practice:**
- Don't just return error codes
- Include current state, limits, and next steps
- Error messages are part of UX
- Different audiences need different context

**Why It Matters:**
Poor error messages multiply support burden, frustrate users, and slow debugging. Good error messages ARE good product design.

**Error Enrichment Levels:**

```javascript
// Level 1 (Useless):
{ "error": "Invalid request" }

// Level 2 (Basic):
{ "error": "Usage limit exceeded" }

// Level 3 (Helpful):
{
  "error": "Usage limit exceeded",
  "details": {
    "currentUsage": 1000,
    "limit": 1000,
    "resetDate": "2025-12-01T00:00:00Z"
  }
}

// Level 4 (Actionable):
{
  "error": "Usage limit exceeded",
  "details": {
    "currentUsage": 1000,
    "limit": 1000,
    "remaining": 0,
    "resetDate": "2025-12-01T00:00:00Z",
    "planName": "Pro Plan"
  },
  "actions": [
    {
      "label": "Upgrade Plan",
      "url": "/billing/upgrade",
      "description": "Increase your monthly limit to 10,000"
    },
    {
      "label": "Wait for Reset",
      "description": "Your limit resets on December 1st"
    }
  ]
}
```

**Decision Framework:**
- User-facing error: What can they do about it?
- Developer error: What code caused this?
- Operations error: What system state led to this?

---

### 7. Caching Strategy

**Principle:** Performance Through Intelligent Staleness

**Question:** When should you cache vs query fresh?

**Answer:** Cache aggressively, invalidate precisely.

**In Practice:**
- Not everything needs real-time data
- Know your consistency requirements
- Cache at the right layer
- Invalidate on writes, not on reads

**Why It Matters:**
Over-caching causes stale data bugs. Under-caching causes performance issues. The key is knowing what can be stale and for how long.

**Consistency Requirements Matrix:**

| Data Type | Staleness Tolerance | Cache Strategy |
|-----------|---------------------|----------------|
| User session | 5 minutes | In-memory with TTL |
| Subscription status | 5 minutes | In-memory, invalidate on webhook |
| Product catalog | 1 hour | CDN cache |
| Real-time inventory | 0 seconds | No cache, query fresh |
| User preferences | 1 day | Browser localStorage + server cache |
| Static assets | Forever | CDN with versioned URLs |

**Caching Pattern:**
```javascript
// Cache with TTL
const CACHE = new Map();
const TTL = 5 * 60 * 1000; // 5 minutes

async function getSubscription(companyId) {
  const cached = CACHE.get(companyId);
  if (cached && (Date.now() - cached.timestamp) < TTL) {
    return cached.data;
  }

  const data = await db.query(
    'SELECT * FROM subscriptions WHERE company_id = ?',
    [companyId]
  );

  CACHE.set(companyId, { data, timestamp: Date.now() });
  return data;
}

// Invalidate on write
async function updateSubscription(companyId, updates) {
  await db.query('UPDATE subscriptions SET ... WHERE company_id = ?', [companyId]);
  CACHE.delete(companyId); // Precise invalidation
}
```

**Decision Framework:**
- What's the worst case if data is stale?
- How often does this data change?
- What's the cost of a cache miss?
- Can you invalidate precisely or must you invalidate broadly?

---

### 8. Layered Responsibility

**Principle:** Vertical Slicing with Horizontal Concerns

**Question:** Should one layer do multiple things or should concerns be separated?

**Answer:** Separate layers for separate concerns, even if it feels repetitive.

**In Practice:**
- Authentication layer: Who are you?
- Authorization layer: Can you do this?
- Validation layer: Is the input valid?
- Business logic layer: What should happen?
- Persistence layer: How do we store it?

**Why It Matters:**
Mixed concerns make change expensive. If auth and business logic are intertwined, changing auth requires understanding all business logic.

**Layer Responsibilities:**
```
┌─────────────────────────────────────────┐
│ Presentation Layer                      │
│ - Parse request                         │
│ - Format response                       │
│ - Handle content negotiation            │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ Authentication Layer                    │
│ - Verify identity                       │
│ - Validate tokens/credentials           │
│ - Populate user context                 │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ Authorization Layer                     │
│ - Check permissions                     │
│ - Enforce usage limits                  │
│ - Verify feature access                 │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ Validation Layer                        │
│ - Validate input structure              │
│ - Check business rules                  │
│ - Sanitize data                         │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ Business Logic Layer                    │
│ - Execute workflows                     │
│ - Apply domain rules                    │
│ - Coordinate operations                 │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ Data Access Layer                       │
│ - Query database                        │
│ - Transform data                        │
│ - Handle transactions                   │
└─────────────────────────────────────────┘
```

**Anti-Pattern:**
```javascript
// BAD: Mixed concerns
async function processPayment(user, amount) {
  // Auth + authorization + validation + business logic + persistence mixed
  if (!user.token) throw new Error("Not authenticated");
  if (!user.canMakePayment) throw new Error("Not authorized");
  if (amount <= 0) throw new Error("Invalid amount");
  if (user.balance < amount) throw new Error("Insufficient funds");
  const charge = await stripe.charge(amount);
  await db.query('INSERT INTO payments ...');
  return charge;
}

// GOOD: Clear layers
async function handlePaymentRequest(req, res) {
  const user = await authenticateRequest(req);               // Auth layer
  await authorizePayment(user, req.body.amount);             // Authz layer
  const validatedAmount = validateAmount(req.body.amount);   // Validation layer
  const result = await processPayment(user.id, validatedAmount); // Business logic
  res.json({ success: true, result });
}
```

**Decision Framework:**
- Can I change authentication without touching business logic?
- Can I add a new authorization rule without modifying existing code?
- Can I test each layer in isolation?

---

### 9. Recovery as Design, Not Afterthought

**Principle:** Design for Failure Scenarios, Not Just Happy Path

**Question:** When should you think about recovery?

**Answer:** During design, not after production failures.

**In Practice:**
- Every operation can fail
- Failed operations need recovery paths
- Recovery is automated, not manual
- Status tracking is built-in

**Why It Matters:**
Production systems fail. If recovery is an afterthought, you're writing recovery code during outages while users are angry.

**Recovery Design Pattern:**
```sql
-- Jobs have explicit failure state from day one
CREATE TABLE jobs (
  id TEXT PRIMARY KEY,
  status TEXT CHECK (status IN (
    'pending',
    'processing',
    'complete',
    'stuck'  -- Explicit failure state
  )),
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 3,
  last_error TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

```javascript
// Recovery worker runs on schedule
async function recoverStuckJobs() {
  const stuckJobs = await db.query(`
    SELECT * FROM jobs
    WHERE status = 'stuck'
      AND retry_count < max_retries
      AND updated_at < NOW() - INTERVAL '1 hour'
  `);

  for (const job of stuckJobs) {
    try {
      await retryJob(job);
      await db.query(`
        UPDATE jobs
        SET status = 'processing', retry_count = retry_count + 1
        WHERE id = ?
      `, [job.id]);
    } catch (error) {
      // Will be picked up in next recovery run
      await db.query(`
        UPDATE jobs
        SET last_error = ?, updated_at = NOW()
        WHERE id = ?
      `, [error.message, job.id]);
    }
  }
}
```

**Recovery Strategies:**

| Failure Type | Recovery Strategy |
|--------------|-------------------|
| Transient network error | Automatic retry with exponential backoff |
| Invalid input | Mark as failed, alert for manual review |
| External service down | Queue for retry when service recovers |
| Data corruption | Rollback transaction, alert operations |
| Logic bug | Mark as stuck, fix code, replay |

**Decision Framework:**
- Is this failure transient or permanent?
- Can we retry automatically?
- Do we need human intervention?
- What's the rollback strategy?

---

### 10. Data Flow Transparency

**Principle:** Explainability Over Magic

**Question:** Should data transformations be implicit or explicit?

**Answer:** Explicit and obvious.

**In Practice:**
- Data flow is visible
- No hidden mutations
- No action at a distance
- Tracing is possible without deep knowledge

**Why It Matters:**
When debugging, you need to trace data through the system. If transformations are implicit or hidden, debugging becomes archaeology.

**Transparent Pattern:**
```javascript
// GOOD: Explicit data flow
async function handleRequest(req, res) {
  // 1. Parse (explicit)
  const input = parseRequestBody(req);

  // 2. Validate (explicit)
  const validated = validateInput(input);

  // 3. Enrich with context (explicit)
  const enriched = {
    ...validated,
    userId: req.user.id,
    timestamp: Date.now()
  };

  // 4. Process (explicit)
  const result = await processData(enriched);

  // 5. Transform for response (explicit)
  const response = formatResponse(result);

  res.json(response);
}

// BAD: Magic transformations
async function handleRequest(req, res) {
  const result = await processData(req.body); // What happened to req.body?
  res.json(result); // What format is result?
}
```

**Logging Pattern:**
```javascript
// Make data flow visible
async function processOrder(order) {
  console.log('Processing order:', { orderId: order.id, status: 'started' });

  const validated = await validateOrder(order);
  console.log('Order validated:', { orderId: order.id, items: validated.items.length });

  const charged = await chargePayment(validated);
  console.log('Payment charged:', { orderId: order.id, amount: charged.amount });

  const shipped = await shipOrder(charged);
  console.log('Order shipped:', { orderId: order.id, trackingNumber: shipped.tracking });

  return shipped;
}
```

**Decision Framework:**
- Can someone trace this request through the logs?
- Are transformations explicit or hidden in frameworks?
- Can you explain the data flow in one sentence per step?

---

### 11. Security Posture

**Principle:** Security is Non-Negotiable

**Question:** Should security be opt-in or default?

**Answer:** Secure by default, no shortcuts.

**In Practice:**
- Use strongest practical cryptography
- No "good enough" compromises
- Timing attack prevention
- Security metadata collection

**Why It Matters:**
Security shortcuts are how breaches happen. "Good enough" crypto gets broken. Convenience over security is how API keys leak.

**Security Standards:**

**Password Hashing:**
```javascript
// BAD: Weak hashing
const hash = sha256(password); // No salt, too fast

// MEDIOCRE: "Good enough" hashing
const hash = bcrypt.hash(password, 10); // Only 1,024 iterations

// GOOD: Strong hashing
const hash = pbkdf2(password, salt, 100000, 'sha256'); // 100,000 iterations
```

**Comparison:**
```javascript
// BAD: Timing attack vulnerable
function compareTokens(provided, stored) {
  return provided === stored; // Leaks info through timing
}

// GOOD: Constant-time comparison
function compareTokens(provided, stored) {
  if (provided.length !== stored.length) return false;
  let result = 0;
  for (let i = 0; i < provided.length; i++) {
    result |= provided.charCodeAt(i) ^ stored.charCodeAt(i);
  }
  return result === 0;
}
```

**Session Management:**
```sql
-- GOOD: Security metadata
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  expires_at TIMESTAMP,
  user_agent TEXT,      -- Detect device changes
  ip_address TEXT,      -- Detect location changes
  last_activity TIMESTAMP -- Detect stale sessions
);
```

**Decision Framework:**
- Is this the strongest practical option?
- Are we vulnerable to timing attacks?
- Can we detect suspicious activity?
- Do we collect enough security metadata?

---

### 12. Thin Boundaries with Rich Context

**Principle:** Separation of Concerns Doesn't Mean Poor UX

**Question:** How much logic belongs at boundaries vs in business logic?

**Answer:** Boundaries are thin but context-aware.

**In Practice:**
- Boundaries route, don't decide
- Business logic has no awareness of boundaries
- Boundaries enrich responses with context
- Clear separation, rich experience

**Why It Matters:**
"Thin proxies" shouldn't mean "unhelpful errors." You can maintain separation of concerns while providing excellent user experience.

**Proxy Pattern:**
```javascript
// Thin proxy: does exactly 4 things
async function proxyToService(req, res) {
  // 1. Extract request data
  const input = extractRequestData(req);

  // 2. Forward to service
  const serviceResponse = await callService(input);

  // 3. Log the interaction
  await logUsage({
    userId: req.user.id,
    service: 'feature-name',
    success: serviceResponse.ok,
    error: serviceResponse.error
  });

  // 4. Return with enriched context
  if (!serviceResponse.ok) {
    return res.status(serviceResponse.status).json({
      ...serviceResponse.body,
      context: {
        currentUsage: req.usage.current,
        limit: req.usage.limit,
        remaining: req.usage.remaining,
        upgradeUrl: '/billing'
      }
    });
  }

  return res.json(serviceResponse.body);
}
```

**Anti-Pattern:**
```javascript
// BAD: Thick proxy (too much logic)
async function proxyToService(req, res) {
  const input = extractRequestData(req);

  // Validation doesn't belong here
  if (!input.email || !input.email.includes('@')) {
    return res.status(400).json({ error: 'Invalid email' });
  }

  // Business decisions don't belong here
  if (req.user.plan === 'free' && input.quality === 'high') {
    input.quality = 'low'; // Silently downgrade
  }

  const serviceResponse = await callService(input);

  // Transformation doesn't belong here
  if (serviceResponse.ok) {
    serviceResponse.body.result = processResult(serviceResponse.body.result);
  }

  return res.json(serviceResponse.body);
}
```

**Decision Framework:**
- Does this boundary make business decisions? → Too thick
- Does this boundary validate business rules? → Too thick
- Does this boundary transform domain data? → Too thick
- Does this boundary route and enrich? → Just right

---

### 13. Observability Built-In

**Principle:** Observability is Architecture, Not Instrumentation

**Question:** When do you add monitoring?

**Answer:** It's not added, it's intrinsic.

**In Practice:**
- Schema supports monitoring queries naturally
- Timestamps on everything
- Status tracking is part of design
- Monitoring is a query, not a tool

**Why It Matters:**
If you have to "add monitoring," your architecture doesn't support visibility. Good architecture makes monitoring queries natural.

**Observable Schema:**
```sql
-- Every table has timestamps
CREATE TABLE orders (
  id TEXT PRIMARY KEY,
  status TEXT,
  user_id TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- When created
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- When last changed
  processed_at TIMESTAMP -- When completed
);

-- Status enables monitoring
SELECT
  status,
  COUNT(*) as count,
  MIN(created_at) as oldest,
  AVG(EXTRACT(EPOCH FROM (processed_at - created_at))) as avg_duration_seconds
FROM orders
WHERE created_at >= NOW() - INTERVAL '24 hours'
GROUP BY status;
```

**Observable Events:**
```sql
-- Usage tracking is part of architecture
CREATE TABLE api_calls (
  id SERIAL PRIMARY KEY,
  user_id TEXT,
  endpoint TEXT,
  success BOOLEAN,
  duration_ms INTEGER,
  error_message TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Monitoring query
SELECT
  endpoint,
  COUNT(*) as total_calls,
  SUM(CASE WHEN success THEN 1 ELSE 0 END) as successful,
  AVG(duration_ms) as avg_duration,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms) as p95_duration
FROM api_calls
WHERE created_at >= NOW() - INTERVAL '1 hour'
GROUP BY endpoint
ORDER BY total_calls DESC;
```

**Decision Framework:**
- Can you answer "how many X are in state Y?" with a query?
- Can you calculate error rates without external tools?
- Can you identify bottlenecks from your data?
- Can you audit "what happened to order #123?" from logs?

---

### 14. Complexity Budget

**Principle:** Manage Cognitive Load Through Decomposition

**Question:** Where should complexity live?

**Answer:** In composition, not in components.

**In Practice:**
- Each piece is simple
- Complexity emerges from composition
- Any component can be understood in 5 minutes
- The system is complex, the parts are not

**Why It Matters:**
Humans can only hold ~7 things in working memory. If a component is too complex to fit in working memory, debugging is impossible.

**Complexity Example:**
```javascript
// BAD: COMPLEX COMPONENT (400 lines)
function processUserRequest(req) {
  // Auth logic (50 lines)
  // Validation logic (75 lines)
  // Business logic (150 lines)
  // Persistence logic (75 lines)
  // Error handling (50 lines)
}

// GOOD: SIMPLE COMPONENTS (5 × 80 lines)
function authenticate(req) { ... }       // 80 lines
function validate(data) { ... }          // 80 lines
function processOrder(data) { ... }      // 80 lines
function persistOrder(order) { ... }     // 80 lines
function handleErrors(error, ctx) { ... } // 80 lines

function processUserRequest(req) {
  const user = authenticate(req);           // 1 line
  const data = validate(req.body);          // 1 line
  const order = processOrder(data);         // 1 line
  persistOrder(order);                      // 1 line
  return order;                             // 1 line
} // Total: 5 lines
```

**Measuring Complexity:**
- Lines of code in single function
- Cyclomatic complexity (branches)
- Number of dependencies
- Time to understand for new developer

**Complexity Budget:**
- Function: < 50 lines
- Class/Module: < 200 lines
- File: < 500 lines
- Service: < 2000 lines

**Decision Framework:**
- Can you explain this component in 2 minutes?
- How many concepts must you hold in mind?
- How many branches/conditions exist?
- Could you rewrite this from memory?

---

### 15. User Experience Ownership

**Principle:** Services Provide Capabilities, Applications Provide Experiences

**Question:** Who owns the user-facing experience?

**Answer:** The application layer, not the service layer.

**In Practice:**
- Services return technical results
- Applications translate to user terms
- Services are reusable, applications are specific
- Context is added at the edge

**Why It Matters:**
If services try to own UX, they become tightly coupled to specific use cases. If applications don't own UX, users get raw technical errors.

**Layer Responsibilities:**
```
Service Layer (Technical)
    ↓
Returns: { error: "INSUFFICIENT_QUOTA", quota_used: 1000, quota_limit: 1000 }

Application Layer (User-Facing)
    ↓
Translates to: "You've used all 1,000 API calls this month.
               Your limit resets on Dec 1st, or upgrade to Pro
               for 10,000 calls/month."
```

**Pattern:**
```javascript
// Service layer: technical
class PaymentService {
  async charge(amount, userId) {
    if (amount > MAX_CHARGE) {
      throw new PaymentError('AMOUNT_EXCEEDS_LIMIT', {
        amount,
        limit: MAX_CHARGE
      });
    }
    // ... process payment
  }
}

// Application layer: user-facing
class CheckoutController {
  async processCheckout(req, res) {
    try {
      await paymentService.charge(req.body.amount, req.user.id);
      res.json({
        success: true,
        message: "Payment successful! Check your email for receipt."
      });
    } catch (error) {
      if (error.code === 'AMOUNT_EXCEEDS_LIMIT') {
        res.status(400).json({
          error: "Payment amount too large",
          message: `The maximum charge is $${error.limit}. Please reduce your cart total or contact support for higher limits.`,
          actions: [
            { label: "Contact Support", url: "/support" },
            { label: "Review Cart", url: "/cart" }
          ]
        });
      } else {
        res.status(500).json({
          error: "Payment failed",
          message: "We couldn't process your payment. Please try again or contact support.",
          supportEmail: "support@example.com"
        });
      }
    }
  }
}
```

**Decision Framework:**
- Is this error message helpful to an end user? → Application concern
- Is this a reusable technical capability? → Service concern
- Does this reference specific UI elements? → Application concern
- Could this be used by multiple applications? → Service concern

---

## Putting It All Together

### The Architecture Checklist

When reviewing a system design, ask:

**Granularity:**
- [ ] Can each component fail independently?
- [ ] Can you understand any component in < 5 minutes?

**Error Handling:**
- [ ] Are errors handled at boundaries, not inline?
- [ ] Is recovery a separate concern?

**Trust:**
- [ ] Is there a clear trust boundary?
- [ ] Do you verify once and trust within?

**State:**
- [ ] Is there a single source of truth?
- [ ] Can you query current state at any time?

**Failures:**
- [ ] Do you fail fast with rich context?
- [ ] Is recovery automated?

**Context:**
- [ ] Do error messages tell users what to do?
- [ ] Can developers debug from error messages?

**Caching:**
- [ ] Do you know what can be stale and for how long?
- [ ] Can you invalidate precisely?

**Layers:**
- [ ] Are concerns separated into layers?
- [ ] Can you change one layer without affecting others?

**Recovery:**
- [ ] Was recovery designed in, not added later?
- [ ] Can stuck jobs be recovered automatically?

**Transparency:**
- [ ] Can you trace data flow through logs?
- [ ] Are transformations explicit?

**Security:**
- [ ] Are you using the strongest practical crypto?
- [ ] Have you prevented timing attacks?

**Boundaries:**
- [ ] Are boundaries thin but context-aware?
- [ ] Do boundaries route rather than decide?

**Observability:**
- [ ] Can you answer monitoring questions with queries?
- [ ] Is status tracking built into the schema?

**Complexity:**
- [ ] Is each component < 200 lines?
- [ ] Does complexity live in composition?

**UX:**
- [ ] Does the application layer own user experience?
- [ ] Do services provide reusable capabilities?

---

## Common Scenarios

### Scenario 1: Adding a New Feature

**Wrong Approach:**
1. Add feature logic to existing monolithic handler
2. Mix new auth checks into feature code
3. Add validation inline
4. Hope error handling works

**Right Approach:**
1. Create focused feature service (business logic only)
2. Add boundary handler (routing + context enrichment)
3. Existing auth middleware applies automatically
4. Errors handled at boundary with rich context
5. Recovery cron picks up failures automatically

**Result:** Feature is isolated, debuggable, recoverable.

### Scenario 2: Debugging Production Issue

**Without These Principles:**
1. User reports "it's broken"
2. No logs to trace request
3. Can't determine current state
4. Error message says "error 500"
5. Spend hours reproducing
6. Fix requires touching multiple files

**With These Principles:**
1. User reports "it's broken" with request ID
2. Trace request through logs (data flow transparency)
3. Query database for current state (single source of truth)
4. Error message explains what failed and why (context enrichment)
5. Identify exact component that failed (small blast radius)
6. Fix single component (thin boundaries)
7. Replay stuck jobs (recovery design)

**Result:** Issue resolved in minutes, not hours.

### Scenario 3: Scaling Team

**Without These Principles:**
- New developers need weeks to understand codebase
- Changes require understanding entire system
- Multiple people edit same files (conflicts)
- Testing requires spinning up entire system
- Deploys are risky (big blast radius)

**With These Principles:**
- New developers understand one component in < 1 day
- Changes are isolated to relevant components
- Clear boundaries prevent conflicts
- Components can be tested in isolation
- Deploys are low-risk (small blast radius)

**Result:** Team scales linearly, not logarithmically.

---

## Anti-Patterns to Avoid

### 1. The God Function
```javascript
// BAD
async function handleEverything(req, res) {
  // 500 lines of mixed concerns
}
```

### 2. Silent Degradation
```javascript
// BAD
if (error) {
  return fallbackValue; // User never knows something failed
}
```

### 3. Scattered State
```javascript
// BAD
const orderStatus = req.session.orderStatus; // State in session
const orderStatus = cache.get('order');       // State in cache
const orderStatus = await db.query('...');    // State in DB
// Which is authoritative?
```

### 4. Missing Recovery
```javascript
// BAD
try {
  await processJob(job);
} catch (error) {
  console.error(error); // Log and forget
}
```

### 5. Opaque Data Flow
```javascript
// BAD
const result = await magicService.process(input);
// What happened to input? What transformations occurred?
```

### 6. Re-verification Hell
```javascript
// BAD
async function featureA(user) {
  await verifyAuth(user); // Verified again
  // ...
}

async function featureB(user) {
  await verifyAuth(user); // Verified again
  // ...
}
```

### 7. Thick Boundaries
```javascript
// BAD
async function proxy(req, res) {
  // Validation logic
  // Business logic
  // Transformation logic
  // Then forwards to service
}
```

### 8. Useless Errors
```javascript
// BAD
throw new Error("Invalid input");
// What input? What's invalid? What should I do?
```

### 9. Hidden Complexity
```javascript
// BAD
async function simpleFunction(input) {
  // 300 lines of complex logic hidden in "simple" function
}
```

### 10. Service-Owned UX
```javascript
// BAD: In reusable service
throw new Error("Payment failed. Please contact support at support@example.com");
// Tightly coupled to specific application
```

---

## Summary

These 15 principles work together to create systems that are:

- **Debuggable:** Small components, explicit flow, rich errors
- **Recoverable:** Designed for failure, automated recovery
- **Secure:** No shortcuts, strong defaults
- **Maintainable:** Separated concerns, thin boundaries
- **Observable:** Built-in monitoring, status tracking
- **Scalable:** Composition over complexity
- **User-Friendly:** Rich context, actionable errors

**The ultimate test:** Can a tired developer at 2 AM understand what's broken and fix it quickly?

If yes, you've built a debuggable system.

If no, revisit these principles.

---

## Further Reading

This philosophy is informed by:

- **Systems thinking:** Small pieces loosely joined
- **DDD:** Bounded contexts and ubiquitous language
- **SRE:** Error budgets and observability
- **12-Factor App:** Stateless processes and explicit dependencies
- **Clean Architecture:** Dependency inversion and separation of concerns

But ultimately, it's about **empathy for future-you** who will be debugging this under pressure.

Build systems you'd want to debug at 2 AM.
