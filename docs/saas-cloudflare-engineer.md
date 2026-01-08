# Cloudflare Blueprint v3: Production-Ready Multi-Tenant SaaS Architecture

## Philosophy

This blueprint emphasizes **explainability + recoverability + security** over "fire-and-forget" automation. Every component is designed to be small, composable, and swappable, with clear separation of concerns and minimal blast radius.

**New in v3:** Combines the best patterns from v1 (state machines, recovery), v2 (middleware, multi-tenancy), and production implementations (security, caching, hybrid architecture). This version provides opinionated, battle-tested patterns for building secure, scalable SaaS applications.

> **Related:** For the underlying design principles, see [saas-architect.md](./saas-architect.md). For component selection decisions (Pages vs Workers, Workflows, LLM models), see [tech-lead.md](./tech-lead.md).

---

## Infrastructure Stack

### Core Cloudflare Services

| Service | Purpose | Use Cases |
|---------|---------|-----------|
| **Workers** | Stateless compute functions | Auth services, business logic, data processing |
| **Pages** | Static hosting + serverless functions | User interfaces, forms, admin dashboards, API proxies |
| **D1** | SQLite-compatible serverless database | Multi-tenant data, work queues, usage tracking, session storage |
| **R2** | Object storage | PDFs, generated media, artifacts, user uploads |
| **KV** | Fast key-value cache | Metadata caching, rate limit counters |
| **Workflows** | Durable execution engine | Long-running AI tasks, multi-step processes |
| **Service Bindings** | Worker-to-worker communication | Clean internal APIs between services |
| **Cron Triggers** | Scheduled execution | Usage resets, cleanup, monitoring, recovery workers |

### External Integrations

- **Anthropic**: LLM processing with claude-sonnet-4-20250514
- **Groq**: Fast LLM inference with meta-llama/llama-4-scout-17b-16e-instruct
- **Stripe**: Subscription billing and payment processing
- **Resend**: Transactional email delivery
- **Google OAuth**: Social authentication (optional)

---

## Architecture Patterns

### 1. Hybrid Architecture Pattern (NEW in v3)

Choose architecture based on application complexity:

**Simple/MVP Applications** → Monolithic Worker
- Single worker handles all routes
- Handlers in separate modules
- Shared database and middleware
- Example: auth + features in one worker

**Complex/Multi-Feature Applications** → Microservices
- Dedicated auth worker
- Feature workers per major capability
- Pages app as API gateway
- Example: auth-worker + feature-worker-1 + feature-worker-2

**When to Use Each:**

| Factor | Monolithic | Microservices |
|--------|------------|---------------|
| Team Size | 1-3 developers | 5+ developers |
| Features | 1-3 core features | 5+ independent features |
| Deploy Frequency | Weekly/monthly | Daily/continuous |
| Scaling Needs | Uniform load | Feature-specific scaling |
| Complexity | Low-medium | Medium-high |

✅ **GOOD Monolith Example**: Simple SaaS with 2-3 features, small team, tight coupling
✅ **GOOD Microservices Example**: Platform with 10+ tools, large team, independent deploy cycles

### 2. Layered Middleware Pattern

Use Cloudflare Pages Functions for middleware that runs before your frontend and API routes. Middleware should be **layered** with clear responsibilities at each level.

#### Root Middleware (`functions/_middleware.js`)

**Purpose**: Session verification and context enrichment

**Responsibilities:**
- Check for session cookie or Authorization header
- Verify session with auth system
- Attach user/company/plan data to request context
- Redirect unauthenticated users to login
- Allow public paths (landing, login, signup, static assets)

**Key Pattern**: Middleware populates `context.data`:

```javascript
context.data = {
  user: { id, email, firstName, lastName, role, emailVerified },
  company: { id, name, slug, subscriptionStatus, stripeCustomerId },
  plan: { name, maxUsers, maxLLMCallsMonthly, features },
  sessionToken: "..."
}
```

This data flows to all downstream Pages Functions and is available without additional auth checks.

#### API Middleware (`functions/api/_middleware.js`)

**Purpose**: Plan enforcement and usage tracking

**Responsibilities:**
- Verify authentication (user must exist from root middleware)
- Check subscription status (active, past_due, canceled)
- Calculate current usage from D1
- Enforce plan limits (prevent requests if limit exceeded)
- Check feature access based on plan
- Attach usage stats and limits to context

**Key Pattern**: Fail fast with clear error messages:

```javascript
// Subscription check
if (company.subscriptionStatus !== 'active') {
  return errorResponse(403, "Subscription inactive", {
    status: company.subscriptionStatus,
    renewUrl: '/billing'
  });
}

// Usage limit check
if (currentUsage >= plan.maxLLMCallsMonthly) {
  return errorResponse(429, "Usage limit exceeded", {
    currentUsage,
    limit: plan.maxLLMCallsMonthly,
    resetDate: getFirstDayOfNextMonth()
  });
}
```

**Why Layered?**
- Separation of concerns: auth vs. authorization vs. usage
- Performance: Only check usage for API calls, not page views
- Maintainability: Each layer has single responsibility
- Flexibility: Can add/remove layers without affecting others

### 3. Thin Proxy Pattern with Rich Context (HYBRID - NEW in v3)

Use Pages Functions as thin proxies to feature workers, but enhance them with rich error context from the application.

**What Makes a Proxy "Thin"?**

Each proxy should do exactly **four** things:
1. Extract request data
2. Forward the request to a feature worker
3. Log the usage to D1 (success or failure)
4. Return the worker's response **with enhanced context**

**Example Structure:**

```javascript
// functions/api/feature-name.js
export async function onRequestPost(context) {
  const { request, env } = context;
  const { user, company, plan, usage } = context.data; // From middleware

  try {
    const body = await request.json();

    // Forward to feature worker
    const workerResponse = await fetch('https://feature.example.com', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    const result = await workerResponse.json();

    // Log usage (success or failure)
    const success = workerResponse.ok;
    await env.DB.prepare(`
      INSERT INTO usage_logs
      (company_id, user_id, worker_name, llm_provider, success, error_message)
      VALUES (?, ?, ?, ?, ?, ?)
    `).bind(
      company.id,
      user.id,
      'feature-name',
      body.llm || 'claude',
      success ? 1 : 0,
      success ? null : result.error
    ).run();

    // Return response with enhanced context if error
    if (!workerResponse.ok) {
      return new Response(JSON.stringify({
        ...result,
        context: {
          currentUsage: usage.current,
          limit: usage.limit,
          remaining: usage.remaining,
          planName: plan.name
        }
      }), {
        status: workerResponse.status,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify(result), {
      status: workerResponse.status,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    // Log catastrophic failure
    await env.DB.prepare(`
      INSERT INTO usage_logs
      (company_id, user_id, worker_name, llm_provider, success, error_message)
      VALUES (?, ?, ?, 'unknown', 0, ?)
    `).bind(company.id, user.id, 'feature-name', error.message).run();

    return errorResponse(500, 'Internal server error', {
      details: error.message,
      currentUsage: usage?.current,
      limit: usage?.limit
    });
  }
}
```

**Why This Hybrid Approach?**
- **Automatic enforcement** (from middleware) prevents forgetting checks
- **Rich error context** (from proxy) provides better user experience
- **Thin** (no business logic in proxy) maintains separation of concerns
- **Usage tracking** (in proxy) ensures all calls are logged

### 4. Secure Authentication Pattern (NEW in v3)

**Password Security**: Use PBKDF2 over bcrypt for better security without dependencies.

```javascript
// utils/crypto.js
export async function hashPassword(password) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const encoder = new TextEncoder();
  const passwordBuffer = encoder.encode(password);

  const key = await crypto.subtle.importKey(
    'raw',
    passwordBuffer,
    { name: 'PBKDF2' },
    false,
    ['deriveBits']
  );

  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt,
      iterations: 100000, // 100k iterations (stronger than bcrypt cost 10)
      hash: 'SHA-256'
    },
    key,
    256 // 32 bytes
  );

  // Combine salt + hash and encode to base64
  const hashArray = new Uint8Array(derivedBits);
  const combined = new Uint8Array(salt.length + hashArray.length);
  combined.set(salt, 0);
  combined.set(hashArray, salt.length);

  return btoa(String.fromCharCode(...combined));
}

export async function verifyPassword(password, hash) {
  // 1. Decode base64 hash
  const combined = new Uint8Array(
    atob(hash).split('').map(c => c.charCodeAt(0))
  );

  // 2. Extract salt (first 16 bytes)
  const salt = combined.slice(0, 16);

  // 3. Extract stored hash (remaining 32 bytes)
  const storedHash = combined.slice(16);

  // 4. Hash provided password with extracted salt
  const encoder = new TextEncoder();
  const passwordBuffer = encoder.encode(password);

  const key = await crypto.subtle.importKey(
    'raw',
    passwordBuffer,
    { name: 'PBKDF2' },
    false,
    ['deriveBits']
  );

  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt,
      iterations: 100000,
      hash: 'SHA-256'
    },
    key,
    256
  );

  const computedHash = new Uint8Array(derivedBits);

  // 5. Constant-time comparison to prevent timing attacks
  let result = 0;
  for (let i = 0; i < computedHash.length; i++) {
    result |= computedHash[i] ^ storedHash[i];
  }

  return result === 0;
}
```

**Why PBKDF2?**
- ✅ No npm dependencies (uses Web Crypto API)
- ✅ 100,000 iterations (stronger than bcrypt cost 10 ≈ 1,024 iterations)
- ✅ Native to Cloudflare Workers
- ✅ FIPS-compliant
- ✅ Constant-time comparison prevents timing attacks

**Session Management**: Enhanced sessions with security metadata.

```javascript
// sessions table
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,                    -- Random 32-byte token
  user_id TEXT NOT NULL,
  expires_at DATETIME NOT NULL,           -- 30 days from creation
  user_agent TEXT,                        -- Browser fingerprint
  ip_address TEXT,                        -- IP for security monitoring
  last_activity_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_sessions_expires ON sessions(expires_at);
CREATE INDEX idx_sessions_user ON sessions(user_id);
```

**Session Creation:**

```javascript
async function createSession(db, userId, userAgent, ipAddress) {
  const sessionId = generateToken(32); // 32-byte random hex
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  await db.prepare(`
    INSERT INTO sessions
    (id, user_id, expires_at, user_agent, ip_address, last_activity_at)
    VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
  `).bind(sessionId, userId, expiresAt.toISOString(), userAgent, ipAddress).run();

  return { sessionId, expiresAt };
}

function generateToken(bytes) {
  const buffer = crypto.getRandomValues(new Uint8Array(bytes));
  return Array.from(buffer).map(b => b.toString(16).padStart(2, '0')).join('');
}
```

**OAuth Support**: Add Google OAuth as optional authentication method.

```javascript
// POST /auth/google/verify
export async function handleGoogleOAuth(request, env) {
  const { idToken } = await request.json();

  // Verify ID token with Google
  const googleResponse = await fetch(
    `https://oauth2.googleapis.com/tokeninfo?id_token=${idToken}`
  );

  if (!googleResponse.ok) {
    return errorResponse(401, 'Invalid Google token');
  }

  const tokenInfo = await googleResponse.json();

  // Validate audience matches your client ID
  if (tokenInfo.aud !== env.GOOGLE_CLIENT_ID) {
    return errorResponse(401, 'Invalid token audience');
  }

  // Extract user info
  const { sub: googleId, email, email_verified, given_name, family_name } = tokenInfo;

  // Find or create user
  let user = await env.DB.prepare(
    'SELECT * FROM users WHERE google_id = ? OR email = ?'
  ).bind(googleId, email).first();

  if (!user) {
    // Create new user with Google ID
    const userId = crypto.randomUUID();
    const companyId = crypto.randomUUID();

    // Create company
    await env.DB.prepare(`
      INSERT INTO companies (id, name, plan_id, subscription_status)
      VALUES (?, ?, 'free', 'active')
    `).bind(companyId, `${given_name}'s Team`, 'free').run();

    // Create user
    await env.DB.prepare(`
      INSERT INTO users
      (id, company_id, email, google_id, first_name, last_name, email_verified, role)
      VALUES (?, ?, ?, ?, ?, ?, 1, 'owner')
    `).bind(userId, companyId, email, googleId, given_name, family_name).run();

    user = { id: userId, company_id: companyId };
  } else if (!user.google_id) {
    // Link existing email account to Google
    await env.DB.prepare(
      'UPDATE users SET google_id = ?, email_verified = 1 WHERE id = ?'
    ).bind(googleId, user.id).run();
  }

  // Create session
  const session = await createSession(
    env.DB,
    user.id,
    request.headers.get('user-agent'),
    request.headers.get('cf-connecting-ip')
  );

  return successResponse({ sessionId: session.sessionId, user });
}
```

### 5. Performance-Optimized Subscription Pattern (NEW in v3)

Combine automatic enforcement (v2) with rich context (v1) and caching (production best practice).

**Subscription Storage**: Separate table (not embedded) for historical tracking.

```sql
-- Subscriptions table (allows history and auditing)
CREATE TABLE subscriptions (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL UNIQUE,
  plan_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'past_due', 'canceled', 'trial')),
  started_at DATETIME NOT NULL,
  expires_at DATETIME NOT NULL,
  trial_ends_at DATETIME,
  stripe_subscription_id TEXT,
  stripe_customer_id TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE,
  FOREIGN KEY (plan_id) REFERENCES plans(id)
);

CREATE INDEX idx_subscriptions_status ON subscriptions(status, expires_at);
CREATE INDEX idx_subscriptions_stripe ON subscriptions(stripe_subscription_id);
```

**Subscription Context with Caching:**

```javascript
// In-memory cache with TTL
const SUBSCRIPTION_CACHE = new Map();
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

export async function getSubscriptionContext(env, companyId) {
  // Check cache first
  const cached = SUBSCRIPTION_CACHE.get(companyId);
  if (cached && (Date.now() - cached.timestamp) < CACHE_TTL) {
    return cached.context;
  }

  // Query subscription with plan limits and usage stats
  const result = await env.DB.prepare(`
    SELECT
      s.*,
      p.name as plan_name,
      p.display_name,
      p.max_users,
      p.max_llm_calls_monthly,
      p.features,
      (SELECT COUNT(*) FROM users WHERE company_id = ? AND active = 1) as user_count,
      (SELECT COUNT(*) FROM usage_logs
       WHERE company_id = ?
       AND created_at >= date('now', 'start of month')
       AND success = 1) as current_usage
    FROM subscriptions s
    JOIN plans p ON s.plan_id = p.id
    WHERE s.company_id = ?
  `).bind(companyId, companyId, companyId).first();

  if (!result) {
    return null;
  }

  const now = Date.now();
  const expiresAt = new Date(result.expires_at).getTime();
  const isExpired = now > expiresAt;
  const isActive = result.status === 'active' && !isExpired;

  const context = {
    subscription: {
      id: result.id,
      company_id: result.company_id,
      plan_id: result.plan_id,
      status: result.status,
      started_at: result.started_at,
      expires_at: result.expires_at,
      stripe_subscription_id: result.stripe_subscription_id,
      isExpired,
      isActive
    },
    limits: {
      max_users: result.max_users,
      max_llm_calls_monthly: result.max_llm_calls_monthly,
      features: JSON.parse(result.features || '{}')
    },
    stats: {
      user_count: result.user_count,
      current_usage: result.current_usage,
      usage_remaining: result.max_llm_calls_monthly - result.current_usage
    },
    // Permission flags for easy checks
    canInviteUser: result.user_count < result.max_users,
    canMakeAPICall: result.current_usage < result.max_llm_calls_monthly,
    hasActiveSubscription: isActive
  };

  // Cache result
  SUBSCRIPTION_CACHE.set(companyId, {
    context,
    timestamp: Date.now()
  });

  return context;
}

export function clearSubscriptionCache(companyId) {
  SUBSCRIPTION_CACHE.delete(companyId);
}
```

**Rich Limit Checking:**

```javascript
export async function checkLimit(env, companyId, action) {
  const context = await getSubscriptionContext(env, companyId);

  if (!context) {
    return {
      allowed: false,
      message: 'No subscription found',
      reason: 'missing_subscription'
    };
  }

  if (!context.hasActiveSubscription) {
    return {
      allowed: false,
      message: `Subscription ${context.subscription.status}. Please update your billing.`,
      reason: 'inactive_subscription',
      context
    };
  }

  // Action-specific checks
  switch (action) {
    case 'invite_user':
      if (!context.canInviteUser) {
        return {
          allowed: false,
          message: `Team size limit reached. Upgrade to add more users.`,
          reason: 'user_limit_exceeded',
          context
        };
      }
      break;

    case 'api_call':
      if (!context.canMakeAPICall) {
        return {
          allowed: false,
          message: `Monthly API limit exceeded (${context.stats.current_usage}/${context.limits.max_llm_calls_monthly}). Upgrade your plan.`,
          reason: 'usage_limit_exceeded',
          context
        };
      }
      break;

    case 'use_feature':
      const featureName = arguments[3]; // 4th argument
      if (!context.limits.features[featureName]) {
        return {
          allowed: false,
          message: `Feature '${featureName}' not available on ${context.subscription.plan_id} plan.`,
          reason: 'feature_not_available',
          context
        };
      }
      break;
  }

  return {
    allowed: true,
    context
  };
}
```

**Usage Pattern in Middleware:**

```javascript
// functions/api/_middleware.js
export async function onRequest(context) {
  const { request, env, next } = context;
  const { company } = context.data;

  // Get rich subscription context with caching
  const subContext = await getSubscriptionContext(env, company.id);

  if (!subContext || !subContext.hasActiveSubscription) {
    return errorResponse(403, "Subscription inactive", {
      status: subContext?.subscription.status,
      expiresAt: subContext?.subscription.expires_at
    });
  }

  // Check usage limit
  if (!subContext.canMakeAPICall) {
    return errorResponse(429, "Usage limit exceeded", {
      currentUsage: subContext.stats.current_usage,
      limit: subContext.limits.max_llm_calls_monthly,
      resetDate: getFirstDayOfNextMonth()
    });
  }

  // Attach to context for downstream use
  context.data.subscription = subContext;

  return next();
}
```

### 6. Cloudflare Workflows for Long-Running Tasks (NEW in v3)

Use Cloudflare Workflows for durable, multi-step processes that can take minutes and survive worker restarts.

**When to Use Workflows:**
- ✅ AI content generation (can take 30+ seconds)
- ✅ Multi-step data processing pipelines
- ✅ External API calls with retries
- ✅ Any task that might exceed Worker CPU time limits

**When NOT to Use Workflows:**
- ❌ Simple CRUD operations
- ❌ Quick API responses (< 1 second)
- ❌ Real-time user interactions

**Example: AI Content Generation Workflow**

```javascript
import { WorkflowEntrypoint } from 'cloudflare:workers';

export class GenerateContentWorkflow extends WorkflowEntrypoint {
  async run(event, step) {
    const { userId, companyId, prompt } = event.params;

    // Step 1: Validate and prepare
    const validation = await step.do('validate-input', async () => {
      // Check subscription limits
      const limitCheck = await checkLimit(this.env, companyId, 'api_call');
      if (!limitCheck.allowed) {
        throw new Error(limitCheck.message);
      }

      return { validated: true };
    });

    // Step 2: Generate content with Claude
    const content = await step.do('generate-content', async () => {
      const response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': this.env.CLAUDE_API_KEY,
          'anthropic-version': '2023-06-01'
        },
        body: JSON.stringify({
          model: 'claude-sonnet-4-20250514',
          max_tokens: 4000,
          messages: [{ role: 'user', content: prompt }]
        })
      });

      const result = await response.json();
      return result.content[0].text;
    });

    // Step 3: Store in R2
    const r2Key = await step.do('store-content', async () => {
      const key = `generated/${companyId}/${crypto.randomUUID()}.md`;
      await this.env.R2_BUCKET.put(key, content);
      return key;
    });

    // Step 4: Log usage
    await step.do('log-usage', async () => {
      await this.env.DB.prepare(`
        INSERT INTO usage_logs
        (company_id, user_id, worker_name, llm_provider, success)
        VALUES (?, ?, 'content-generator', 'claude', 1)
      `).bind(companyId, userId).run();
    });

    // Step 5: Send notification
    await step.do('send-notification', async () => {
      await sendEmail(this.env, {
        to: await getUserEmail(this.env, userId),
        subject: 'Your content is ready!',
        html: `<p>Your AI-generated content is ready. <a href="${baseUrl}/view/${r2Key}">View it here</a>.</p>`
      });
    });

    return { success: true, r2Key };
  }
}

// In your main worker
export default {
  async fetch(request, env) {
    if (request.url.endsWith('/generate')) {
      const { userId, companyId, prompt } = await request.json();

      // Start workflow
      const workflowId = crypto.randomUUID();
      const handle = await env.CONTENT_WORKFLOW.create({
        id: workflowId,
        params: { userId, companyId, prompt }
      });

      return Response.json({
        workflowId,
        status: 'processing',
        statusUrl: `/status/${workflowId}`
      });
    }
  }
}
```

**Workflow Configuration:**

```toml
# wrangler.toml
[[workflows]]
name = "content-workflow"
class_name = "GenerateContentWorkflow"
script_name = "content-generator"
```

**Why Workflows?**
- ✅ Survives worker restarts
- ✅ Built-in retry logic
- ✅ Step-by-step execution
- ✅ Can take minutes (not limited to Worker CPU time)
- ✅ Automatic state persistence

### 7. State Machine Coordination

D1 holds canonical state via status columns that drive workflow progression:

**State Flow Example:**

```
pending → processing → complete
  ↓           ↓           ↓
stuck ←───── stuck ←──── stuck
```

**Database Schema Pattern:**

```sql
CREATE TABLE jobs (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'complete', 'stuck')),
  payload JSON,
  result JSON,
  error_info JSON,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  processed_at DATETIME
);

CREATE INDEX idx_jobs_status ON jobs(status, created_at);
```

**Worker Pattern:**

```javascript
export default {
  async fetch(request, env) {
    const jobId = await getJobId(request);

    // Check current status and claim work
    const job = await env.DB.prepare(
      "SELECT * FROM jobs WHERE id = ? AND status = 'pending'"
    ).bind(jobId).first();

    if (!job) {
      return new Response("Job not pending", { status: 200 });
    }

    // Mark as processing (atomic)
    await env.DB.prepare(
      "UPDATE jobs SET status = 'processing', updated_at = CURRENT_TIMESTAMP WHERE id = ?"
    ).bind(jobId).run();

    try {
      const result = await processJob(job);

      await env.DB.prepare(`
        UPDATE jobs
        SET status = 'complete', result = ?, processed_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).bind(JSON.stringify(result), jobId).run();

      return Response.json({ success: true, result });
    } catch (error) {
      await env.DB.prepare(`
        UPDATE jobs
        SET status = 'stuck', error_info = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).bind(JSON.stringify({ message: error.message, stack: error.stack }), jobId).run();

      throw error;
    }
  }
};
```

### 8. Idempotent Operations

All operations are safe to retry using:
- Record IDs as deterministic keys
- Status flags for coordination
- Atomic state transitions

**Why?** Cloudflare's distributed nature means operations may retry, so idempotency prevents duplicate work.

### 9. Centralized Frontend State

Use a single JavaScript file to manage all client-side state, API calls, and rendering logic.

**Structure (`public/app.js`):**

```javascript
// 1. CONFIGURATION
const CONFIG = {
  authWorkerUrl: 'https://auth.example.com',
  apiBaseUrl: '/api'
};

// 2. STATE MANAGEMENT
const AppState = {
  user: null,
  company: null,
  plan: null,
  sessionToken: null,

  setUser(userData) {
    this.user = userData.user;
    this.company = userData.company;
    this.plan = userData.plan;
    localStorage.setItem('session', JSON.stringify(userData));
  },

  clearUser() {
    this.user = null;
    this.company = null;
    this.plan = null;
    this.sessionToken = null;
    localStorage.removeItem('session');
  },

  getSessionToken() {
    return this.sessionToken;
  }
};

// 3. API HELPERS
const API = {
  async request(url, options = {}) {
    const headers = {
      'Content-Type': 'application/json',
      ...options.headers
    };

    if (AppState.sessionToken) {
      headers['Authorization'] = `Bearer ${AppState.sessionToken}`;
    }

    const response = await fetch(url, {
      ...options,
      headers
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.message || 'Request failed');
    }

    return response.json();
  },

  async verifySession() {
    try {
      const data = await this.request('/api/me');
      AppState.setUser(data);
      return true;
    } catch (error) {
      AppState.clearUser();
      return false;
    }
  },

  async callFeature(featureName, data) {
    return this.request(`/api/${featureName}`, {
      method: 'POST',
      body: JSON.stringify(data)
    });
  }
};

// 4. UI HELPERS
const UI = {
  showLoading(selector) {
    const el = document.querySelector(selector);
    if (el) el.innerHTML = '<div class="spinner">Loading...</div>';
  },

  showError(selector, message) {
    const el = document.querySelector(selector);
    if (el) el.innerHTML = `<div class="error">${message}</div>`;
  },

  updateUserDisplay() {
    if (AppState.user) {
      document.querySelector('#user-name').textContent =
        `${AppState.user.firstName} ${AppState.user.lastName}`;
      document.querySelector('#plan-name').textContent =
        AppState.plan.displayName;
    }
  }
};

// 5. FORM HANDLERS
const FormHandlers = {
  async handleLogin(formData) {
    const email = formData.get('email');
    const password = formData.get('password');

    const response = await API.request('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password })
    });

    AppState.sessionToken = response.sessionId;
    AppState.setUser(response);

    window.location.href = '/dashboard.html';
  },

  async handleFeatureSubmit(formData) {
    const data = Object.fromEntries(formData);
    const result = await API.callFeature('feature-name', data);
    return result;
  }
};

// 6. RENDER HELPERS
const Render = {
  featureResult(data, container) {
    container.innerHTML = `
      <div class="result">
        <h3>${data.title}</h3>
        <p>${data.content}</p>
      </div>
    `;
  }
};

// 7. GLOBAL EXPORT
window.App = {
  AppState,
  API,
  UI,
  FormHandlers,
  Render
};
```

**Why Centralized?**
- ✅ Consistency: All API calls use same error handling
- ✅ Reusability: Shared helpers across all pages
- ✅ Maintainability: One place to update API logic
- ✅ State sharing: Session data available everywhere
- ✅ Type safety: Clear contracts between forms and APIs

---

## Multi-Tenant SaaS Database Schema

### Core Tables

```sql
-- Companies table (tenants)
CREATE TABLE companies (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  stripe_customer_id TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_companies_slug ON companies(slug);
CREATE INDEX idx_companies_stripe ON companies(stripe_customer_id);

-- Users table (belongs to company)
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL,
  email TEXT NOT NULL,
  password_hash TEXT,                    -- Nullable for OAuth-only users
  google_id TEXT UNIQUE,                 -- For Google OAuth
  first_name TEXT,
  last_name TEXT,
  role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'member')),
  active INTEGER DEFAULT 1,              -- 0 for pending invitations
  email_verified INTEGER DEFAULT 0,
  last_login_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE,
  UNIQUE(email, company_id)
);

CREATE INDEX idx_users_company ON users(company_id, active);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_google ON users(google_id);

-- Plans table (subscription tiers)
CREATE TABLE plans (
  id TEXT PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,             -- 'free', 'pro', 'business'
  display_name TEXT NOT NULL,            -- 'Free Plan', 'Pro Plan'
  max_users INTEGER,                     -- NULL = unlimited
  max_llm_calls_monthly INTEGER,         -- NULL = unlimited
  price_monthly REAL NOT NULL,
  features JSON,                         -- { "feature1": true, "feature2": false }
  stripe_price_id TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Subscriptions table (separate for history tracking)
CREATE TABLE subscriptions (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL UNIQUE,
  plan_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'past_due', 'canceled', 'trial')),
  started_at DATETIME NOT NULL,
  expires_at DATETIME NOT NULL,
  trial_ends_at DATETIME,
  stripe_subscription_id TEXT UNIQUE,
  stripe_customer_id TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE,
  FOREIGN KEY (plan_id) REFERENCES plans(id)
);

CREATE INDEX idx_subscriptions_status ON subscriptions(status, expires_at);
CREATE INDEX idx_subscriptions_stripe ON subscriptions(stripe_subscription_id);

-- Sessions table (authentication)
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at DATETIME NOT NULL,
  user_agent TEXT,
  ip_address TEXT,
  last_activity_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_sessions_expires ON sessions(expires_at);
CREATE INDEX idx_sessions_user ON sessions(user_id);

-- Usage logs table (metering and analytics)
CREATE TABLE usage_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  company_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  worker_name TEXT NOT NULL,
  llm_provider TEXT,                     -- 'claude', 'groq', etc.
  success INTEGER DEFAULT 1,             -- 1 = success, 0 = failure
  error_message TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_usage_company_date ON usage_logs(company_id, created_at);
CREATE INDEX idx_usage_success ON usage_logs(success, created_at);
CREATE INDEX idx_usage_worker ON usage_logs(worker_name, created_at);

-- Team invitations table
CREATE TABLE team_invitations (
  id TEXT PRIMARY KEY,
  company_id TEXT NOT NULL,
  email TEXT NOT NULL,
  invited_by TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  role TEXT DEFAULT 'member',
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'expired')),
  expires_at DATETIME NOT NULL,          -- 7 days
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE,
  FOREIGN KEY (invited_by) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_invitations_token ON team_invitations(token);
CREATE INDEX idx_invitations_status ON team_invitations(status, expires_at);

-- Password reset tokens table
CREATE TABLE password_reset_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  expires_at DATETIME NOT NULL,          -- 1 hour
  used INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_reset_tokens_token ON password_reset_tokens(token);
CREATE INDEX idx_reset_tokens_expires ON password_reset_tokens(expires_at, used);
```

### Seed Data

```sql
-- Insert default plans
INSERT INTO plans (id, name, display_name, max_users, max_llm_calls_monthly, price_monthly, features, stripe_price_id)
VALUES
  ('free', 'free', 'Free Plan', 1, 10, 0, '{"basic": true}', NULL),
  ('pro', 'pro', 'Pro Plan', 5, 1000, 29, '{"basic": true, "advanced": true}', 'price_xxx'),
  ('business', 'business', 'Business Plan', NULL, NULL, 99, '{"basic": true, "advanced": true, "premium": true}', 'price_yyy');
```

---

## Implementation Templates

### Worker Structure Template

```javascript
// Standard worker template
export default {
  async fetch(request, env, ctx) {
    // 1. Extract job/request ID
    const jobId = extractJobId(request);

    // 2. Check status and claim work
    const job = await claimWork(env.DB, jobId);
    if (!job) return successResponse("No work available");

    // 3. Process with error handling
    try {
      const result = await processWork(job, env);
      await markComplete(env.DB, jobId, result);
      return successResponse(result);
    } catch (error) {
      await markStuck(env.DB, jobId, error);
      throw error;
    }
  }
};

async function claimWork(db, jobId) {
  const job = await db.prepare(
    "SELECT * FROM jobs WHERE id = ? AND status = 'pending'"
  ).bind(jobId).first();

  if (!job) return null;

  await db.prepare(
    "UPDATE jobs SET status = 'processing' WHERE id = ?"
  ).bind(jobId).run();

  return job;
}
```

### Root Middleware Template

```javascript
// functions/_middleware.js
export async function onRequest(context) {
  const { request, env, next } = context;
  const url = new URL(request.url);

  // Define public paths
  const publicPaths = ['/login', '/signup', '/reset-password', '/'];
  const isPublic = publicPaths.some(path => url.pathname.startsWith(path)) ||
                   url.pathname.match(/\.(css|js|png|jpg|svg)$/);

  // Get session token from cookie or header
  const sessionToken = getSessionToken(request);

  // Redirect to login if no session and not public
  if (!sessionToken && !isPublic) {
    return Response.redirect(new URL('/login', request.url), 302);
  }

  // Verify session if token exists
  if (sessionToken) {
    try {
      const sessionData = await verifySession(env, sessionToken);

      if (sessionData && sessionData.valid) {
        context.data = {
          user: sessionData.user,
          company: sessionData.company,
          plan: sessionData.plan,
          sessionToken
        };
      } else if (!isPublic) {
        // Invalid session, redirect to login
        return Response.redirect(new URL('/login', request.url), 302);
      }
    } catch (error) {
      console.error('Session verification failed:', error);
      if (!isPublic) {
        return Response.redirect(new URL('/login', request.url), 302);
      }
    }
  }

  return next();
}

function getSessionToken(request) {
  // Check Authorization header first
  const authHeader = request.headers.get('Authorization');
  if (authHeader?.startsWith('Bearer ')) {
    return authHeader.substring(7);
  }

  // Check cookie
  const cookies = request.headers.get('Cookie') || '';
  const sessionCookie = cookies.split(';').find(c => c.trim().startsWith('session='));
  if (sessionCookie) {
    return sessionCookie.split('=')[1];
  }

  return null;
}

async function verifySession(env, sessionToken) {
  // Call auth worker or check D1 directly
  const response = await fetch(`${env.AUTH_WORKER_URL}/session/verify`, {
    headers: { 'Authorization': `Bearer ${sessionToken}` }
  });

  if (!response.ok) {
    return null;
  }

  return response.json();
}
```

### API Middleware Template

```javascript
// functions/api/_middleware.js
export async function onRequest(context) {
  const { request, env, next } = context;

  // Require authentication
  if (!context.data.user) {
    return errorResponse(401, "Unauthorized");
  }

  const { company } = context.data;

  // Get subscription context (with caching)
  const subContext = await getSubscriptionContext(env, company.id);

  if (!subContext || !subContext.hasActiveSubscription) {
    return errorResponse(403, "Subscription inactive", {
      status: subContext?.subscription.status,
      expiresAt: subContext?.subscription.expires_at,
      renewUrl: '/billing'
    });
  }

  // Check usage limits
  if (!subContext.canMakeAPICall) {
    return errorResponse(429, "Usage limit exceeded", {
      currentUsage: subContext.stats.current_usage,
      limit: subContext.limits.max_llm_calls_monthly,
      resetDate: getFirstDayOfNextMonth(),
      upgradeUrl: '/billing'
    });
  }

  // Attach subscription context for downstream use
  context.data.subscription = subContext;
  context.data.usage = {
    current: subContext.stats.current_usage,
    limit: subContext.limits.max_llm_calls_monthly,
    remaining: subContext.stats.usage_remaining
  };

  return next();
}

function errorResponse(status, message, details = {}) {
  return new Response(JSON.stringify({
    error: message,
    ...details
  }), {
    status,
    headers: { 'Content-Type': 'application/json' }
  });
}

function getFirstDayOfNextMonth() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth() + 1, 1).toISOString();
}
```

### Thin Proxy Template

```javascript
// functions/api/feature-name.js
export async function onRequestPost(context) {
  const { request, env } = context;
  const { user, company, subscription } = context.data;

  try {
    const body = await request.json();

    // Forward to feature worker
    const workerResponse = await fetch('https://feature-worker.example.com', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    const result = await workerResponse.json();
    const success = workerResponse.ok;

    // Log usage
    await env.DB.prepare(`
      INSERT INTO usage_logs
      (company_id, user_id, worker_name, llm_provider, success, error_message)
      VALUES (?, ?, ?, ?, ?, ?)
    `).bind(
      company.id,
      user.id,
      'feature-name',
      body.llm || 'claude',
      success ? 1 : 0,
      success ? null : result.error
    ).run();

    // Return with enhanced context on error
    if (!success) {
      return new Response(JSON.stringify({
        ...result,
        context: {
          currentUsage: subscription.stats.current_usage,
          limit: subscription.limits.max_llm_calls_monthly,
          remaining: subscription.stats.usage_remaining,
          planName: subscription.subscription.plan_id
        }
      }), {
        status: workerResponse.status,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify(result), {
      status: workerResponse.status,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    // Log catastrophic failure
    await env.DB.prepare(`
      INSERT INTO usage_logs
      (company_id, user_id, worker_name, llm_provider, success, error_message)
      VALUES (?, ?, ?, 'unknown', 0, ?)
    `).bind(company.id, user.id, 'feature-name', error.message).run();

    return new Response(JSON.stringify({
      error: 'Internal server error',
      details: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
```

---

## Data Flow Architecture

### Typical Multi-Tenant Request Flow

```
User Browser
  ↓
Pages UI (HTML form)
  ↓
Root Middleware (verify session, attach user/company/plan)
  ↓
API Middleware (check subscription, usage limits, feature access)
  ↓
Thin Proxy (forward to worker, log usage)
  ↓
Feature Worker (process business logic)
  ↓
D1 / R2 / External API
  ↓
Response back through layers (with enhanced context)
  ↓
Render in UI
```

### Authentication Flow

1. User submits login form
2. Pages sends POST to auth worker
3. Auth worker verifies credentials (PBKDF2)
4. Auth worker creates session in D1 (with user_agent, IP)
5. Auth worker returns sessionId + user/company/plan data
6. Pages sets session cookie
7. Redirect to dashboard
8. Root middleware verifies session on each request
9. Session cached for 5 minutes

### Usage Tracking Flow

1. User submits feature form
2. Root middleware verifies session
3. API middleware checks usage limits (from cache if available)
4. Thin proxy forwards to feature worker
5. Feature worker processes request
6. Thin proxy logs usage to D1 (success/failure)
7. Response returned to user (with context on error)
8. Usage count available for next request (cache cleared if limit reached)

---

## Monitoring and Observability

### Built-in Status Tracking

```sql
-- Monitor job health
SELECT
  status,
  COUNT(*) as count,
  MIN(created_at) as oldest,
  MAX(updated_at) as newest
FROM jobs
GROUP BY status;

-- Monitor usage by company
SELECT
  c.name,
  COUNT(*) as calls_this_month,
  p.max_llm_calls_monthly as limit,
  ROUND((COUNT(*) * 100.0 / p.max_llm_calls_monthly), 2) as usage_percent
FROM usage_logs u
JOIN companies c ON u.company_id = c.id
JOIN subscriptions s ON c.id = s.company_id
JOIN plans p ON s.plan_id = p.id
WHERE u.created_at >= date('now', 'start of month')
  AND u.success = 1
GROUP BY c.id
ORDER BY usage_percent DESC;

-- Monitor error rates by feature
SELECT
  worker_name,
  COUNT(*) as total_calls,
  SUM(success) as successful_calls,
  COUNT(*) - SUM(success) as failed_calls,
  ROUND((1.0 - (SUM(success) * 1.0 / COUNT(*))) * 100, 2) as error_rate_percent
FROM usage_logs
WHERE created_at >= datetime('now', '-24 hours')
GROUP BY worker_name
ORDER BY error_rate_percent DESC;

-- Identify companies approaching limits
SELECT
  c.name,
  COUNT(*) as current_usage,
  p.max_llm_calls_monthly as limit,
  p.max_llm_calls_monthly - COUNT(*) as remaining
FROM usage_logs u
JOIN companies c ON u.company_id = c.id
JOIN subscriptions s ON c.id = s.company_id
JOIN plans p ON s.plan_id = p.id
WHERE u.created_at >= date('now', 'start of month')
  AND u.success = 1
  AND p.max_llm_calls_monthly IS NOT NULL
GROUP BY c.id
HAVING COUNT(*) > (p.max_llm_calls_monthly * 0.8)
ORDER BY remaining ASC;
```

---

## Recovery Patterns

### Cron Worker for Stuck Job Recovery

```javascript
// workers/recovery-worker.js
export default {
  async scheduled(event, env, ctx) {
    // Find stuck jobs older than 1 hour
    const stuckJobs = await env.DB.prepare(`
      SELECT * FROM jobs
      WHERE status = 'stuck'
        AND updated_at < datetime('now', '-1 hour')
      LIMIT 100
    `).all();

    for (const job of stuckJobs.results) {
      try {
        // Retry the job
        await env.FEATURE_WORKER.fetch(createRetryRequest(job));
      } catch (error) {
        console.error(`Failed to retry job ${job.id}:`, error);
      }
    }

    console.log(`Processed ${stuckJobs.results.length} stuck jobs`);
  }
};
```

### Usage Reset Cron (Monthly)

```javascript
// workers/usage-reset-worker.js
export default {
  async scheduled(event, env, ctx) {
    // Archive old usage logs to R2
    const threeMonthsAgo = new Date();
    threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

    const oldLogs = await env.DB.prepare(`
      SELECT * FROM usage_logs
      WHERE created_at < ?
      LIMIT 10000
    `).bind(threeMonthsAgo.toISOString()).all();

    if (oldLogs.results.length > 0) {
      // Archive to R2
      await env.R2_BUCKET.put(
        `usage-archive/${new Date().toISOString()}.json`,
        JSON.stringify(oldLogs.results)
      );

      // Delete archived logs
      await env.DB.prepare(`
        DELETE FROM usage_logs
        WHERE created_at < ?
      `).bind(threeMonthsAgo.toISOString()).run();

      console.log(`Archived ${oldLogs.results.length} usage logs`);
    }

    // Clear subscription cache (force refresh)
    console.log('Monthly usage period rolled over');
  }
};
```

### Session Cleanup Cron (Daily)

```javascript
// workers/session-cleanup-worker.js
export default {
  async scheduled(event, env, ctx) {
    // Delete expired sessions
    const result = await env.DB.prepare(`
      DELETE FROM sessions
      WHERE expires_at < CURRENT_TIMESTAMP
    `).run();

    console.log(`Deleted ${result.meta.changes} expired sessions`);

    // Delete used password reset tokens
    await env.DB.prepare(`
      DELETE FROM password_reset_tokens
      WHERE used = 1 AND created_at < datetime('now', '-7 days')
    `).run();

    // Delete expired team invitations
    await env.DB.prepare(`
      UPDATE team_invitations
      SET status = 'expired'
      WHERE status = 'pending' AND expires_at < CURRENT_TIMESTAMP
    `).run();
  }
};
```

---

## Stripe Integration

### Webhook Handler

```javascript
// POST /api/billing/webhook
export async function handleStripeWebhook(request, env) {
  const signature = request.headers.get('stripe-signature');
  const body = await request.text();

  // Verify webhook signature
  const event = await verifyStripeWebhook(body, signature, env.STRIPE_WEBHOOK_SECRET);

  if (!event) {
    return new Response('Invalid signature', { status: 400 });
  }

  // Route to event handler
  switch (event.type) {
    case 'checkout.session.completed':
      await handleCheckoutCompleted(event.data.object, env);
      break;

    case 'customer.subscription.created':
    case 'customer.subscription.updated':
      await handleSubscriptionUpdated(event.data.object, env);
      break;

    case 'customer.subscription.deleted':
      await handleSubscriptionDeleted(event.data.object, env);
      break;

    case 'invoice.payment_succeeded':
      await handlePaymentSucceeded(event.data.object, env);
      break;

    case 'invoice.payment_failed':
      await handlePaymentFailed(event.data.object, env);
      break;
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' }
  });
}

async function handleSubscriptionUpdated(subscription, env) {
  const companyId = subscription.metadata.company_id;
  const planId = subscription.metadata.plan_id;

  const now = new Date().toISOString();
  const expiresAt = new Date(subscription.current_period_end * 1000).toISOString();

  const status = subscription.status === 'active' ? 'active' :
                 subscription.status === 'past_due' ? 'past_due' :
                 'canceled';

  // Upsert subscription
  await env.DB.prepare(`
    INSERT INTO subscriptions
    (id, company_id, plan_id, status, started_at, expires_at, stripe_subscription_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(company_id) DO UPDATE SET
      plan_id = excluded.plan_id,
      status = excluded.status,
      expires_at = excluded.expires_at,
      stripe_subscription_id = excluded.stripe_subscription_id,
      updated_at = excluded.updated_at
  `).bind(
    crypto.randomUUID(),
    companyId,
    planId,
    status,
    now,
    expiresAt,
    subscription.id,
    now,
    now
  ).run();

  // Clear cache
  clearSubscriptionCache(companyId);

  console.log(`Subscription updated for company ${companyId}`);
}
```

---

## Design Principles

### ✅ Core Principles

1. **Small Blast Radius**: Each worker failure affects minimal scope
2. **Composable**: Workers combine to create complex workflows
3. **Swappable**: Replace components without touching core schema
4. **Stateless**: No local state, everything in D1/R2
5. **Recoverable**: Failed operations can be retried/fixed
6. **Explainable**: Clear audit trail of what happened when
7. **Layered**: Middleware handles auth/usage, proxies handle routing, workers handle logic
8. **Secure by Default**: PBKDF2 hashing, session metadata, constant-time comparison
9. **Performance-Optimized**: Multi-layer caching with TTL
10. **Rich Context**: Detailed error messages with usage stats and limits

### ❌ Anti-Patterns

- Complex workers that do multiple things
- Business logic in middleware or proxies
- Hidden state or implicit dependencies
- Fire-and-forget operations without status tracking
- Tight coupling between components
- Non-idempotent operations
- Thick proxies with validation/transformation logic
- Re-authenticating on every API call (use middleware context)
- Storing subscriptions in companies table (prevents history)
- Using bcrypt (npm dependency, weaker than PBKDF2 100k iterations)

---

## Deployment Architecture

### Separate Deployments

1. **Auth Worker** (if using microservices): Standalone worker at `auth.example.com`
2. **Feature Workers**: Individual workers at `feature1.example.com`, `feature2.example.com`, etc.
3. **Pages App**: Single deployment at `app.example.com` containing:
   - All HTML/CSS/JS files
   - Root middleware (`functions/_middleware.js`)
   - API middleware (`functions/api/_middleware.js`)
   - Thin proxies (`functions/api/*.js`)

### Configuration

```toml
# wrangler.toml (Pages)
name = "app"
compatibility_date = "2024-01-01"
pages_build_output_dir = "public"

[[d1_databases]]
binding = "DB"
database_name = "app-db"
database_id = "xxx"

[[r2_buckets]]
binding = "R2_BUCKET"
bucket_name = "app-assets"

[[kv_namespaces]]
binding = "KV"
id = "xxx"

[[workflows]]
name = "content-workflow"
class_name = "GenerateContentWorkflow"
script_name = "content-generator"

[env.production]
vars = {
  AUTH_WORKER_URL = "https://auth.example.com",
  BASE_URL = "https://app.example.com"
}

# Secrets (set via wrangler secret put)
# STRIPE_SECRET_KEY
# STRIPE_WEBHOOK_SECRET
# CLAUDE_API_KEY
# GROQ_API_KEY
# RESEND_API_KEY
# GOOGLE_CLIENT_ID
```

---

## Key Takeaways

### What's New in v3:

1. **Hybrid Architecture**: Choose monolith or microservices based on complexity
2. **PBKDF2 Authentication**: Stronger password hashing without dependencies
3. **Enhanced Sessions**: Security metadata (user_agent, IP, last_activity)
4. **OAuth Support**: Google Sign-In integration
5. **Performance Caching**: Multi-layer caching with 5-minute TTL
6. **Rich Error Context**: Detailed limit information in responses
7. **Separate Subscriptions Table**: Enables historical tracking and auditing
8. **Cloudflare Workflows**: Durable execution for long-running tasks
9. **Automatic + Rich**: Combines automatic enforcement with rich context
10. **Production-Ready**: Battle-tested patterns from real implementations

### When to Use Each Component:

- **Workers**: Business logic, data processing, external API calls
- **Pages Functions (Middleware)**: Authentication, authorization, usage enforcement
- **Pages Functions (Proxies)**: Routing to workers, usage logging, error boundaries
- **Workflows**: Long-running tasks (AI generation, multi-step processes)
- **D1**: Multi-tenant data, sessions, usage logs, job queues
- **R2**: Large files, generated media, archives
- **KV**: Fast metadata caching, rate limit counters

### Remember:

- Middleware = **protection and enrichment**
- Proxies = **routing and tracking**
- Workers = **business logic**
- Workflows = **durable execution**
- Keep proxies thin, workers focused, middleware layered
- Cache aggressively, invalidate precisely
- Track everything, recover gracefully
- Fail fast with rich context

---

This blueprint ensures every component is **debuggable, recoverable, secure, and swappable** while leveraging Cloudflare's serverless strengths for production-ready multi-tenant SaaS applications.
