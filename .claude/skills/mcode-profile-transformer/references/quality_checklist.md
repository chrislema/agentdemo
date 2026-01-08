# Quality Checklist

Verify each item before delivering a Synthetic Profile.

## Structural Completeness

- [ ] All 32 motivations present in `full_ranking` with correct scores
- [ ] Top 5 motivations have complete driver descriptions (4 drivers each)
- [ ] All 4 achievement stories transformed with `motivations_expressed`
- [ ] Strongest dimensions include `blind_spots` from report (page 13)
- [ ] Weakest dimensions accurately identified from bottom motivations
- [ ] JSON is valid and properly formatted

## Content Accuracy

- [ ] `flip_side` uses exact language from report (not paraphrased)
- [ ] Motivation names match taxonomy exactly (e.g., "Meet The Challenge" not "Meet Challenges")
- [ ] Scores match report values (check for transcription errors)
- [ ] Thriving/struggling environments extracted from correct motivation sections
- [ ] Achievement story summaries accurately reflect the full story content

## Analytical Quality

- [ ] `motivations_expressed` in stories align with actual story content (3-5 per story)
- [ ] `language_that_resonates` drawn from motivation descriptions, drivers, and story language
- [ ] `values_hierarchy.high_priority` maps to top 5-8 motivations
- [ ] `values_hierarchy.low_priority` maps to bottom 5-8 motivations
- [ ] `notable_patterns.unique_insight` is specific to THIS person, not generic

## Notable Patterns Verification

### unique_insight should include:
- [ ] Any tied motivation scores (especially at top)
- [ ] Dominant dimension combination (e.g., "Influencer-Visionary-Relator")
- [ ] Throughline across all 4 achievement stories
- [ ] Any surprising contrasts (e.g., high impact with low recognition need)

### emotional_signature should reflect:
- [ ] Words that appear in "what made satisfying" across multiple stories
- [ ] What results they celebrate
- [ ] Whether recognition matters or is irrelevant
- [ ] Whether satisfaction is self-focused or others-focused

### collaboration_style should verify:
- [ ] Actual Collaborate score (don't assume)
- [ ] Make The Team score
- [ ] Take Charge score
- [ ] Evidence from stories about how they work with others

## Final Validation

- [ ] Run `scripts/validate_sp.py` with no errors
- [ ] Review output JSON for any placeholder text remaining
- [ ] Confirm persona_id follows format: `{firstname}-{lastname}-mcode-001`
- [ ] Verify assessment_date is in YYYY-MM-DD format
