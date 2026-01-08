---
name: mcode-profile-transformer
description: Transform MCode Motivational Assessment Reports (PDF) into structured Synthetic Profile (SP) JSON files. Use when processing MCode assessment PDFs to create "motivational operating systems" that enable LLM simulation of how individuals respond, make decisions, and interact based on their unique motivational drivers. Triggers on requests to create synthetic profiles, transform MCode reports, or build motivational personas from assessment data.
---

# MCode Profile Transformer

Transform MCode Assessment Reports into Synthetic Profiles (SPs) - structured JSON files that enable LLMs to respond as specific individuals based on their motivational patterns.

## Quick Start

1. Render MCode PDF pages as images using PyMuPDF
2. Use Claude's vision to extract data from rendered pages
3. Follow the 8-step transformation process below
4. Validate output with `scripts/validate_sp.py`

## PDF Extraction

MCode PDFs often use non-extractable text rendering. Use image-based extraction:

```python
import fitz  # PyMuPDF - pip install pymupdf

def render_mcode_pages(pdf_path, output_dir="./pages"):
    """Render PDF pages as images for visual extraction."""
    import os
    os.makedirs(output_dir, exist_ok=True)
    doc = fitz.open(pdf_path)
    # Key pages: 2-7 (Top 5), 8 (ranking), 11 (dimensions), 13 (blindspots), 14-17 (stories)
    key_pages = [2,3,4,5,6,7,8,11,13,14,15,16,17]
    for i in key_pages:
        page = doc[i-1]  # 0-indexed
        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
        pix.save(f"{output_dir}/page_{i}.png")
    print(f"Rendered {len(key_pages)} pages to {output_dir}/")
```

Then read the rendered images using Claude's vision capability to extract the data.

Key pages:
- **Pages 2-7**: Top 5 motivations with detailed descriptions
- **Page 8**: Full 32-motivation ranking with scores
- **Page 11**: Strongest dimensions (typically 3)
- **Page 13**: Blind spots for each dimension
- **Pages 14-17**: Achievement stories (4 stories)

## Transformation Process

### STEP 1: Extract Core Identity

From the report header:
```json
{
  "schema_version": "1.0",
  "persona_id": "{firstname}-{lastname}-mcode-001",
  "assessment_date": "YYYY-MM-DD",
  "identity": {
    "display_name": "{First Name}",
    "persona_type": "synthetic_user",
    "source": "mcode_assessment"
  }
}
```

### STEP 2: Build Motivational Core

**2A: Top 5 Motivations** - For each, extract:
- rank, name, score, description
- drivers (use keys from `references/driver_key_mappings.md`)
- thriving_environments (4 items from report)
- struggling_environments (3 items from report)
- flip_side (exact text from report)

**2B: Full Ranking** - Extract all 32 motivations from page 8 with rank and score.

### STEP 3: Map Dimensions

**Strongest** (from page 11): Extract name, description, blind_spots (from page 13).

**Weakest**: Identify from bottom 8-10 motivations using `references/dimension_mappings.md`.

### STEP 4: Analyze Motivational Flow

Synthesize from top motivations and achievement stories:
- **prompts**: What triggers their engagement (5-7 patterns)
- **process**: How they approach and execute work (5-7 patterns)
- **payoffs**: What results they celebrate (5-7 patterns)

### STEP 5: Transform Achievement Stories

For each of 4 stories, create structured entry with:
- id, title, summary, situation
- what_got_involved, what_did
- what_made_satisfying (list all elements)
- motivations_expressed (3-5 motivations demonstrated)

### STEP 6: Build Interaction Patterns

Synthesize how to engage, pitch to, negotiate with, and communicate:
- effective_approaches / ineffective_approaches
- key_appeals / language_that_resonates
- communication preferences / likely_to_dismiss

### STEP 7: Create Synthetic Response Guidance

Critical for LLM simulation:
- when_asked_about_new_opportunity (will_look_for, will_be_drawn_to, will_avoid)
- when_asked_how_to_approach_problem (typical_process steps)
- when_facing_setback (likely_response)
- values_hierarchy (high_priority from top 5-8, low_priority from bottom 5-8)

### STEP 8: Synthesize Notable Patterns

Requires analytical insight:
- **unique_insight**: What makes their pattern distinctive (tied scores, dimension combinations, throughlines)
- **emotional_signature**: Deep satisfaction patterns across stories
- **collaboration_style**: How they work with others (check Collaborate, Make The Team, Take Charge scores)

## Reference Files

| File | Purpose |
|------|---------|
| `references/driver_key_mappings.md` | Driver keys for all 32 motivations |
| `references/dimension_mappings.md` | Dimension ↔ Motivation relationships |
| `references/motivations_taxonomy.xml` | Full motivation definitions |
| `references/dimensions_taxonomy.xml` | Full dimension definitions |
| `references/quality_checklist.md` | Pre-delivery validation checklist |

## Validation

After transformation, validate the JSON:

```bash
python scripts/validate_sp.py path/to/profile.json
```

This checks:
- JSON schema compliance
- All 32 motivations present with valid scores
- Required fields populated
- Motivation names match taxonomy exactly
- Score ranges valid (0-10)

## Common Errors to Avoid

1. **Generic flip_sides** - Use exact language from report
2. **Missing story motivations** - Every story needs 3-5 motivations_expressed
3. **Inconsistent naming** - Use exact names (e.g., "Meet The Challenge" not "Meet Challenges")
4. **Overlooking tied scores** - Note in unique_insight when motivations tie
5. **Ignoring low motivations** - Bottom 5-8 are as revealing as top
6. **Generic notable_patterns** - Must reference THIS person's specific stories
7. **Collaboration assumption** - Check actual scores, don't assume

## Output Usage

The completed SP enables:
1. **Respond as individual**: "Based on your MCode profile, you would likely..."
2. **Predict reactions**: "Given your motivation to [X], you'd probably feel..."
3. **Tailor communication**: "To pitch this effectively, emphasize [X] because..."
4. **Identify fit**: "This role aligns with your [X] but may challenge your need for [Y]"

See `examples/chris_teitzel_sp.json` for a complete reference implementation.
