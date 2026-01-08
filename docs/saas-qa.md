# Testing Guide: Playwright E2E Testing Strategy

## Philosophy

Tests are not optional extras—they're the safety net that lets you deploy with confidence. Every deployment should pass tests. No exceptions.

**Priority:** Confidence over coverage. A focused test suite that catches real problems beats 100% coverage that never runs.

> **Related:** For architectural patterns being tested, see [saas-cloudflare-engineer.md](./saas-cloudflare-engineer.md).

---

## Why Playwright

| Criteria | Playwright |
|----------|------------|
| Cross-browser | Chromium, Firefox, WebKit |
| Speed | Parallel execution, fast |
| Reliability | Auto-wait, no flaky selectors |
| Debugging | Trace viewer, screenshots, videos |
| CI/CD | First-class GitHub Actions support |
| API Testing | Built-in request context |

**No other dependencies needed.** Playwright handles browser testing, API testing, and visual regression in one package.

---

## Project Structure

```
project/
├── tests/
│   ├── e2e/                    # End-to-end user flows
│   │   ├── auth.spec.ts        # Login, logout, signup, password reset
│   │   ├── onboarding.spec.ts  # New user flows
│   │   ├── billing.spec.ts     # Subscription, upgrade, cancel
│   │   └── features/           # Feature-specific tests
│   │       ├── feature-a.spec.ts
│   │       └── feature-b.spec.ts
│   ├── api/                    # API endpoint tests
│   │   ├── auth.api.spec.ts
│   │   └── features.api.spec.ts
│   ├── smoke/                  # Quick sanity checks (run on every deploy)
│   │   └── smoke.spec.ts
│   └── fixtures/               # Shared test utilities
│       ├── auth.fixture.ts     # Authenticated user setup
│       └── test-data.ts        # Test data generators
├── playwright.config.ts
└── package.json
```

---

## Configuration

### playwright.config.ts

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',

  // Run tests in parallel
  fullyParallel: true,

  // Fail the build on CI if you accidentally left test.only
  forbidOnly: !!process.env.CI,

  // Retry failed tests (2x on CI, 0 locally)
  retries: process.env.CI ? 2 : 0,

  // Limit parallel workers on CI
  workers: process.env.CI ? 1 : undefined,

  // Reporter configuration
  reporter: [
    ['html', { open: 'never' }],
    ['json', { outputFile: 'test-results/results.json' }],
    process.env.CI ? ['github'] : ['list']
  ],

  use: {
    // Base URL for relative navigation
    baseURL: process.env.TEST_BASE_URL || 'http://localhost:8788',

    // Collect trace on first retry
    trace: 'on-first-retry',

    // Screenshot on failure
    screenshot: 'only-on-failure',

    // Video on failure
    video: 'retain-on-failure',
  },

  // Project configurations
  projects: [
    // Smoke tests - run first, fast
    {
      name: 'smoke',
      testDir: './tests/smoke',
      use: { ...devices['Desktop Chrome'] },
    },

    // E2E tests - full browser matrix
    {
      name: 'chromium',
      testDir: './tests/e2e',
      use: { ...devices['Desktop Chrome'] },
      dependencies: ['smoke'],
    },
    {
      name: 'firefox',
      testDir: './tests/e2e',
      use: { ...devices['Desktop Firefox'] },
      dependencies: ['smoke'],
    },
    {
      name: 'webkit',
      testDir: './tests/e2e',
      use: { ...devices['Desktop Safari'] },
      dependencies: ['smoke'],
    },

    // Mobile tests
    {
      name: 'mobile-chrome',
      testDir: './tests/e2e',
      use: { ...devices['Pixel 5'] },
      dependencies: ['smoke'],
    },
    {
      name: 'mobile-safari',
      testDir: './tests/e2e',
      use: { ...devices['iPhone 12'] },
      dependencies: ['smoke'],
    },

    // API tests - no browser needed
    {
      name: 'api',
      testDir: './tests/api',
      use: { baseURL: process.env.TEST_API_URL || 'http://localhost:8788' },
    },
  ],

  // Local dev server
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:8788',
    reuseExistingServer: !process.env.CI,
    timeout: 120 * 1000,
  },
});
```

### package.json Scripts

```json
{
  "scripts": {
    "dev": "wrangler pages dev public --d1 DB=app-db --port 8788",
    "test": "playwright test",
    "test:smoke": "playwright test --project=smoke",
    "test:e2e": "playwright test --project=chromium",
    "test:api": "playwright test --project=api",
    "test:all": "playwright test",
    "test:ui": "playwright test --ui",
    "test:debug": "playwright test --debug",
    "test:report": "playwright show-report",
    "test:codegen": "playwright codegen http://localhost:8788"
  }
}
```

---

## Test Types

### 1. Smoke Tests (Run Every Deploy)

Quick sanity checks that critical paths work. Run in under 2 minutes.

```typescript
// tests/smoke/smoke.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Smoke Tests', () => {
  test('homepage loads', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle(/App Name/);
  });

  test('login page accessible', async ({ page }) => {
    await page.goto('/login');
    await expect(page.getByRole('button', { name: 'Sign In' })).toBeVisible();
  });

  test('API health check', async ({ request }) => {
    const response = await request.get('/api/health');
    expect(response.ok()).toBeTruthy();
  });

  test('static assets load', async ({ page }) => {
    await page.goto('/');

    // Check CSS loaded
    const styles = await page.evaluate(() => {
      return window.getComputedStyle(document.body).fontFamily;
    });
    expect(styles).not.toBe('');

    // Check JS loaded
    const appExists = await page.evaluate(() => 'App' in window);
    expect(appExists).toBeTruthy();
  });
});
```

### 2. Authentication Tests

```typescript
// tests/e2e/auth.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Authentication', () => {
  test.describe('Login', () => {
    test('successful login redirects to dashboard', async ({ page }) => {
      await page.goto('/login');

      await page.getByLabel('Email').fill('test@example.com');
      await page.getByLabel('Password').fill('testpassword123');
      await page.getByRole('button', { name: 'Sign In' }).click();

      await expect(page).toHaveURL('/dashboard');
      await expect(page.getByText('test@example.com')).toBeVisible();
    });

    test('invalid credentials show error', async ({ page }) => {
      await page.goto('/login');

      await page.getByLabel('Email').fill('wrong@example.com');
      await page.getByLabel('Password').fill('wrongpassword');
      await page.getByRole('button', { name: 'Sign In' }).click();

      await expect(page.getByText('Invalid email or password')).toBeVisible();
      await expect(page).toHaveURL('/login');
    });

    test('empty fields show validation errors', async ({ page }) => {
      await page.goto('/login');
      await page.getByRole('button', { name: 'Sign In' }).click();

      await expect(page.getByText('Email is required')).toBeVisible();
      await expect(page.getByText('Password is required')).toBeVisible();
    });
  });

  test.describe('Logout', () => {
    test('logout clears session and redirects', async ({ page }) => {
      // Login first
      await page.goto('/login');
      await page.getByLabel('Email').fill('test@example.com');
      await page.getByLabel('Password').fill('testpassword123');
      await page.getByRole('button', { name: 'Sign In' }).click();
      await expect(page).toHaveURL('/dashboard');

      // Logout
      await page.getByText('test@example.com').click();
      await page.getByRole('link', { name: 'Logout' }).click();

      await expect(page).toHaveURL('/login');

      // Verify session cleared - trying to access dashboard redirects
      await page.goto('/dashboard');
      await expect(page).toHaveURL('/login');
    });
  });

  test.describe('Signup', () => {
    test('new user can create account', async ({ page }) => {
      const uniqueEmail = `test-${Date.now()}@example.com`;

      await page.goto('/signup');

      await page.getByLabel('First Name').fill('Test');
      await page.getByLabel('Last Name').fill('User');
      await page.getByLabel('Email').fill(uniqueEmail);
      await page.getByLabel('Password').fill('securepassword123');
      await page.getByLabel('Confirm Password').fill('securepassword123');
      await page.getByRole('button', { name: 'Create Account' }).click();

      // Should redirect to dashboard or verification page
      await expect(page).toHaveURL(/\/(dashboard|verify-email)/);
    });

    test('duplicate email shows error', async ({ page }) => {
      await page.goto('/signup');

      await page.getByLabel('First Name').fill('Test');
      await page.getByLabel('Last Name').fill('User');
      await page.getByLabel('Email').fill('existing@example.com');
      await page.getByLabel('Password').fill('securepassword123');
      await page.getByLabel('Confirm Password').fill('securepassword123');
      await page.getByRole('button', { name: 'Create Account' }).click();

      await expect(page.getByText(/already exists|already registered/i)).toBeVisible();
    });
  });
});
```

### 3. API Tests

```typescript
// tests/api/auth.api.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Auth API', () => {
  test('POST /api/auth/login - valid credentials', async ({ request }) => {
    const response = await request.post('/api/auth/login', {
      data: {
        email: 'test@example.com',
        password: 'testpassword123'
      }
    });

    expect(response.ok()).toBeTruthy();

    const body = await response.json();
    expect(body.sessionId).toBeDefined();
    expect(body.user.email).toBe('test@example.com');
  });

  test('POST /api/auth/login - invalid credentials', async ({ request }) => {
    const response = await request.post('/api/auth/login', {
      data: {
        email: 'wrong@example.com',
        password: 'wrongpassword'
      }
    });

    expect(response.status()).toBe(401);

    const body = await response.json();
    expect(body.error).toBeDefined();
  });

  test('GET /api/me - requires authentication', async ({ request }) => {
    const response = await request.get('/api/me');
    expect(response.status()).toBe(401);
  });

  test('GET /api/me - with valid session', async ({ request }) => {
    // Login first
    const loginResponse = await request.post('/api/auth/login', {
      data: {
        email: 'test@example.com',
        password: 'testpassword123'
      }
    });

    const { sessionId } = await loginResponse.json();

    // Use session
    const meResponse = await request.get('/api/me', {
      headers: {
        'Authorization': `Bearer ${sessionId}`
      }
    });

    expect(meResponse.ok()).toBeTruthy();

    const body = await meResponse.json();
    expect(body.user.email).toBe('test@example.com');
  });
});
```

### 4. Feature Tests

```typescript
// tests/e2e/features/feature-a.spec.ts
import { test, expect } from '@playwright/test';
import { authenticatedPage } from '../../fixtures/auth.fixture';

test.describe('Feature A', () => {
  // Use authenticated fixture
  test.use({ storageState: 'tests/.auth/user.json' });

  test('can submit feature form', async ({ page }) => {
    await page.goto('/feature-a');

    await page.getByLabel('Input Field').fill('test input');
    await page.getByRole('button', { name: 'Submit' }).click();

    // Wait for result
    await expect(page.getByTestId('result')).toBeVisible();
    await expect(page.getByTestId('result')).toContainText('Success');
  });

  test('shows usage limit warning', async ({ page }) => {
    await page.goto('/feature-a');

    // Check usage display
    await expect(page.getByTestId('usage-counter')).toBeVisible();
  });

  test('handles API error gracefully', async ({ page }) => {
    // Mock API error
    await page.route('/api/feature-a', route => {
      route.fulfill({
        status: 500,
        body: JSON.stringify({ error: 'Internal server error' })
      });
    });

    await page.goto('/feature-a');
    await page.getByLabel('Input Field').fill('test');
    await page.getByRole('button', { name: 'Submit' }).click();

    await expect(page.getByText(/error|failed/i)).toBeVisible();
  });
});
```

---

## Test Fixtures

### Authentication Fixture

```typescript
// tests/fixtures/auth.fixture.ts
import { test as base, expect } from '@playwright/test';

// Extend base test with authentication
export const test = base.extend<{
  authenticatedPage: void;
}>({
  authenticatedPage: async ({ page }, use) => {
    // Login before test
    await page.goto('/login');
    await page.getByLabel('Email').fill('test@example.com');
    await page.getByLabel('Password').fill('testpassword123');
    await page.getByRole('button', { name: 'Sign In' }).click();
    await expect(page).toHaveURL('/dashboard');

    await use();
  },
});

// Setup authentication state for reuse
// Run with: npx playwright test --project=setup
export async function globalSetup() {
  const { chromium } = await import('@playwright/test');
  const browser = await chromium.launch();
  const page = await browser.newPage();

  await page.goto('http://localhost:8788/login');
  await page.getByLabel('Email').fill('test@example.com');
  await page.getByLabel('Password').fill('testpassword123');
  await page.getByRole('button', { name: 'Sign In' }).click();
  await page.waitForURL('/dashboard');

  // Save authentication state
  await page.context().storageState({ path: 'tests/.auth/user.json' });

  await browser.close();
}
```

### Test Data Generator

```typescript
// tests/fixtures/test-data.ts
export function generateTestUser() {
  const timestamp = Date.now();
  return {
    email: `test-${timestamp}@example.com`,
    password: 'TestPassword123!',
    firstName: 'Test',
    lastName: `User${timestamp}`,
  };
}

export function generateTestCompany() {
  const timestamp = Date.now();
  return {
    name: `Test Company ${timestamp}`,
    slug: `test-company-${timestamp}`,
  };
}

export const TEST_USERS = {
  owner: {
    email: 'owner@example.com',
    password: 'ownerpassword123',
    role: 'owner',
  },
  admin: {
    email: 'admin@example.com',
    password: 'adminpassword123',
    role: 'admin',
  },
  member: {
    email: 'member@example.com',
    password: 'memberpassword123',
    role: 'member',
  },
};
```

---

## When to Run Tests

### Test Execution Matrix

| Event | Smoke | E2E | API | Full Matrix |
|-------|-------|-----|-----|-------------|
| Every commit (local) | ✅ | ❌ | ❌ | ❌ |
| Before push to GitHub | ✅ | ✅ | ✅ | ❌ |
| Pull request | ✅ | ✅ | ✅ | ❌ |
| Pre-deployment | ✅ | ✅ | ✅ | ✅ |
| Production deploy | ✅ | ❌ | ❌ | ❌ |

### Pre-Deployment Checklist

```bash
# Before any deployment to Cloudflare:

# 1. Run smoke tests (must pass)
npm run test:smoke

# 2. Run full E2E suite
npm run test:e2e

# 3. Run API tests
npm run test:api

# 4. If deploying to production, run full matrix
npm run test:all

# 5. Only then deploy
wrangler pages deploy public
```

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  smoke:
    name: Smoke Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium

      - name: Run smoke tests
        run: npm run test:smoke

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: smoke-results
          path: test-results/

  e2e:
    name: E2E Tests
    needs: smoke
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        project: [chromium, firefox, webkit]
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Install Playwright browsers
        run: npx playwright install --with-deps ${{ matrix.project }}

      - name: Run E2E tests
        run: npx playwright test --project=${{ matrix.project }}

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: e2e-results-${{ matrix.project }}
          path: |
            test-results/
            playwright-report/

  api:
    name: API Tests
    needs: smoke
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run API tests
        run: npm run test:api

  deploy:
    name: Deploy
    needs: [e2e, api]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Deploy to Cloudflare
        run: npx wrangler pages deploy public
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

---

## Writing Good Tests

### Test Naming Convention

```typescript
// Pattern: [action] [expected result] [condition]

// Good
test('login redirects to dashboard with valid credentials', ...)
test('signup shows error when email already exists', ...)
test('form disables submit button while loading', ...)

// Bad
test('test1', ...)
test('login works', ...)
test('should work correctly', ...)
```

### Selector Strategy

**Priority order:**

1. **Role** - `getByRole('button', { name: 'Submit' })`
2. **Label** - `getByLabel('Email')`
3. **Text** - `getByText('Welcome')`
4. **Test ID** - `getByTestId('submit-button')` (fallback)

```typescript
// Good - semantic, accessible
await page.getByRole('button', { name: 'Sign In' }).click();
await page.getByLabel('Email').fill('test@example.com');

// Avoid - brittle, implementation-dependent
await page.click('#btn-submit');
await page.locator('.form-input-email').fill('test@example.com');
```

### Assertions

```typescript
// Good - specific assertions
await expect(page).toHaveURL('/dashboard');
await expect(page.getByRole('heading')).toHaveText('Dashboard');
await expect(page.getByTestId('user-menu')).toBeVisible();

// Good - wait for network
await page.waitForResponse('/api/data');

// Avoid - arbitrary waits
await page.waitForTimeout(2000); // Don't do this
```

---

## Debugging Failed Tests

### Local Debugging

```bash
# Run with headed browser
npm run test:debug

# Run with UI mode (interactive)
npm run test:ui

# Generate new test with codegen
npm run test:codegen
```

### Trace Viewer

```bash
# Open trace from failed test
npx playwright show-trace test-results/path/to/trace.zip
```

### Screenshots and Videos

Failed tests automatically capture:
- Screenshot at failure point
- Video of entire test (on CI)
- Trace file for step-by-step debugging

---

## Test Database Strategy

### Option 1: Test Database (Recommended)

```bash
# Create separate D1 database for tests
wrangler d1 create app-db-test

# Use in tests via environment variable
TEST_DATABASE_ID=xxx npm run test
```

### Option 2: Database Seeding

```typescript
// tests/fixtures/db-seed.ts
export async function seedTestData(db: D1Database) {
  // Clear existing test data
  await db.exec(`DELETE FROM users WHERE email LIKE 'test-%'`);

  // Insert test users
  await db.prepare(`
    INSERT INTO users (id, email, password_hash, ...)
    VALUES (?, ?, ?, ...)
  `).bind(...testUser).run();
}
```

### Option 3: API-Based Setup

```typescript
// Use your API to set up test state
test.beforeEach(async ({ request }) => {
  await request.post('/api/test/reset');
  await request.post('/api/test/seed');
});
```

---

## Performance Testing

### Basic Performance Checks

```typescript
test('page loads within performance budget', async ({ page }) => {
  await page.goto('/dashboard');

  const timing = await page.evaluate(() => {
    const nav = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming;
    return {
      domContentLoaded: nav.domContentLoadedEventEnd - nav.startTime,
      load: nav.loadEventEnd - nav.startTime,
    };
  });

  expect(timing.domContentLoaded).toBeLessThan(2000); // 2 seconds
  expect(timing.load).toBeLessThan(5000); // 5 seconds
});
```

---

## Summary

### Test Hierarchy

```
Smoke Tests (< 2 min)
    ↓ must pass
E2E Tests (5-15 min)
    ↓ must pass
API Tests (2-5 min)
    ↓ must pass
Full Matrix (15-30 min)
    ↓ must pass for production
Deploy
```

### Key Commands

| Command | When to Use |
|---------|-------------|
| `npm run test:smoke` | Every commit, quick sanity check |
| `npm run test:e2e` | Before push, full user flows |
| `npm run test:api` | Before push, API contracts |
| `npm run test:all` | Pre-production, full matrix |
| `npm run test:ui` | Debugging, interactive mode |
| `npm run test:debug` | Debugging, headed browser |

### Rules

1. **Smoke tests must pass** before any other tests run
2. **All tests must pass** before deployment
3. **Never skip tests** to deploy faster
4. **Write tests for bugs** before fixing them
5. **Test the contract**, not the implementation

---

**Document Version:** 1.0
**Last Updated:** 2024-12-21
**Status:** Active - Use for all testing
