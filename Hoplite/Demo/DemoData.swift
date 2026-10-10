import Foundation

enum DemoData {
    static let me = UserSummary(id: "user_demo", name: "Camden Rose")
    static let ines = UserSummary(id: "user_ines", name: "Ines Okafor")

    static let rateLimitThreadId = "thr_ratelimit"
    static let failedThreadId = "thr_sentry"
    static let checkoutThreadId = "thr_checkout"
    static let reactThreadId = "thr_react19"
    static let billingThreadId = "thr_billing"

    private static func ago(_ minutes: Double) -> String { ISO8601.string(.now.addingTimeInterval(-minutes * 60)) }

    static let projects: [Project] = [
        Project(id: "prj_storefront", name: "storefront", description: "Next.js commerce frontend", taskCode: "WEB", repos: [RepoRef(fullName: "acme/storefront", defaultBranch: "main")], defaultBranch: "main", defaultModel: "claude-fable-5", framework: "nextjs"),
        Project(id: "prj_billing", name: "billing-service", description: "Go service for plans, invoices and metering", taskCode: "BIL", repos: [RepoRef(fullName: "acme/billing", defaultBranch: "main")], defaultBranch: "main", defaultModel: "gpt-6-sol", framework: "go"),
        Project(id: "prj_ui", name: "design-system", description: "Shared React components", taskCode: "UI", repos: [RepoRef(fullName: "acme/ui", defaultBranch: "main")], defaultBranch: "main", defaultModel: "claude-sonnet-5"),
    ]

    static func pr(_ number: Int, repo: String, state: String = "open", checks: ChecksSummary, mergeable: String = "mergeable", draft: Bool = false, unresolved: Int = 0) -> PullRequest {
        PullRequest(id: "pr_\(number)", number: number, url: "https://github.com/\(repo)/pull/\(number)", repoFullName: repo, state: state, headRef: "hoplite/\(number)", headSha: "4f2a9c1e8b7d6a5f4e3d2c1b0a9f8e7d6c5b\(number)", baseRef: "main", draft: draft, githubSummary: GitHubSummary(state: state, draft: draft, mergeable: mergeable, checks: checks, unresolvedCount: unresolved))
    }

    static let threads: [AgentThread] = [
        AgentThread(id: rateLimitThreadId, projectId: "prj_storefront", modelId: "claude-fable-5", title: "Add rate limiting to the public API", status: .running, initializationState: "completed", tasks: [ThreadTask(id: "task_rl_1", identifier: "WE-212.1", title: "Audit routes that bypass the API router", status: "completed"), ThreadTask(id: "task_rl_2", identifier: "WE-212.2", title: "Load-test the limiter against staging Redis", status: "running")], createdAt: ago(18), updatedAt: ago(0.2), version: 12, archiveVersion: 0, titleVersion: 1, latestRunId: "run_rl_2", runStartedAt: ago(4), runStatus: .running, runSteerable: true, participantUserIds: ["user_demo", "user_ines"]),
        AgentThread(id: reactThreadId, projectId: "prj_storefront", modelId: "gpt-6-sol", title: "Upgrade React to 19 across the monorepo", status: .blocked, initializationState: "completed", blockedOn: ["approval"], createdAt: ago(52), updatedAt: ago(3), version: 30, archiveVersion: 0, titleVersion: 1, latestRunId: "run_r19", runStartedAt: ago(26), runStatus: .waiting, runSteerable: false, participantUserIds: ["user_demo"]),
        AgentThread(id: billingThreadId, projectId: "prj_billing", modelId: "gpt-6-sol", title: "Migrate the billing service to the new plan tiers", status: .waiting, initializationState: "completed", waitingOn: ["checks"], primaryPullRequest: pr(212, repo: "acme/billing", checks: ChecksSummary(total: 12, succeeded: 7, failing: 0, running: 5), mergeable: "unknown"), createdAt: ago(95), updatedAt: ago(6), version: 41, archiveVersion: 0, titleVersion: 1, latestRunId: "run_bill", runStatus: .completed, participantUserIds: ["user_ines", "user_demo"]),
        AgentThread(id: checkoutThreadId, projectId: "prj_storefront", modelId: "claude-fable-5", title: "Fix the flaky checkout test and open a PR", status: .ready, initializationState: "completed", primaryPullRequest: pr(184, repo: "acme/storefront", checks: ChecksSummary(total: 12, succeeded: 12, failing: 0, running: 0)), createdAt: ago(140), updatedAt: ago(22), version: 27, archiveVersion: 0, titleVersion: 1, latestRunId: "run_co", runStatus: .completed, participantUserIds: ["user_demo"]),
        AgentThread(id: failedThreadId, projectId: "prj_storefront", modelId: "claude-sonnet-5", title: "Investigate Sentry: TypeError in CartDrawer", status: .failed, initializationState: "completed", createdAt: ago(210), updatedAt: ago(48), version: 9, archiveVersion: 0, titleVersion: 1, latestRunId: "run_sentry", runStatus: .failed, createdByAutomation: true),
        AgentThread(id: "thr_e2e", projectId: "prj_ui", modelId: "claude-sonnet-5", title: "Write e2e tests for the onboarding flow", status: .queued, initializationState: "preparing", initializationPhase: "allocating_sandbox", createdAt: ago(1), updatedAt: ago(0.5), version: 2, archiveVersion: 0, titleVersion: 0),
        AgentThread(id: "thr_deps", projectId: "prj_billing", modelId: "gpt-6-luna", title: "Weekly dependency audit", status: .ready, initializationState: "completed", primaryPullRequest: pr(209, repo: "acme/billing", state: "merged", checks: ChecksSummary(total: 9, succeeded: 9, failing: 0, running: 0)), createdAt: ago(60 * 26), updatedAt: ago(60 * 20), version: 14, archiveVersion: 0, titleVersion: 1, runStatus: .completed, createdByAutomation: true),
        AgentThread(id: "thr_tokens", projectId: "prj_ui", modelId: "claude-fable-5", title: "Move color tokens to OKLCH", status: .ready, initializationState: "completed", primaryPullRequest: pr(77, repo: "acme/ui", checks: ChecksSummary(total: 6, succeeded: 5, failing: 1, running: 0), unresolved: 2), createdAt: ago(60 * 30), updatedAt: ago(60 * 27), version: 18, archiveVersion: 0, titleVersion: 1, runStatus: .completed),
        AgentThread(id: "thr_summary", projectId: "prj_storefront", modelId: "gpt-6-luna", title: "Summarize yesterday's activity", status: .ready, initializationState: "completed", createdAt: ago(60 * 40), updatedAt: ago(60 * 39), version: 4, archiveVersion: 0, titleVersion: 1, runStatus: .completed),
        AgentThread(id: "thr_old1", projectId: "prj_storefront", modelId: "claude-sonnet-5", title: "Remove the legacy coupon endpoint", status: .archived, archivedAt: ago(60 * 80), initializationState: "completed", createdAt: ago(60 * 100), updatedAt: ago(60 * 80), version: 22, archiveVersion: 1, titleVersion: 1),
        AgentThread(id: "thr_old2", projectId: "prj_billing", modelId: "gpt-6-sol", title: "Backfill invoice line item currency", status: .archived, archivedAt: ago(60 * 140), initializationState: "completed", createdAt: ago(60 * 150), updatedAt: ago(60 * 140), version: 15, archiveVersion: 1, titleVersion: 1),
    ]

    private static func user(_ thread: String, _ content: String, _ minutes: Double, author: UserSummary = me) -> Message {
        Message(id: "m_\(thread)_\(Int(minutes * 10))_u", threadId: thread, authorUserId: author.id, author: author, role: .user, kind: .chat, content: content, createdAt: ago(minutes))
    }

    private static func agent(_ thread: String, _ content: String, _ minutes: Double, run: String, kind: MessageKind = .chat) -> Message {
        Message(id: "m_\(thread)_\(Int(minutes * 10))_\(kind.rawValue)", threadId: thread, runId: run, role: .assistant, kind: kind, content: content, createdAt: ago(minutes))
    }

    private static func tool(_ thread: String, _ tool: String, _ content: String, _ minutes: Double, run: String) -> Message {
        Message(id: "m_\(thread)_\(Int(minutes * 100))_t", threadId: thread, runId: run, role: .tool, kind: .tool, content: content, createdAt: ago(minutes), toolName: tool)
    }

    static let messages: [String: [Message]] = [
        rateLimitThreadId: [
            user(rateLimitThreadId, "Add rate limiting to the public API. 600 requests per minute per key, return the standard `RateLimit` headers, and make sure the limiter is shared across instances.", 18),
            agent(rateLimitThreadId, "The public API runs on 4 instances behind the load balancer, so an in-memory counter would let each key make 4× the allowance. I'll back the limiter with the Redis instance the session store already uses.", 17.5, run: "run_rl_1", kind: .thinking),
            tool(rateLimitThreadId, "search", "Searched for `createServer` and middleware registration", 17.4, run: "run_rl_1"),
            tool(rateLimitThreadId, "read_file", "Read `src/server.ts`", 17.3, run: "run_rl_1"),
            tool(rateLimitThreadId, "read_file", "Read `src/lib/redis.ts`", 17.2, run: "run_rl_1"),
            tool(rateLimitThreadId, "edit_file", "Created `src/middleware/rate-limit.ts`", 16.5, run: "run_rl_1"),
            tool(rateLimitThreadId, "shell", "Ran `pnpm typecheck` (exit 0)", 15.8, run: "run_rl_1"),
            agent(rateLimitThreadId, "First pass is in place: a fixed-window limiter in `src/middleware/rate-limit.ts`, registered ahead of the API router.\n\n| Header | Value |\n|---|---|\n| `RateLimit` | `\"default\";r=599;t=60` |\n| `RateLimit-Policy` | `\"default\";q=600;w=60` |\n| `Retry-After` | sent with 429 |", 15.5, run: "run_rl_1"),
            user(rateLimitThreadId, "Use a sliding window instead, fixed windows let clients burst 2× at the boundary.", 5, author: ines),
        ],
        reactThreadId: [
            user(reactThreadId, "Upgrade React to 19 across the monorepo. Fix any breaking changes, keep the bundle size flat.", 52),
            tool(reactThreadId, "shell", "Ran `pnpm -r outdated react react-dom`", 50, run: "run_r19"),
            tool(reactThreadId, "edit_file", "Edited 7 `package.json` files", 44, run: "run_r19"),
            tool(reactThreadId, "edit_file", "Replaced `ReactDOM.render` in `apps/admin/src/main.tsx`", 38, run: "run_r19"),
            tool(reactThreadId, "edit_file", "Migrated 14 `forwardRef` components to ref-as-prop", 31, run: "run_r19"),
            agent(reactThreadId, "Packages are bumped and the two breaking APIs are migrated. The lockfile has conflicting peer ranges from `@acme/charts`, so I need to regenerate it with `--force` before the build will pass.", 27, run: "run_r19"),
        ],
        billingThreadId: [
            user(billingThreadId, "Migrate the billing service to the new plan tiers: Free, Plus, Pro, Scale. Existing Team customers map to Pro.", 95, author: ines),
            tool(billingThreadId, "read_file", "Read `internal/plans/catalog.go`", 93, run: "run_bill"),
            tool(billingThreadId, "edit_file", "Edited `internal/plans/catalog.go` (+86 −41)", 80, run: "run_bill"),
            tool(billingThreadId, "edit_file", "Created migration `0042_plan_tiers.sql`", 74, run: "run_bill"),
            tool(billingThreadId, "shell", "Ran `go test ./...` (exit 0)", 62, run: "run_bill"),
            tool(billingThreadId, "github", "Opened PR #212", 58, run: "run_bill"),
            agent(billingThreadId, "Opened [#212](https://github.com/acme/billing/pull/212). The migration is reversible and maps `team` → `pro` in a single transaction. Waiting on CI before I mark it ready.", 57, run: "run_bill"),
        ],
        checkoutThreadId: [
            user(checkoutThreadId, "The checkout e2e test fails about 1 in 8 runs on CI. Find the cause, fix it, and open a PR.", 140),
            agent(checkoutThreadId, "Ran the spec 40 times with tracing on. Every failure has the same shape: the Pay button is clicked while the Stripe iframe is still mounting.", 132, run: "run_co", kind: .thinking),
            tool(checkoutThreadId, "shell", "Ran `pnpm playwright test checkout --repeat-each=40`", 136, run: "run_co"),
            tool(checkoutThreadId, "read_file", "Read `e2e/checkout.spec.ts`", 131, run: "run_co"),
            tool(checkoutThreadId, "read_file", "Read `src/components/PaymentForm.tsx`", 130, run: "run_co"),
            tool(checkoutThreadId, "edit_file", "Edited `e2e/checkout.spec.ts` (+6 −2)", 126, run: "run_co"),
            tool(checkoutThreadId, "edit_file", "Edited `src/components/PaymentForm.tsx` (+3 −1)", 125, run: "run_co"),
            tool(checkoutThreadId, "shell", "Ran `pnpm playwright test checkout --repeat-each=100` (exit 0)", 118, run: "run_co"),
            tool(checkoutThreadId, "github", "Opened PR #184", 114, run: "run_co"),
            agent(checkoutThreadId, "## Root cause\nThe test clicked **Pay** as soon as the button rendered, but the Stripe Elements iframe signals readiness asynchronously. On slow CI runners the click landed before `onReady`, so the submit handler bailed out silently.\n\n## Fix\n1. `PaymentForm` keeps the button disabled until Stripe calls `onReady`\n2. The spec waits for the button to be enabled instead of a fixed `waitForTimeout(500)`\n\n```ts\nawait expect(page.getByRole('button', { name: 'Pay' })).toBeEnabled()\nawait page.getByRole('button', { name: 'Pay' }).click()\n```\n\n100/100 runs pass locally. Opened [#184](https://github.com/acme/storefront/pull/184), all 12 checks are green.", 113, run: "run_co"),
        ],
        failedThreadId: [
            Message(id: "m_sentry_auto", threadId: failedThreadId, role: .system, kind: .status, content: "Started by automation **Sentry triage** · issue STOREFRONT-2Q1", createdAt: ago(210)),
            user(failedThreadId, "Investigate `TypeError: Cannot read properties of undefined (reading 'lineItems')` in `CartDrawer`. 312 events in the last hour.", 210),
            tool(failedThreadId, "sentry", "Fetched Sentry issue STOREFRONT-2Q1 (312 events)", 208, run: "run_sentry"),
            tool(failedThreadId, "read_file", "Read `src/components/CartDrawer.tsx`", 206, run: "run_sentry"),
            tool(failedThreadId, "edit_file", "Edited `src/components/CartDrawer.tsx` (+4 −1)", 200, run: "run_sentry"),
            tool(failedThreadId, "shell", "Ran `pnpm test cart` (exit 1)", 196, run: "run_sentry"),
            agent(failedThreadId, "The guard fixes the crash, but `cart.test.tsx` asserts the old empty-state copy and the snapshot for the drawer is now stale. I couldn't get the suite green without changing product copy, so I stopped here.", 190, run: "run_sentry"),
        ],
        "thr_e2e": [user("thr_e2e", "Write Playwright e2e tests for the onboarding flow: sign up, verify email, create first project.", 1)],
        "thr_deps": [
            Message(id: "m_deps_auto", threadId: "thr_deps", role: .system, kind: .status, content: "Started by automation **Weekly dependency audit**", createdAt: ago(60 * 26)),
            agent("thr_deps", "Updated 11 patch and 3 minor dependencies. No advisories remain. Merged [#209](https://github.com/acme/billing/pull/209) after checks passed.", 60 * 20, run: "run_deps"),
        ],
        "thr_tokens": [
            user("thr_tokens", "Move our color tokens to OKLCH and keep the hex fallbacks for email templates.", 60 * 30),
            agent("thr_tokens", "Tokens are converted and the email build still emits hex. One visual regression check fails on the `Badge` story because the warning hue shifted by 2°. Review comments are open on the PR.", 60 * 27, run: "run_tok"),
        ],
        "thr_summary": [
            user("thr_summary", "Summarize yesterday's activity across the team.", 60 * 40),
            agent("thr_summary", "**Yesterday in storefront**\n\n- 9 threads finished, 6 PRs merged, 1 reverted\n- Checkout conversion fix shipped ([#181](https://github.com/acme/storefront/pull/181))\n- Ines started the billing tier migration\n- Two Sentry issues auto-triaged; one needs a product decision on empty-cart copy", 60 * 39, run: "run_sum"),
        ],
    ]

    static let activity: [String: [ActivityItem]] = [
        "run_r19": [ActivityItem(kind: "tool", id: "act_r19_force", threadId: reactThreadId, runId: "run_r19", toolCallId: "call_force", toolName: "shell", status: "waiting", createdAt: ago(26), description: "Run `pnpm install --force` to regenerate the lockfile", inputPreview: "pnpm install --force")],
    ]

    static let approvals: [String: [Approval]] = [
        reactThreadId: [Approval(id: "apr_r19", threadId: reactThreadId, runId: "run_r19", toolName: "shell", toolCallId: "call_force", requestEventId: "evt_force", actionable: true, createdAt: ago(26), summary: "Run `pnpm install --force` to regenerate the lockfile")],
    ]

    static let routesDiff = DiffFile(path: "src/app/routes.ts", state: "modified", additions: 12, deletions: 3, patch: """
    @@ -41,9 +41,18 @@ export const routes = [
       { path: '/cart', handler: cart },
       { path: '/checkout', handler: checkout },
    -  { path: '*', handler: notFound },
    -]
    -
    +  { path: '/orders/:id', handler: orderDetail },
    +  { path: '/orders', handler: orderList },
    +  { path: '*', handler: notFound },
    +]
    +
    +export function matchRoute(pathname: string) {
    +  return routes.find((route) => match(route.path, pathname))
    +}
    +
    """)

    static let diffs: [String: [DiffFile]] = [
        checkoutThreadId: [
            DiffFile(path: "e2e/checkout.spec.ts", state: "modified", additions: 6, deletions: 2, patch: """
            @@ -18,12 +18,16 @@ test.describe('checkout', () => {
               test('pays with a saved card', async ({ page }) => {
                 await page.goto('/cart')
                 await page.getByRole('link', { name: 'Checkout' }).click()
            -    await page.waitForTimeout(500)
            -    await page.getByRole('button', { name: 'Pay' }).click()
            +    const pay = page.getByRole('button', { name: 'Pay' })
            +    await expect(pay).toBeEnabled({ timeout: 15_000 })
            +    await pay.click()
            +
            +    await expect(page).toHaveURL(/\\/orders\\/[a-z0-9]+/)
            +    await expect(page.getByText('Payment received')).toBeVisible()
               })
            """),
            DiffFile(path: "src/components/PaymentForm.tsx", state: "modified", additions: 3, deletions: 1, patch: """
            @@ -27,7 +27,9 @@ export function PaymentForm({ onPaid }: Props) {
               const stripe = useStripe()
               const elements = useElements()
            -  const disabled = !stripe || submitting
            +  const [ready, setReady] = useState(false)
            +  const disabled = !stripe || !ready || submitting
            +
               return (
                 <form onSubmit={handleSubmit}>
            -      <PaymentElement />
            +      <PaymentElement onReady={() => setReady(true)} />
            """),
        ],
        rateLimitThreadId: [
            DiffFile(path: "src/middleware/rate-limit.ts", state: "added", additions: 64, deletions: 0, patch: """
            @@ -0,0 +1,24 @@
            +import type { Request, Response, NextFunction } from 'express'
            +import { redis } from '../lib/redis'
            +
            +const WINDOW_MS = 60_000
            +const LIMIT = 600
            +
            +export async function rateLimit(req: Request, res: Response, next: NextFunction) {
            +  const key = `rl:${req.apiKey.id}`
            +  const now = Date.now()
            +  const [, , count] = await redis
            +    .multi()
            +    .zremrangebyscore(key, 0, now - WINDOW_MS)
            +    .zadd(key, now, `${now}:${Math.random()}`)
            +    .zcard(key)
            +    .pexpire(key, WINDOW_MS)
            +    .exec()
            +
            +  const remaining = Math.max(0, LIMIT - Number(count))
            +  res.setHeader('RateLimit', `"default";r=${remaining};t=60`)
            +  res.setHeader('RateLimit-Policy', `"default";q=${LIMIT};w=60`)
            +  if (remaining === 0) return res.status(429).set('Retry-After', '60').json({ ok: false, error: 'rate_limited' })
            +  next()
            +}
            """),
            DiffFile(path: "src/server.ts", state: "modified", additions: 2, deletions: 0, patch: """
            @@ -12,6 +12,8 @@ const app = express()
             app.use(express.json())
             app.use(authenticate)
            +app.use('/api', rateLimit)
            +
             app.use('/api', router)
            """),
            DiffFile(path: "src/middleware/rate-limit.test.ts", state: "added", additions: 88, deletions: 0, patch: "@@ -0,0 +1,3 @@\n+import { describe, it, expect } from 'vitest'\n+import { rateLimit } from './rate-limit'\n+// 14 cases covering window rollover, headers and 429s"),
        ],
        billingThreadId: [
            DiffFile(path: "internal/plans/catalog.go", state: "modified", additions: 86, deletions: 41, patch: """
            @@ -8,14 +8,22 @@ package plans
             type Tier string
             
             const (
            -	TierFree Tier = "free"
            -	TierTeam Tier = "team"
            +	TierFree  Tier = "free"
            +	TierPlus  Tier = "plus"
            +	TierPro   Tier = "pro"
            +	TierScale Tier = "scale"
             )
            +
            +// Legacy maps retired tiers onto the current catalog.
            +var Legacy = map[string]Tier{"team": TierPro}
            """),
            DiffFile(path: "migrations/0042_plan_tiers.sql", state: "added", additions: 18, deletions: 0, patch: "@@ -0,0 +1,4 @@\n+BEGIN;\n+UPDATE subscriptions SET tier = 'pro' WHERE tier = 'team';\n+ALTER TYPE plan_tier ADD VALUE IF NOT EXISTS 'scale';\n+COMMIT;"),
            DiffFile(path: "internal/plans/legacy_team.go", previousPath: "internal/plans/team.go", state: "renamed", additions: 2, deletions: 2, patch: "@@ -1,3 +1,3 @@\n-// Package plans: team tier helpers.\n+// Package plans: helpers kept for migrated Team customers.\n package plans"),
            DiffFile(path: "internal/plans/team_seats.go", state: "deleted", additions: 0, deletions: 37, patch: "@@ -1,37 +0,0 @@\n-package plans\n-\n-func teamSeatLimit() int { return 10 }"),
        ],
        failedThreadId: [
            DiffFile(path: "src/components/CartDrawer.tsx", state: "modified", additions: 4, deletions: 1, patch: "@@ -54,7 +54,10 @@ export function CartDrawer() {\n   const { cart } = useCart()\n-  const items = cart.lineItems\n+  if (!cart) {\n+    return <EmptyCart />\n+  }\n+  const items = cart.lineItems\n   return (\n"),
        ],
    ]

    static func checks(running: Int, total: Int, failing: Int = 0) -> [PRCheck] {
        let names = ["build", "lint", "typecheck", "unit (node 22)", "unit (node 24)", "e2e · chromium", "e2e · webkit", "e2e · firefox", "migrations", "storybook", "vercel preview", "codeql"]
        return names.prefix(total).enumerated().map { index, name in
            let isRunning = index >= total - running
            let isFailing = !isRunning && index >= total - running - failing
            return PRCheck(name: name, status: isRunning ? "in_progress" : "completed", conclusion: isRunning ? nil : (isFailing ? "failure" : "success"), startedAt: ago(Double(20 - index)), completedAt: isRunning ? nil : ago(Double(12 - index / 2)), url: "https://github.com")
        }
    }

    static let reviewLoops: [String: ReviewLoop] = [
        billingThreadId: ReviewLoop(id: "rl_billing", pullRequestId: "pr_212", enabled: true, autoMerge: false, status: "waiting_checks", passCount: 2, lastObservedAt: ago(4)),
    ]

    static let reviewThreads: [String: [ReviewThread]] = [
        billingThreadId: [
            ReviewThread(id: "rt_1", path: "db/migrations/0042_plan_tiers.sql", line: 18, isResolved: false, isOutdated: false, comments: [
                ReviewComment(id: "rc_1", authorLogin: "ines-okafor", body: "Can we backfill `plan_tier` in batches? This table has ~4M rows in prod and a single UPDATE will hold the lock for a while.", createdAt: ago(38)),
                ReviewComment(id: "rc_2", authorLogin: "hoplite[bot]", body: "Good call. I'll switch to a batched backfill of 10k rows per transaction and add a progress log.", createdAt: ago(30)),
            ]),
            ReviewThread(id: "rt_2", path: "src/billing/plans.ts", line: 64, isResolved: false, isOutdated: false, comments: [
                ReviewComment(id: "rc_3", authorLogin: "ryan", body: "Scale should keep the custom SSO entitlement from Enterprise.", createdAt: ago(26)),
            ]),
            ReviewThread(id: "rt_3", path: "src/billing/plans.ts", line: 12, isResolved: true, isOutdated: true, comments: [
                ReviewComment(id: "rc_4", authorLogin: "ines-okafor", body: "Nit: export the tier list as a const tuple so the union type is derived from it.", createdAt: ago(55)),
            ]),
        ],
    ]

    static let pullRequests: [String: PullRequestStatus] = [
        checkoutThreadId: PullRequestStatus(number: 184, url: "https://github.com/acme/storefront/pull/184", repoFullName: "acme/storefront", title: "Fix flaky checkout e2e by waiting for Stripe readiness", body: "The Pay button is now disabled until Stripe Elements reports ready, and the spec waits for it to be enabled instead of sleeping.", state: "open", draft: false, mergeable: "mergeable", checks: checks(running: 0, total: 12), additions: 9, deletions: 3, changedFiles: 2, aheadBy: 1, behindBy: 0, baseRef: "main", headRef: "hoplite/fix-flaky-checkout", headSha: "4f2a9c1e8b7d6a5f4e3d2c1b0a9f8e7d6c5b4a39", allowedMergeMethods: ["squash", "merge", "rebase"]),
        billingThreadId: PullRequestStatus(number: 212, url: "https://github.com/acme/billing/pull/212", repoFullName: "acme/billing", title: "Migrate to Free / Plus / Pro / Scale plan tiers", body: "Maps Team → Pro in a reversible migration.", state: "open", draft: false, mergeable: "unknown", checks: checks(running: 5, total: 12), additions: 106, deletions: 80, changedFiles: 4, aheadBy: 3, behindBy: 2, baseRef: "main", headRef: "hoplite/plan-tiers", headSha: "8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b", allowedMergeMethods: ["squash"]),
        "thr_tokens": PullRequestStatus(number: 77, url: "https://github.com/acme/ui/pull/77", repoFullName: "acme/ui", title: "Color tokens in OKLCH with hex fallbacks", state: "open", draft: false, mergeable: "mergeable", checks: checks(running: 0, total: 6, failing: 1), additions: 312, deletions: 298, changedFiles: 21, baseRef: "main", headRef: "hoplite/oklch", headSha: "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b", allowedMergeMethods: ["squash", "merge"]),
        "thr_deps": PullRequestStatus(number: 209, url: "https://github.com/acme/billing/pull/209", repoFullName: "acme/billing", title: "chore(deps): weekly dependency updates", state: "merged", mergeable: "mergeable", checks: checks(running: 0, total: 9), additions: 44, deletions: 44, changedFiles: 2, baseRef: "main", headRef: "hoplite/deps-week-41", headSha: "0f9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a2f1e"),
    ]

    static let catalog = ModelCatalog(
        models: [
            ModelInfo(id: "claude-fable-5", name: "Fable 5", provider: "anthropic", capabilities: .init(contextWindowTokens: 1_000_000, reasoningLevels: ["low", "medium", "high", "max"], supportsFast: false, supportsImages: true)),
            ModelInfo(id: "claude-sonnet-5", name: "Sonnet 5", provider: "anthropic", capabilities: .init(contextWindowTokens: 400_000, reasoningLevels: ["low", "medium", "high"], supportsFast: false, supportsImages: true)),
            ModelInfo(id: "gpt-6-sol", name: "GPT-6 Sol", provider: "openai", capabilities: .init(contextWindowTokens: 400_000, reasoningLevels: ["low", "medium", "high", "xhigh"], supportsFast: true, supportsImages: true)),
            ModelInfo(id: "gpt-6-luna", name: "GPT-6 Luna", provider: "openai", capabilities: .init(contextWindowTokens: 400_000, reasoningLevels: ["none", "low", "medium", "high"], supportsFast: true, supportsImages: true)),
            ModelInfo(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash", provider: "google", capabilities: .init(contextWindowTokens: 1_000_000, reasoningLevels: ["low", "medium", "high"], supportsFast: false, supportsImages: true)),
            ModelInfo(id: "grok-4.7", name: "Grok 4.7", provider: "xai", capabilities: .init(contextWindowTokens: 256_000, reasoningLevels: ["low", "high"], supportsFast: true, supportsImages: false)),
        ],
        runConfig: .init(defaultModelId: "claude-fable-5", defaultReasoning: "high", reasoningOptions: ["none", "low", "medium", "high", "xhigh", "max"])
    )

    static let automations: [Automation] = [
        Automation(id: "aut_sentry", projectId: "prj_storefront", name: "Sentry triage", enabled: true, triggerKind: "webhook", eventKind: "sentry.issue.created", prompt: "Investigate the new Sentry issue, reproduce it, and open a fix PR if the cause is clear.", title: "Sentry triage", repoFullName: "acme/storefront", modelId: "claude-sonnet-5", lastRunAt: ago(210)),
        Automation(id: "aut_flaky", projectId: "prj_storefront", name: "Nightly flaky test sweep", enabled: true, triggerKind: "schedule", schedule: AutomationSchedule(mode: "cron", expression: "0 3 * * *", timezone: "America/New_York"), prompt: "Run the e2e suite 20 times, find flaky specs, and fix the most frequent one.", repoFullName: "acme/storefront", modelId: "claude-fable-5", nextRunAt: ISO8601.string(.now.addingTimeInterval(3600 * 9)), lastRunAt: ago(60 * 15)),
        Automation(id: "aut_pr_review", projectId: "prj_storefront", name: "Review every new PR", enabled: false, triggerKind: "webhook", eventKind: "github.pull_request.opened", prompt: "Review the pull request for correctness and security issues; leave inline comments.", repoFullName: "acme/storefront", modelId: "gpt-6-sol", lastRunAt: ago(60 * 72)),
        Automation(id: "aut_deps", projectId: "prj_billing", name: "Weekly dependency audit", enabled: true, triggerKind: "schedule", schedule: AutomationSchedule(mode: "cron", expression: "0 9 * * 1", timezone: "America/New_York"), prompt: "Update patch and minor dependencies, run tests, and open a PR.", repoFullName: "acme/billing", modelId: "gpt-6-luna", nextRunAt: ISO8601.string(.now.addingTimeInterval(86_400 * 3)), lastRunAt: ago(60 * 26)),
        Automation(id: "aut_linear", projectId: "prj_ui", name: "Linear: label → agent", enabled: true, triggerKind: "webhook", eventKind: "linear.issue.labeled", prompt: "When an issue is labeled `agent`, implement it and link the PR back to Linear.", repoFullName: "acme/ui", modelId: "claude-fable-5", lastRunAt: ago(60 * 5)),
    ]

    static func executions(automationId: String, projectId: String) -> [AutomationExecution] {
        let statuses = ["completed", "completed", "failed", "completed", "completed", "completed"]
        return statuses.enumerated().map { index, status in
            AutomationExecution(id: "exe_\(automationId)_\(index)", automationId: automationId, projectId: projectId, triggerKind: "schedule", status: status, threadId: index == 0 ? (automationId == "aut_sentry" ? failedThreadId : "thr_deps") : nil, threadTitle: index == 0 ? "Latest run" : "Run \(statuses.count - index)", error: status == "failed" ? "Tests failed after 3 repair attempts" : nil, createdAt: ago(Double(60 * 24 * index + 30)), runStatus: status, runDurationMs: 180_000 + index * 41_000)
        }
    }

    static func title(for prompt: String) -> String {
        let firstLine = prompt.split(separator: "\n").first.map(String.init) ?? prompt
        let words = firstLine.split(separator: " ").prefix(9).joined(separator: " ")
        return words.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:")).capitalizedFirst
    }
}
