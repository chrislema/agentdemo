---
name: series-planning
description: |
  Multi-episode series architecture for podcasts, video series, email courses, and sequential content.
  Covers arc shapes, episode sequencing, inter-episode connective tissue, episode types, and 
  series/episode promise nesting.
  
  Use when: planning a podcast series, designing multi-part content sequences, structuring 
  email courses, mapping episode arcs, or sequencing educational content across multiple pieces.
  
  Note: For individual episode creation, use the content-creation skill. This skill handles 
  the meta-layer of how episodes connect and sequence.
---

# Series Planning System

Architecture for multi-episode content. This skill handles sequencing logic *across* episodes. For creating individual episodes, use the `content-creation` skill.

## When to Use This Skill

- Planning a podcast series (primary use case)
- Designing multi-part blog sequences
- Structuring email courses or drip sequences
- Mapping video series arcs
- Any content where someone consumes multiple connected pieces over time

## Core Concept: The Trust Ladder

Each episode moves the listener up or down:

```
Episode 1: "Is this worth my time?"
Episode 2: "Was episode 1 a fluke or a pattern?"
Episode 3: "Okay, this person knows what they're talking about"
Episode 4: "I'm invested now—I want to see where this goes"
Episode 5+: "This is part of my rotation—I'm committed"
```

**Critical insight:** Episodes 1-3 are auditions. Episodes 4+ are the actual series. Don't treat episode 1 like episode 5.

## Workflow: Planning a Series

### Step 1: Define the Series Promise
The transformation or value listeners get from completing the entire series.

Formula: "By the end of this series, you will [understand/be able to/see] X that you can't [understand/do/see] now."

### Step 2: Choose Arc Shape
Load: `references/series-architecture.md` → "Series Arc Shapes" section

Five options:
1. **Ascending Build** - Foundation → Intermediate → Advanced (educational content)
2. **Problem-Solution Sequence** - Problems first, solutions second (consulting content)
3. **Thematic Cluster** - Grouped by theme, flexible order (reference content)
4. **Case Study Sequence** - Multiple stories illustrating same principles (experience-based)
5. **Narrative Journey** - One extended story across all episodes (documentary-style)

### Step 3: Design Episode Distribution
Map your content to the arc shape. Assign episode types:
- **Foundation Episodes** (1-3): Establish essential knowledge
- **Payoff Episodes** (4, 7, 10): Major insights, "aha" moments
- **Breather Episodes**: Lower intensity, let concepts sink in
- **Bridge Episodes** (4, 8): Transition between sections
- **Climax Episode** (10 or 11): Series' biggest moment

### Step 4: Plan the Pilot (Episode 1)
The pilot has 5 unique jobs:
1. Prove competence (within first 3 minutes)
2. Establish stakes (why care for 12 episodes?)
3. Set format expectations
4. Preview the journey
5. Earn Episode 2 (end with open loop)

**Timing:** First 3 min = hook + competence. Min 3-10 = stakes. Min 10-20 = deliver ONE complete insight. Final 2 min = preview + open loop.

### Step 5: Plan the Finale
Four unique jobs:
1. Synthesis (pull together threads)
2. Transformation proof (contrast with episode 1)
3. Closure (close every loop)
4. Continuation path (what's next)

**Critical:** No new content in the finale. It's for landing, not launching.

### Step 6: Design Connective Tissue
Load: `references/series-architecture.md` → "Inter-Episode Connective Tissue" section

- **Opening Callbacks**: Connect to previous episode
- **Closing Hooks**: Pull toward next episode
- **Running Threads**: Elements that recur (terminology, characters, questions)
- **Episode Bridges**: Final 2 min of each episode + first 2 min of next should feel connected

### Step 7: Nest Episode Promises
Each episode has its own promise that contributes to the series promise:

```
Series Promise: "Build a pricing strategy that doesn't fail"

Episode 2 Promise: "Understand why value-based pricing fails for most agencies"
Episode 3 Promise: "Identify your actual pricing constraints"
Episode 4 Promise: "Build the first version of your pricing framework"
...
Episode 12 Promise: "Put it all together into a complete system"
```

Completing all episode promises = series promise fulfilled.

## Surviving the Sagging Middle (Episodes 5-7)

The middle is where series die. Tactics:
1. **Vary format** - Don't let every episode feel identical
2. **Escalate stakes** - Re-establish why this matters around episode 5-6
3. **Deliver standalone wins** - Each episode should feel complete
4. **Create mid-series payoff** - Episode 6 or 7 should have a significant "aha"
5. **Strengthen hooks** - Middle episodes need stronger "next episode" pulls

## Quality Checklist Before Finalizing

- [ ] Series promise stated in one sentence?
- [ ] Pilot delivers complete, standalone value?
- [ ] Dependencies mapped? Sequencing logical?
- [ ] Payoff episode between 5-7?
- [ ] Format varies across middle?
- [ ] Every episode (except finale) ends with hook to next?
- [ ] At least 2 running threads across series?
- [ ] Finale synthesizes, closes loops, provides continuation?
- [ ] Episode promises add up to series promise?

## Reference File

`references/series-architecture.md` contains:
- Detailed arc shape specifications
- Episode sequencing principles
- Inter-episode connective tissue patterns
- Episode type definitions
- Common failures and fixes

## Integration with Content-Creation Skill

Series Architecture sets the WHAT and WHERE.
The `content-creation` skill handles the HOW within each episode.

**For each episode:**
1. Use this skill to determine: Episode's role, promise, position in arc
2. Use `content-creation` skill to determine: Story shape, gap/stakes/progression, trigger placement
