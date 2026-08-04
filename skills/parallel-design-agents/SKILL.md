---
name: parallel-design-agents
description: Coordinate multiple agents to explore different architectural approaches in parallel, then synthesize recommendations
---

# Parallel Design Agents Workflow

## When to Use This Skill

Trigger when facing a **complex architectural decision** with:
- 2-3+ viable approaches (not an obvious winner)
- High impact (affects team/product > 3 months)
- Legitimate tradeoffs (performance vs. simplicity, cost vs. control, etc.)

**Examples:**
- "REST vs. GraphQL vs. gRPC for our API?"
- "Monorepo vs. multi-repo for 5 teams?"
- "Build custom auth vs. Auth0 vs. Cognito?"
- "Migrate to serverless vs. optimize current setup?"
- "In-house queue vs. SQS vs. Kafka?"

**NOT for:**
- Simple factual lookup ("What's Node.js LTS?")
- Debugging (single investigation path)
- Code review (doesn't need multiple perspectives)

---

## Quick Start: 5 Steps

### Step 1: Articulate the Decision

Define **what, constraints, criteria, and timeline:**

```
Decision: API architecture for new mobile platform

Constraints:
- 1000 concurrent users, <100ms latency
- 5-person backend team
- Must support real-time updates

Success Criteria:
- Easy to debug and maintain
- Scales to 10x users without architecture change
- Team can ship MVP in 6 weeks

Timeline: 2 weeks to decide, 6 weeks to implement
```

### Step 2: List Approaches to Explore

2-3 concrete options (not abstract discussion):

```
1. REST + Polling
   - Traditional JSON API
   - Client polls for updates
   
2. GraphQL + Subscriptions
   - Single query language
   - Real-time via subscriptions
   
3. gRPC + Streaming
   - Binary protocol
   - Bidirectional streaming
```

### Step 3: Create Agent Briefing (Use Template Below)

For each approach, write a **focused agent task**. Example:

```
## Agent Briefing: REST + Polling Approach

You are a backend architect evaluating REST + polling for our mobile API.

**Context:**
- 1000 concurrent users, <100ms latency
- 5-person team, 6-week MVP timeline
- Must scale to 10x without redesign

**Your Scope:**
Explore REST + polling in depth:
1. Architecture overview (how does polling work at scale?)
2. How it handles constraints (latency, scalability, real-time requirements)
3. Team impact (learning curve, debugging)
4. Implementation complexity (estimated dev time, testing)
5. Honest pros and cons (3-5 each)
6. Risks specific to this approach (and mitigation)
7. Is this approach recommended for our project? Why or why not?

**Your Assumption:**
Assume we WILL choose REST + polling. What does success look like? What breaks?

**Deliverable Format:**
Use the structured output format (see Part 3 of MULTI_AGENT_COORDINATION.md).

**Constraints:**
- Focus: Make the strongest case for REST + polling AND articulate its weaknesses honestly
- Do NOT compare to alternatives (Agent B and C handle that)
- Length: 2000-3000 words (comprehensive but bounded)
```

Create 3 similar briefings, one per approach.

### Step 4: Launch Agents in Parallel

**All agents start simultaneously** (this is the key to avoiding sequential bias):

```
Instruction to Claude Code:

"Launch 3 agents in parallel to explore:
- Agent A: REST + polling deep-dive (use briefing A above)
- Agent B: GraphQL + subscriptions deep-dive (use briefing B above)
- Agent C: gRPC + streaming deep-dive (use briefing C above)

Each agent works independently for ~2-3 hours.
No cross-communication until synthesis.

Once all complete, proceed to Step 5."
```

### Step 5: Synthesis & Decision

**After all agents complete**, create synthesis task:

```
## Synthesis Task

Input: Three agent reports on REST vs. GraphQL vs. gRPC approaches.

Your Job: Compare and recommend.

Deliverable:
1. Comparison matrix (approach × criterion: latency, scalability, team velocity, etc.)
2. Risk matrix (likelihood × impact for each approach)
3. Team readiness assessment (learning curve, confidence)
4. Final recommendation with rationale
5. Implementation roadmap (phases, timeline, effort)
6. Next steps (how to validate, pilot, scale)
```

**Output Example:**

```
# Decision: API Architecture

## Recommendation: GraphQL + Subscriptions

### Rationale
- Native real-time (subscriptions handle polling at scale)
- Single query language reduces API fragmentation
- Team has some GraphQL experience
- Scales to 10x users with proper caching

### Comparison Matrix
| Criteria | REST | GraphQL | gRPC |
|----------|------|---------|------|
| Real-time | 5/10 (polling overhead) | 9/10 (native) | 9/10 (streaming) |
| Team velocity | 9/10 (familiar) | 7/10 (learning curve) | 4/10 (steep curve) |
| Debugging | 8/10 (simple) | 6/10 (query complexity) | 5/10 (binary) |
| Latency | 7/10 (polling adds delay) | 8/10 (optimized) | 9/10 (binary) |
| Scalability | 7/10 (polling at 1000+ users) | 8/10 (caching helps) | 9/10 (binary efficiency) |

### Risk Assessment
| Approach | Risk | Likelihood | Mitigation |
|----------|------|-----------|-----------|
| REST | Polling overhead at scale | Medium | Implement long-polling or switch to GraphQL |
| GraphQL | N+1 query problem | Medium | Use DataLoader, proper resolver caching |
| gRPC | Team skill gap | High | 2-week ramp-up, pair programming |

### Implementation Roadmap
- **Week 1-2:** Setup Apollo Server, design schema
- **Week 3-4:** Implement core resolvers, real-time subscriptions
- **Week 5-6:** Testing, optimization, mobile client integration

### Next Steps
1. Prototype GraphQL API (1 week)
2. Benchmark against REST polling
3. If latency acceptable, proceed to full implementation
4. If N+1 problems surface, add caching layer
5. Revisit in 6 months for performance review
```

---

## Structured Output Template

Each agent should deliver in this format to ensure comparability:

### Header
```
# Approach: {Name}

## Executive Summary
[1-2 sentence assessment]

## Architecture Overview
[Diagram or description]
```

### Body
```
## How It Handles Constraints

| Constraint | Assessment | Notes |
|-----------|-----------|-------|
| <Constraint 1> | ✅/⚠️/❌ | [Rationale] |
| <Constraint 2> | ✅/⚠️/❌ | [Rationale] |

## Strengths (3-5)
1. [Honest advantage with rationale]
2. [Another genuine pro]

## Weaknesses (3-5)
1. [Honest disadvantage]
2. [Another genuine con]

## Team Impact
- Learning curve: [X weeks]
- Debugging difficulty: [Easy/Medium/Hard]
- Day-to-day friction: [Low/Medium/High]

## Implementation Complexity
- Backend effort: [X weeks]
- Frontend effort: [X weeks]
- Testing effort: [X weeks]
- **Total: X weeks**

## Risks & Mitigation
1. [Risk] → Likelihood: [Low/Med/High], Impact: [Low/Med/High]
   - Mitigation: [How to prevent]

## Recommendation for This Project
Recommend if: [Conditions where this approach succeeds]
Break if: [Conditions where this approach fails]
```

---

## Tips for Success

1. **Isolate agent contexts** — Each agent starts fresh, no bias from others
2. **Clear scope boundaries** — Agent A explores, doesn't critique Agent B
3. **Quantify** — Use metrics, timelines, complexity scores (not just opinions)
4. **Honest assessment** — Agents must articulate strengths AND weaknesses
5. **No consensus expected** — Synthesis agent decides; agents just explore
6. **Parallel execution** — All agents run simultaneously (the whole point)
7. **Structured output** — Same format across all agents for easy comparison

---

## Time Estimate

```
Preparation (articulate decision, define scopes): 1 hour
Agent 1 exploration (parallel): 2-3 hours
Agent 2 exploration (parallel): 2-3 hours
Agent 3 exploration (parallel): 2-3 hours
Synthesis (read reports + recommend): 2-3 hours
Review + decision: 1 hour

Total: 8-10 hours (parallel agents = only +5 hours vs. single agent)
```

**Is it worth it?**
- If decision affects team > 6 months: ✅ Yes
- If decision is easily reversible: ⚠️ Maybe
- If it's a small preference: ❌ No

---

## Related Resources

- **MULTI_AGENT_COORDINATION.md** — Deep dive guide with philosophy, patterns, gotchas
- **/plan** — Use this first to clarify if multi-agent is needed
- **grill-me** — Stress-test the chosen approach after synthesis

---

## Example: REST vs. GraphQL

### Agent A Briefing (REST)

```
Explore REST API for our mobile backend.

Scope:
- Polling strategy at scale (1000+ concurrent)
- Pagination and data fetching patterns
- Versioning and backward compatibility
- Latency impact of multiple round-trips

Deliverable: Structured output (see template)
```

### Agent B Briefing (GraphQL)

```
Explore GraphQL for our mobile backend.

Scope:
- Query language design and resolver patterns
- Real-time subscriptions (replace polling)
- N+1 query problem and caching strategies
- Schema versioning

Deliverable: Structured output (see template)
```

### Synthesis

```
Compare REST vs. GraphQL:
1. Recommendation (which is better for our project?)
2. Risk matrix
3. Implementation roadmap
4. Next validation steps
```

---

## Checklist Before Launch

- [ ] Decision question is clear (not vague)
- [ ] 2-3 approaches identified
- [ ] Constraints listed (latency, cost, team size, timeline)
- [ ] Success criteria defined
- [ ] Agent briefings written (clear scopes)
- [ ] All agents ready to launch simultaneously
- [ ] Timeline allows 6-8 hours (parallel exploration)
- [ ] Stakeholders agree to follow recommendation
