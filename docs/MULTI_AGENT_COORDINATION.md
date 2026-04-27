---
description: Deep guide on multi-agent coordination for complex architectural decisions
---

# Multi-Agent Coordination Guide

## Part 1: Philosophy & Decision Complexity

### The Problem with Single-Agent Exploration

When one AI agent explores a decision, it faces inherent biases:

1. **Anchoring bias** — First idea becomes the reference point; later ideas compared unfavorably
2. **Confirmation bias** — Searches for evidence supporting initial direction
3. **Context limits** — Can't deeply explore 3+ alternatives simultaneously
4. **Expertise tunnel** — Agent explores from one lens, misses multi-disciplinary insights

### The Multi-Agent Solution

Launch multiple agents **in parallel**, each exploring one approach independently:

- **Independent perspectives** — Each agent starts fresh, no bias from others
- **Explicit tradeoffs** — Each approach articulates its weaknesses honestly
- **Parallel thinking** — 3 agents thinking for 2 hours = 6 hours of exploration in 2 hours
- **Prevents premature convergence** — Avoids settling on suboptimal solution early

### Decision Complexity Matrix

```
                Low Impact              Medium Impact              High Impact
              (days matter)           (weeks matter)            (months matter)

Simple         Single Agent             Single Agent              Single Agent
Choice         ❌ Overkill              ⚠️ Use /plan               ⚠️ Maybe multi

Complex        Single Agent             ✅ MULTI-AGENT             ✅ MULTI-AGENT
Choice         (unnecessary)            (RECOMMENDED)             (ESSENTIAL)

Examples:
- "Framework: React vs. Vue?" → Medium + Simple = Single Agent (/plan)
- "DB: PostgreSQL vs. MongoDB?" → Medium + Complex = Multi-Agent
- "Monorepo vs. multi-repo?" → High + Complex = Multi-Agent (affects 3 years)
```

---

## Part 2: Taxonomy of Multi-Agent Patterns

### Pattern A: Expertise-Based Division

Each agent represents a specialized role:

**Scenario:** Should we migrate to Kubernetes?

- **Agent 1 (DevOps)** — Infrastructure complexity, operational burden, HA strategy
- **Agent 2 (Architect)** — Scalability patterns, service mesh considerations, API impact
- **Agent 3 (Finance)** — Cost analysis, resource utilization, ROI, long-term economics
- **Synthesis** — Balance all three perspectives

**Best for:** Cross-functional decisions where roles have legitimate expertise gaps.

### Pattern B: Approach-Based Division

Each agent explores one concrete option deeply:

**Scenario:** REST vs. GraphQL vs. gRPC

- **Agent 1** — REST architecture (simplicity, ecosystem, tradeoffs)
- **Agent 2** — GraphQL architecture (query flexibility, N+1 problems, caching)
- **Agent 3** — gRPC architecture (performance, type safety, browser support)
- **Synthesis** — Comparison and recommendation

**Best for:** Technology choices where each option has distinct characteristics.

### Pattern C: Risk/Constraint-Based Division

Each agent stress-tests from a different angle:

**Scenario:** Can we migrate to serverless?

- **Agent 1 (Ops risk)** — Cold start latency, state management, monitoring complexity
- **Agent 2 (Cost risk)** — Pricing models, over-provisioning, data egress costs
- **Agent 3 (Dev risk)** — Local testing, debugging, vendor lock-in, team skills
- **Synthesis** — Risk matrix and go/no-go recommendation

**Best for:** Significant architectural changes with multiple failure modes.

---

## Part 3: Full Workflow

### Phase 1: Problem Articulation

**Input:** Collect information needed for clear briefing.

```
Decision: Monorepo vs. multi-repo for 50-engineer organization

Constraints (Hard Limits):
- 50 engineers across 5 teams
- 200+ services expected at scale
- Shared libraries must not break consumers
- CI/CD pipeline must stay < 10 min per commit
- Initial migration must complete in 4 weeks

Success Criteria:
- Teams work independently without blocking
- Dependency conflicts rare (< 1 per week)
- New engineer onboarding < 2 hours
- Code reuse across teams > 30%

Timeline:
- 2 weeks to decide
- 4 weeks to pilot
- 3 months to full rollout

Stakes:
- Architectural foundation for next 3 years
- Hard/expensive to reverse midstream
- Affects daily workflow for every engineer
```

### Phase 2: Approach Definition

List 2-4 concrete approaches (not abstract discussion):

```
1. **Monorepo (Nx/Turborepo)**
   - Single git repo, shared tooling
   - Coordinated releases, implicit coupling
   - Examples: Google, Meta, Airbnb

2. **Multi-Repo (npm packages)**
   - Decoupled repos, explicit versioning
   - More overhead, full team autonomy
   - Examples: Vercel, Shopify, Stripe

3. **Hybrid (Monorepo + federated packages)**
   - Monorepo for core, publish stable as npm
   - Best of both, most complex setup
   - Examples: Some Meta teams, Nx Cloud
```

### Phase 3: Agent Briefing

Create a briefing for each agent. Template:

```
# Agent Briefing: Approach X

## Context
[Decision question, constraints, success criteria, timeline]

## Your Scope
Explore this approach in depth:
1. Architecture and file structure
2. How it handles each constraint
3. Team impact (learning curve, autonomy, collaboration)
4. Implementation path and timeline
5. 3-5 honest pros
6. 3-5 honest cons
7. Risks specific to this approach (and mitigations)
8. Is this recommended for our 50-engineer org?

## Your Assumption
Assume we WILL choose this approach. What does success look like? What breaks?

## Deliverable
Structure output as below (5,000 words max):
- Executive summary
- Architecture overview
- Constraint satisfaction matrix
- Strengths & weaknesses
- Team impact
- Implementation roadmap
- Risks & mitigations
- Recommendation for our org

## Important
- Focus: Make the strongest case for YOUR approach AND articulate weaknesses honestly
- You are NOT comparing to alternatives (synthesis agent does that)
- You are NOT recommending overall (synthesis agent decides)
- Think independently; don't reference other agents' work
```

### Phase 4: Parallel Execution

**All agents start simultaneously** (key to avoiding sequential bias):

```
Time:
T+0:00   Agent 1 starts (Monorepo deep-dive)
T+0:00   Agent 2 starts (Multi-repo deep-dive)
T+0:00   Agent 3 starts (Hybrid deep-dive)

T+2:30   Agent 1 completes, waits
T+2:45   Agent 2 completes, waits
T+3:15   Agent 3 completes

T+3:15   Synthesis agent launches (reads all three reports)
T+5:30   Synthesis complete
```

### Phase 5: Synthesis & Decision

**Input:** All three exploration reports.

**Synthesis agent tasks:**

```
1. Build comparison matrix (approach × criterion)
   | Criterion | Monorepo | Multi-Repo | Hybrid |
   |-----------|----------|-----------|--------|
   | Autonomy | 6/10 | 9/10 | 8/10 |
   | Scalability | 7/10 | 8/10 | 9/10 |
   | Tooling overhead | 7/10 | 5/10 | 4/10 |
   | Release coordination | 8/10 | 3/10 | 6/10 |

2. Identify decision drivers
   "For your team of 50 engineers, two factors dominate:
   - Team autonomy (Multi-repo wins)
   - Shared code simplicity (Monorepo wins)"

3. Risk assessment per approach
   | Approach | Risk | Likelihood | Impact | Mitigation |
   |----------|------|-----------|--------|-----------|

4. Recommendation with rationale
   "RECOMMEND: Hybrid approach.
   Rationale: Captures monorepo benefits (fast refactoring, shared tooling) 
   while preventing multi-repo fragmentation. Scales to public/partner 
   integrations later via npm publication."

5. Next steps
   - Week 1-2: Set up Nx monorepo
   - Week 3-4: Migrate 10 services
   - Gather feedback, adjust if needed
```

**Output Example:**

```
# Monorepo vs. Multi-Repo Decision

## Recommendation: Hybrid Approach

### Rationale
- Captures monorepo benefits (coordinated releases, shared refactoring)
- Prevents multi-repo fragmentation (single source of truth for core)
- Scales to partnerships/public API via npm publication
- Acceptable learning curve (teams familiar with both patterns)

### Comparison Matrix
| Criterion | Monorepo | Multi-Repo | Hybrid |
|-----------|----------|-----------|--------|
| Team Autonomy | 6/10 | 9/10 | 8/10 |
| Scalability | 7/10 | 8/10 | 9/10 |
| Onboarding | 7/10 | 6/10 | 6/10 |
| Shared Code | 9/10 | 5/10 | 8/10 |
| Complexity | 5/10 | 8/10 | 4/10 |

### Risk Matrix
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Over-coupling | Medium | High | Enforce boundaries with linting |
| Release chaos | Low | High | Automated versioning (changesets) |
| Onboarding friction | Medium | Medium | Better docs + templates |

### Implementation Roadmap
- **Week 1-2:** Set up Nx, monorepo structure
- **Week 3-4:** Migrate 10 services from multi-repo
- **Week 5:** Publish 2 stable packages to npm
- **Month 2-3:** Full migration, gather feedback
```

---

## Part 4: Structured Output Format

Each agent delivers in this format (ensures comparability):

```markdown
# Approach: {Name}

## Executive Summary
[1-2 sentence overview of approach and key finding]

## Architecture Overview
[Diagram or prose description of how this works]

## Constraint Satisfaction

| Constraint | Status | Notes |
|-----------|--------|-------|
| 50 engineers | ✅ Good | Clear team boundaries |
| 200+ services | ⚠️ Tricky | Needs careful versioning |
| Shared libs | ✅ Strong | Implicit deps handled well |
| < 10min CI | ❌ Risk | Monorepo builds slow at scale |

## Strengths (3-5)

1. **[Strength 1]** — [Why this matters, with evidence]
   - Example: "Coordinated releases prevent version skew"
   
2. **[Strength 2]** — [Why this matters]

3. **[Strength 3]** — [Why this matters]

## Weaknesses (3-5)

1. **[Weakness 1]** — [Why this is a real problem]
   - Example: "Teams tightly coupled; one team's refactor can block others"
   
2. **[Weakness 2]** — [Why this is a real problem]

3. **[Weakness 3]** — [Why this is a real problem]

## Team Impact

- **Learning Curve:** 2-4 weeks for new engineer to become productive
- **Debugging Difficulty:** Moderate (implicit deps harder to trace)
- **Day-to-day Friction:** Low once systems are in place
- **Cross-team Collaboration:** Strong (shared code easy to change)

## Implementation Complexity

| Phase | Effort | Duration | Notes |
|-------|--------|----------|-------|
| Infrastructure setup | 200 hours | 2 weeks | Nx setup, CI/CD config |
| Service migration | 400 hours | 4 weeks | Gradual, 50 services |
| Testing & validation | 150 hours | 2 weeks | Ensure no regressions |

**Total:** 750 hours (~1.5 months for 50-engineer org)

## Risks & Mitigations

1. **Risk: Build performance degrades at scale**
   - Likelihood: Medium | Impact: High
   - Mitigation: Implement incremental builds, caching, sharding

2. **Risk: Implicit coupling causes subtle bugs**
   - Likelihood: Low | Impact: High
   - Mitigation: Strong linting, boundary testing

3. **Risk: Release coordination becomes bottleneck**
   - Likelihood: Medium | Impact: Medium
   - Mitigation: Automated changesets, semantic versioning

## Recommendation for This Organization

**Recommend THIS approach if:**
- You value coordinated releases and implicit code sharing
- Your teams are moderately coupled
- You can invest in monorepo tooling upfront

**This approach breaks if:**
- Teams need full autonomy (go multi-repo instead)
- You can't invest in infrastructure (go multi-repo)
- Services are completely independent (go multi-repo)

**Success looks like:**
- Teams refactoring across repos without coordination
- Shared library updates in one commit
- No versioning skew or "works locally" bugs
```

---

## Part 5: Gotchas & Anti-Patterns

### ❌ Don't: Let agents debate

**Bad:**
```
Agent 1: "Monorepo is better because X"
Agent 2: "No, multi-repo is better because Y"
→ Agents feel forced to advocate; lose objectivity
```

**Good:**
```
Agent 1: "Here's monorepo: strengths A, B, C. Weaknesses X, Y, Z."
Agent 2: "Here's multi-repo: strengths D, E, F. Weaknesses M, N, O."
Synthesis: "Comparing these, I recommend..."
→ Agents explore; synthesis decides
```

### ❌ Don't: Ask agents to compare alternatives

**Bad:**
```
"Compare monorepo vs. multi-repo and recommend"
→ Agents feel forced to advocate their assigned approach
```

**Good:**
```
"Explore monorepo. What does it do well? What's hard? What breaks?"
→ Agents explore honestly; synthesis compares
```

### ❌ Don't: Run agents sequentially

**Bad:**
```
1. Agent 1 explores (2 hours)
2. Wait for report
3. Agent 2 explores, now biased by Agent 1's work
→ Agent 2 subconsciously reacts to Agent 1
```

**Good:**
```
1. All agents start simultaneously
2. No cross-pollination until synthesis
→ Independent analyses
```

### ✅ Do: Isolate agent contexts

```
Agent briefing should be:
- Self-contained (doesn't reference other agents)
- Focused scope (not "compare everything")
- Same format as others (ensures comparability)
- Clear deliverable (what output do we need?)
```

### ✅ Do: Use synthesis agent, not human vote

**Don't:**
```
"Read three agent reports and pick the best"
→ Requires subjective judgment
```

**Do:**
```
"Synthesis agent: Score each approach on criteria X, Y, Z. Recommend one."
→ Systematic aggregation
```

---

## Part 6: Cost & Time Estimate

### When Is Multi-Agent Worth It?

**Rule of thumb:**
- Cost of wrong decision > Cost of multi-agent exploration = Worth it

```
Decision | Cost of Wrong | Impact Duration | Worth Multi-Agent? |
----------|--------------|-----------------|-------------------|
"npm: lodash vs underscore?" | Low | 1 month | ❌ No |
"DB: PostgreSQL vs MongoDB?" | Very High | 2 years | ✅ Yes |
"Monorepo vs multi-repo?" | Extreme | 3 years | ✅ Yes |
"Auth: build vs. Auth0?" | High | 1+ years | ✅ Yes |
"Framework: React vs Vue?" | Medium | 6+ months | ⚠️ Maybe |
```

### Time Budget

```
Single-agent /plan:
  Problem articulation: 30 min
  Agent exploration: 2-3 hours
  Review + decide: 1 hour
  ─────────────────────
  Total: 3.5-4 hours

Multi-agent parallel:
  Problem articulation: 1 hour (more detail)
  Briefing prep: 1 hour (3 scopes)
  Agent 1: 2-3 hours (parallel)
  Agent 2: 2-3 hours (parallel)
  Agent 3: 2-3 hours (parallel)
  Synthesis: 2-3 hours
  Review + decide: 1 hour
  ─────────────────────
  Total: 8-10 hours (3 agents parallel = +5 hours vs single)

ROI:
  +5 hours of thinking
  If decision affects team for 1+ years = strong ROI
  If decision is reversible = lower ROI
```

---

## Part 7: Integration with Claude Code

### Workflow

1. **Detect:** Claude notices a complex architectural decision
   - Auto-trigger rule in GLOBAL_RULES.md
   - Claude suggests: "Want to use /parallel-design-agents?"

2. **Clarify (optional):** User can run `/plan` first
   - Clarifies the decision
   - Explores if multi-agent is needed
   - Surfaces constraints

3. **Launch:** User runs `/parallel-design-agents`
   - User articulates decision, approaches, constraints
   - Creates 3 agent briefings
   - Launches agents in parallel

4. **Wait:** Agents explore independently (2-3 hours)
   - No cross-pollination
   - Parallel execution

5. **Synthesize:** Synthesis agent compares and recommends
   - Reads all three reports
   - Builds comparison matrix
   - Recommends approach with rationale

6. **Validate (optional):** User can run `/grill-me`
   - Pressure-test the chosen approach
   - Surface hidden assumptions

---

## Part 8: Real-World Example

### Scenario: REST vs. GraphQL Decision

**Context:**
```
Team: 5 backend engineers
Users: 1000 concurrent, growing to 10,000
Requirement: Real-time mobile updates
Timeline: 6-week MVP, 2-week decision
```

**Agents:**

**Agent A (REST):**
```
Deep dive on REST architecture with polling.

Scope:
- Polling strategy at 1000+ concurrent users
- Pagination patterns
- Real-time latency impact
- Scalability to 10x

Deliverable: Structured output
```

**Agent B (GraphQL):**
```
Deep dive on GraphQL + subscriptions.

Scope:
- Query language design
- Real-time subscriptions (replace polling)
- N+1 query problem at scale
- Caching strategies

Deliverable: Structured output
```

**Agent C (gRPC):**
```
Deep dive on gRPC + streaming.

Scope:
- Binary protocol benefits
- Bidirectional streaming
- Browser support challenges
- Team learning curve

Deliverable: Structured output
```

**Synthesis Output:**

```
# API Architecture Recommendation

## Recommendation: GraphQL + Subscriptions

### Rationale
- Native real-time (subscriptions, not polling overhead)
- Single query language reduces API fragmentation
- Team has some GraphQL experience
- Scales to 10x users with proper caching

### Comparison
| Aspect | REST | GraphQL | gRPC |
|--------|------|---------|------|
| Real-time | 5/10 | 9/10 | 9/10 |
| Team velocity | 9/10 | 7/10 | 4/10 |
| Debugging | 8/10 | 6/10 | 5/10 |
| Scalability | 7/10 | 8/10 | 9/10 |

### Next Steps
1. Prototype GraphQL API (1 week)
2. Benchmark against REST polling
3. If latency acceptable, full implementation
4. Revisit in 3 months for performance review
```

---

## Part 9: Checklist Before Launch

- [ ] Decision is well-articulated (not vague)
- [ ] 2-3 viable approaches identified (not obvious winner)
- [ ] Constraints clearly listed (latency, cost, team, timeline)
- [ ] Success criteria defined (measurable)
- [ ] Agent briefings written with clear scopes
- [ ] All briefings use same template/format
- [ ] Synthesis scope defined (how to aggregate)
- [ ] Timeline allows 6-8 hours (parallel agents)
- [ ] Stakeholders agree to follow recommendation
- [ ] Someone will own implementation (clear ownership)

---

## Summary

**Multi-agent coordination excels when:**
- Decision is complex (3+ variables)
- Options are legitimate (no obvious winner)
- Impact is significant (affects team > 6 months)
- Cost of wrong choice is high (years of regret)

**Use this guide to:**
1. Recognize when multi-agent helps
2. Structure agent briefings for honesty
3. Parallelize exploration (the real win)
4. Synthesize recommendations systematically
5. Build institutional knowledge

**Next time you face "Should we use X or Y?" — ask:**
- "Is this decision worth 6-8 hours of multi-agent thinking?"
- "What's the cost of getting it wrong?"
- "How long will this decision affect us?"

If the answers are "yes, high, and > 1 year" → Multi-agent coordination is your tool.
