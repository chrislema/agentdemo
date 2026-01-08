---
name: mcode-translator
description: Translates any message, email, website copy, or communication into MCode dimension-specific language using NLP techniques. Use when the user wants to adapt communication for a specific MCode dimension (Achiever, Driver, Influencer, Learner, Optimizer, Orchestrator, Relator, Visionary), translate content to resonate with someone's motivational profile, or rewrite messages using dimension-appropriate linguistic patterns, meta programs, and framing strategies.
---

# MCode Translator

Transform any communication to resonate with a specific MCode dimension by applying dimension-specific linguistic patterns, meta programs, and NLP-based translation rules.

## Quick Start

1. Identify the target dimension (one of 8 MCode dimensions)
2. Read the NLP rules for that dimension from `references/nlp_rules.xml`
3. Apply translation rules, linguistic patterns, and framing strategies
4. Avoid patterns that conflict with the dimension

## The 8 MCode Dimensions

| Dimension | Core Drive | Communication Focus |
|-----------|-----------|---------------------|
| **Achiever** | Excellence, recognition, standing out | Results, distinction, personal achievement |
| **Driver** | Forward momentum, overcoming obstacles | Action, progress, breakthrough |
| **Influencer** | Impact on others, persuasion | Relationships, inspiration, change |
| **Learner** | Knowledge, understanding, growth | Discovery, mastery, expertise |
| **Optimizer** | Efficiency, improvement, refinement | Streamlining, fixing, enhancing |
| **Orchestrator** | Coordination, strategic oversight | Systems, leadership, organization |
| **Relator** | Connection, collaboration, team harmony | Relationships, support, unity |
| **Visionary** | Innovation, future possibilities | Creativity, transformation, pioneering |

## Translation Workflow

```
1. INPUT: Original message + Target dimension
2. LOAD: Read references/nlp_rules.xml for target dimension
3. ANALYZE: Identify patterns to transform and avoid
4. APPLY:
   - Meta programs (internal/external reference, toward/away motivation)
   - Power verbs specific to dimension
   - Sensory predicates (visual/auditory/kinesthetic)
   - Framing strategies
   - Embedded commands
5. VALIDATE: Ensure avoided patterns are not present
6. OUTPUT: Transformed message
```

## Translation Principles

From `references/nlp_rules.xml` General Principles:
- Maintain core message while transforming language patterns
- Write at 10th grade reading level for approachability
- Use sensory-specific language matching dimension's processing style
- Apply appropriate meta programs to frame information compellingly
- Match energy levels and communication pace to dimensional preferences
- Create emotional anchors connecting to dimensional motivations
- Use presuppositions and embedded commands aligned with dimensional drives

## Reference Files

### references/nlp_rules.xml
**Primary translation resource.** Contains for each dimension:
- Core motivation
- Meta programs (internal/external reference, toward/away, options/procedures, etc.)
- Translation rules (specific transformations to apply)
- Linguistic patterns (predicates, power verbs, anchors, embedded commands)
- Framing strategies (outcome, comparison, progress frames)
- Patterns to avoid

### references/dimensions.xml
Complete dimension profiles including:
- Primary goals and characteristics
- Thrives in / Struggles in environments
- Voice, brand, fears
- Related motivations (maps to the 32 motivations)
- Communication strategy details

### references/motivations.xml
The 32 individual motivations that roll up into dimensions:
- Motivation descriptions and characteristics
- Strengths and flip sides
- Environment fit details

## Example: Translating for Driver

**Original:** "Our software helps teams work better together."

**Driver Translation Process:**
1. Load Driver rules: momentum, overcoming, action-oriented
2. Apply meta programs: procedures orientation, toward motivation, activity focus
3. Use power verbs: advance, overcome, drive, accelerate, breakthrough
4. Apply kinesthetic predicates: push through, drive forward, build momentum
5. Avoid: passive language, maintenance focus, complex explanations

**Result:** "Drive your team forward with software that breaks through collaboration barriers and accelerates results."

## Multi-Dimension Translation

When translating for someone with known primary and secondary dimensions:
1. Lead with primary dimension patterns (70%)
2. Weave in secondary dimension anchors (30%)
3. Ensure no conflicts between dimensional approaches

## Usage Notes

- Always read the full NLP rules for the target dimension before translating
- Maintain authenticity—transform language patterns, not the core message
- Calibrate intensity to context (email vs. landing page vs. sales pitch)
- Test with different framing strategies when unsure
