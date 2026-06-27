---
name: red
description: Use for security concerns, audit requests, or when changes touch auth, input handling, or data boundaries. OWASP-informed review led by Cipher.
user-invocable: true
---

# RED -- Security Audit & Hardening

I run a security-focused audit. Cipher leads the investigation tracks, Monk fixes, I challenge severity classifications and push for HARDENED.

## My Protocol

### Step 1: I Dispatch Cipher to Define Security Tracks

Typical tracks (Cipher adapts to the project):

| Track | Focus |
|-------|-------|
| AUTH & AUTHZ | Token validation, session, admin gating, rate limiting |
| API SECURITY | Input validation, injection, CORS, error sanitization |
| DATA PROTECTION | Secrets in code, PII in logs, encryption |
| REAL-TIME | WebSocket auth, message scoping, replay prevention |
| BUSINESS LOGIC | Race condition locks, value bounds, state consistency |
| MULTI-TENANT | IDOR, membership checks, scoped queries |

I also dispatch Mack for the business logic track — his exploit-chain thinking catches what Cipher's systematic approach may miss.

### Step 2: I Review Severity Classifications

| Severity | Meaning | Action |
|----------|---------|--------|
| CRITICAL | Active exploit possible | Fix immediately |
| HIGH | Exploitable with effort | Fix this session |
| MEDIUM | Defense gap | Fix this sprint |
| LOW | Hygiene | Document for later |

I challenge: "What's the worst case if this is exploited?" I push severity UP, not down.

### Step 3: I Dispatch Monk to Fix in Priority Order

1. ALL CRITICAL — before anything else
2. ALL HIGH — next
3. MEDIUM — best-effort within session
4. LOW — documented for future

### Step 4: Verify Patches

I run a targeted GOLD sweep on fixed files via Monk to ensure patches don't introduce new issues.

### Step 5: My Verdict

| Verdict | Criteria |
|---------|----------|
| HARDENED | 0 CRITICAL, 0 HIGH, <=3 MEDIUM |
| SECURE | 0 CRITICAL, <=2 HIGH |
| EXPOSED | Any CRITICAL remaining |
| COMPROMISED | Multiple CRITICAL + exploit paths |

Max 2 passes. If CRITICAL remains after pass 2, I escalate to the human.
