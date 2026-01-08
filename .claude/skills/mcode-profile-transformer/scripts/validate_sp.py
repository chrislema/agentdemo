#!/usr/bin/env python3
"""
MCode Synthetic Profile Validator

Validates SP JSON files against the schema and performs additional semantic checks.

Usage:
    python validate_sp.py <profile.json>
    python validate_sp.py <profile.json> --verbose
"""

import json
import sys
import os
from pathlib import Path

# Valid motivation names (must match exactly)
VALID_MOTIVATIONS = [
    "Advance", "Architect", "Be Key", "Be Unique", "Collaborate",
    "Comprehend And Express", "Demonstrate Learning", "Design", "Develop",
    "Do It Right", "Establish", "Evoke Recognition", "Excel",
    "Experience The Ideal", "Explore", "Finish", "Gain Ownership",
    "Identify Potential", "Improve", "Make An Impact", "Make It Work",
    "Make The Team", "Mastery", "Maximize", "Meet Needs", "Meet Requirements",
    "Meet The Challenge", "Overcome", "Persuade", "Realize The Vision",
    "Systematize", "Take Charge"
]

VALID_DIMENSIONS = [
    "Achiever", "Driver", "Influencer", "Learner", 
    "Optimizer", "Orchestrator", "Relator", "Visionary"
]


def validate_sp(filepath: str, verbose: bool = False) -> tuple[bool, list[str]]:
    """
    Validate a Synthetic Profile JSON file.
    
    Returns:
        (is_valid, list_of_errors)
    """
    errors = []
    warnings = []
    
    # Load JSON
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return False, [f"Invalid JSON: {e}"]
    except FileNotFoundError:
        return False, [f"File not found: {filepath}"]
    
    # Required top-level fields
    required_fields = [
        "schema_version", "persona_id", "assessment_date", "identity",
        "motivational_core", "dimensions", "motivational_flow",
        "achievement_stories", "interaction_patterns", 
        "synthetic_response_guidance", "notable_patterns"
    ]
    
    for field in required_fields:
        if field not in data:
            errors.append(f"Missing required field: {field}")
    
    if errors:
        return False, errors
    
    # Validate schema_version
    if data.get("schema_version") != "1.0":
        errors.append(f"Invalid schema_version: expected '1.0', got '{data.get('schema_version')}'")
    
    # Validate persona_id format
    persona_id = data.get("persona_id", "")
    if not persona_id or persona_id.count("-") < 2 or not persona_id.endswith("-mcode-001"):
        warnings.append(f"persona_id '{persona_id}' may not follow format: firstname-lastname-mcode-001")
    
    # Validate identity
    identity = data.get("identity", {})
    if identity.get("persona_type") != "synthetic_user":
        errors.append("identity.persona_type must be 'synthetic_user'")
    if identity.get("source") != "mcode_assessment":
        errors.append("identity.source must be 'mcode_assessment'")
    if not identity.get("display_name"):
        errors.append("identity.display_name is required")
    
    # Validate motivational_core
    mc = data.get("motivational_core", {})
    
    # Check top_5
    top_5 = mc.get("top_5", [])
    if len(top_5) != 5:
        errors.append(f"motivational_core.top_5 must have exactly 5 items, found {len(top_5)}")
    
    for i, mot in enumerate(top_5):
        name = mot.get("name", "")
        if name not in VALID_MOTIVATIONS:
            errors.append(f"Invalid motivation name in top_5[{i}]: '{name}'")
        
        score = mot.get("score")
        if score is None or not (0 <= score <= 10):
            errors.append(f"Invalid score in top_5[{i}]: {score}")
        
        drivers = mot.get("drivers", {})
        if len(drivers) != 4:
            warnings.append(f"top_5[{i}] '{name}' should have exactly 4 drivers, found {len(drivers)}")
        
        if not mot.get("flip_side"):
            errors.append(f"Missing flip_side in top_5[{i}] '{name}'")
    
    # Check full_ranking
    full_ranking = mc.get("full_ranking", [])
    if len(full_ranking) != 32:
        errors.append(f"full_ranking must have exactly 32 items, found {len(full_ranking)}")
    
    found_motivations = set()
    for i, mot in enumerate(full_ranking):
        name = mot.get("name", "")
        if name not in VALID_MOTIVATIONS:
            errors.append(f"Invalid motivation name in full_ranking[{i}]: '{name}'")
        if name in found_motivations:
            errors.append(f"Duplicate motivation in full_ranking: '{name}'")
        found_motivations.add(name)
        
        rank = mot.get("rank")
        if rank != i + 1:
            warnings.append(f"full_ranking[{i}] has rank {rank}, expected {i + 1}")
        
        score = mot.get("score")
        if score is None or not (0 <= score <= 10):
            errors.append(f"Invalid score in full_ranking[{i}] '{name}': {score}")
    
    # Check all 32 motivations present
    missing = set(VALID_MOTIVATIONS) - found_motivations
    if missing:
        errors.append(f"Missing motivations in full_ranking: {missing}")
    
    # Validate dimensions
    dims = data.get("dimensions", {})
    strongest = dims.get("strongest", [])
    if len(strongest) < 2:
        errors.append(f"dimensions.strongest should have at least 2-3 dimensions, found {len(strongest)}")
    
    for i, dim in enumerate(strongest):
        name = dim.get("name", "")
        if name not in VALID_DIMENSIONS:
            errors.append(f"Invalid dimension name in strongest[{i}]: '{name}'")
        
        if not dim.get("blind_spots", {}).get("when_not_at_best"):
            errors.append(f"Missing blind_spots.when_not_at_best for dimension '{name}'")
        if not dim.get("blind_spots", {}).get("advice"):
            errors.append(f"Missing blind_spots.advice for dimension '{name}'")
    
    weakest = dims.get("weakest", [])
    for dim_name in weakest:
        if dim_name not in VALID_DIMENSIONS:
            errors.append(f"Invalid dimension name in weakest: '{dim_name}'")
    
    # Validate achievement_stories
    stories = data.get("achievement_stories", [])
    if len(stories) < 3:
        errors.append(f"Should have at least 3-4 achievement stories, found {len(stories)}")
    
    for i, story in enumerate(stories):
        if not story.get("motivations_expressed"):
            errors.append(f"Missing motivations_expressed in story {i+1}")
        else:
            mots = story.get("motivations_expressed", [])
            if len(mots) < 3:
                warnings.append(f"Story {i+1} should have 3-5 motivations_expressed, found {len(mots)}")
            for mot in mots:
                if mot not in VALID_MOTIVATIONS:
                    errors.append(f"Invalid motivation in story {i+1} motivations_expressed: '{mot}'")
    
    # Validate notable_patterns lengths
    np = data.get("notable_patterns", {})
    if len(np.get("unique_insight", "")) < 100:
        warnings.append("notable_patterns.unique_insight should be at least 100 characters")
    if len(np.get("emotional_signature", "")) < 100:
        warnings.append("notable_patterns.emotional_signature should be at least 100 characters")
    if len(np.get("collaboration_style", "")) < 50:
        warnings.append("notable_patterns.collaboration_style should be at least 50 characters")
    
    # Validate interaction_patterns
    ip = data.get("interaction_patterns", {})
    ltr = ip.get("how_to_pitch_to", {}).get("language_that_resonates", [])
    if len(ltr) < 10:
        warnings.append(f"language_that_resonates should have 10-20 words, found {len(ltr)}")
    
    # Print results
    is_valid = len(errors) == 0
    
    if verbose or not is_valid:
        print(f"\n{'='*60}")
        print(f"Validation Results: {filepath}")
        print(f"{'='*60}")
        
        if errors:
            print(f"\n❌ ERRORS ({len(errors)}):")
            for e in errors:
                print(f"   • {e}")
        
        if warnings and verbose:
            print(f"\n⚠️  WARNINGS ({len(warnings)}):")
            for w in warnings:
                print(f"   • {w}")
        
        if is_valid:
            print(f"\n✅ VALID - Profile passes all required checks")
            if warnings:
                print(f"   ({len(warnings)} warnings - run with --verbose to see)")
        else:
            print(f"\n❌ INVALID - {len(errors)} error(s) found")
        
        print()
    
    return is_valid, errors


def main():
    if len(sys.argv) < 2:
        print("Usage: python validate_sp.py <profile.json> [--verbose]")
        sys.exit(1)
    
    filepath = sys.argv[1]
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    
    is_valid, errors = validate_sp(filepath, verbose)
    sys.exit(0 if is_valid else 1)


if __name__ == "__main__":
    main()
