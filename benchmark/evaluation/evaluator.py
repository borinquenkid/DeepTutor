#!/usr/bin/env python
"""
Benchmark Evaluator - Score tutor responses and full dialogs

Uses LLM-as-judge to evaluate:
- Turn-level: Each tutor response on 9 dimensions (personalization + effectiveness)
- Dialog-level: Entire conversation on 8 dimensions (personalization + overall quality)

Requires transcript JSON with 'transcript' and 'entry' keys (from conversation runner).
"""

import json
import logging
from pathlib import Path

from benchmark.data_generation.llm_utils import call_llm_json, load_prompt

logger = logging.getLogger("benchmark.evaluation")

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent

# Personalization dimensions (weight 0.6) vs effectiveness (weight 0.4)
TURN_PERSONALIZATION_KEYS = [
    "knowledge_state_adaptation",
    "learning_style_adaptation",
    "misconception_targeting",
    "communication_style_match",
    "scaffolding_appropriateness",
]
TURN_EFFECTIVENESS_KEYS = [
    "correctness",
    "responsiveness",
    "clarity",
    "engagement",
]
DIALOG_PERSONALIZATION_KEYS = [
    "personalization_consistency",
    "gap_coverage",
    "misconception_resolution_trajectory",
    "success_criteria_met",
    "learning_path_adaptation",
]
DIALOG_QUALITY_KEYS = [
    "efficiency",
    "coherence",
    "student_agency",
]


def _format_profile(profile: dict) -> str:
    """Format student profile for prompt."""
    parts = []
    if profile.get("personality"):
        parts.append(f"Personality: {profile['personality']}")
    if profile.get("education_background"):
        parts.append(f"Background: {profile['education_background']}")
    if profile.get("learning_purpose"):
        parts.append(f"Purpose: {profile['learning_purpose']}")
    ks = profile.get("knowledge_state", {})
    if ks.get("known_well"):
        parts.append(f"Known well: {', '.join(ks['known_well'][:5])}")
    if ks.get("partially_known"):
        parts.append(f"Partially known: {', '.join(ks['partially_known'][:5])}")
    if ks.get("unknown"):
        parts.append(f"Unknown: {', '.join(ks['unknown'][:5])}")
    if profile.get("beliefs"):
        parts.append(f"Beliefs (may be misconceptions): {profile['beliefs']}")
    return "\n".join(parts) if parts else "(no profile)"


def _format_gaps(gaps: list) -> str:
    """Format knowledge gaps for prompt."""
    if not gaps:
        return "(no gaps)"
    lines = []
    for g in gaps:
        lines.append(
            f"- {g.get('target_concept', '?')}: {g.get('description', '')[:200]}... "
            f"Manifests as: {g.get('manifestation', '')[:150]}"
        )
    return "\n".join(lines)


def _format_task(task: dict) -> str:
    """Format task for prompt."""
    parts = []
    if task.get("title"):
        parts.append(f"Title: {task['title']}")
    if task.get("description"):
        parts.append(f"Description: {task['description']}")
    if task.get("success_criteria"):
        parts.append(f"Success criteria: {task['success_criteria']}")
    if task.get("target_gaps"):
        parts.append(f"Target gaps: {task['target_gaps']}")
    if task.get("expected_gap_exposure"):
        parts.append(f"Expected gap exposure: {task['expected_gap_exposure'][:300]}...")
    return "\n".join(parts) if parts else "(no task)"


def _format_transcript(transcript: list[dict]) -> str:
    """Format transcript for prompt."""
    lines = []
    for i, msg in enumerate(transcript, 1):
        role = msg.get("role", "?")
        content = (msg.get("content", "") or "")[:800]
        if len((msg.get("content") or "")) > 800:
            content += "..."
        lines.append(f"[{i}] {role.upper()}: {content}")
    return "\n\n".join(lines)


def _compute_weighted_avg(scores: dict, personalization_keys: list, other_keys: list) -> float:
    """Compute weighted average: 60% personalization, 40% other."""
    p_vals = [scores.get(k) for k in personalization_keys if scores.get(k) is not None]
    o_vals = [scores.get(k) for k in other_keys if scores.get(k) is not None]
    if not p_vals and not o_vals:
        return 0.0
    p_avg = sum(p_vals) / len(p_vals) if p_vals else 0.0
    o_avg = sum(o_vals) / len(o_vals) if o_vals else 0.0
    if p_vals and o_vals:
        return 0.6 * p_avg + 0.4 * o_avg
    return p_avg if p_vals else o_avg


async def evaluate_turn(
    entry: dict,
    transcript_up_to_turn: list[dict],
    student_message: str,
    tutor_response: str,
    turn_index: int,
    temperature: float = 0.2,
) -> dict:
    """
    Evaluate a single tutor response.

    Returns:
        dict with scores, rationale, personalization_subscore, overall_turn_score
    """
    prompt_cfg = load_prompt("eval_turn")
    profile = entry.get("profile", {})
    gaps = entry.get("gaps", [])
    task = entry.get("task", {})

    conv_text = _format_transcript(transcript_up_to_turn)

    user_prompt = prompt_cfg["user_template"].format(
        profile_summary=_format_profile(profile),
        gaps_summary=_format_gaps(gaps),
        task_summary=_format_task(task),
        conversation_context=conv_text or "(start of conversation)",
        student_message=student_message,
        tutor_response=tutor_response,
    )

    try:
        result = await call_llm_json(
            user_prompt=user_prompt,
            system_prompt=prompt_cfg["system"],
            temperature=temperature,
            max_tokens=1024,
        )
    except (json.JSONDecodeError, Exception) as e:
        logger.warning("Turn %d evaluation failed: %s", turn_index, e)
        return {
            "turn_index": turn_index,
            "scores": {},
            "rationale": f"Evaluation failed: {e}",
            "personalization_subscore": 0.0,
            "overall_turn_score": 0.0,
            "error": str(e),
        }

    scores = result.get("scores", {})
    rationale = result.get("rationale", "")

    personalization_subscore = 0.0
    if TURN_PERSONALIZATION_KEYS:
        p_vals = [scores.get(k) for k in TURN_PERSONALIZATION_KEYS if scores.get(k) is not None]
        personalization_subscore = sum(p_vals) / len(p_vals) if p_vals else 0.0

    overall = _compute_weighted_avg(
        scores, TURN_PERSONALIZATION_KEYS, TURN_EFFECTIVENESS_KEYS
    )

    return {
        "turn_index": turn_index,
        "scores": scores,
        "rationale": rationale,
        "personalization_subscore": round(personalization_subscore, 2),
        "overall_turn_score": round(overall, 2),
    }


async def evaluate_dialog(
    entry: dict,
    transcript: list[dict],
    temperature: float = 0.2,
) -> dict:
    """
    Evaluate the entire tutoring dialog.

    Returns:
        dict with scores, summary, personalization_dialog_score, overall_dialog_score
    """
    prompt_cfg = load_prompt("eval_dialog")
    profile = entry.get("profile", {})
    gaps = entry.get("gaps", [])
    task = entry.get("task", {})

    user_prompt = prompt_cfg["user_template"].format(
        profile_summary=_format_profile(profile),
        gaps_summary=_format_gaps(gaps),
        task_summary=_format_task(task),
        transcript=_format_transcript(transcript),
    )

    try:
        result = await call_llm_json(
            user_prompt=user_prompt,
            system_prompt=prompt_cfg["system"],
            temperature=temperature,
            max_tokens=1024,
        )
    except (json.JSONDecodeError, Exception) as e:
        logger.warning("Dialog evaluation failed: %s", e)
        return {
            "scores": {},
            "summary": f"Evaluation failed: {e}",
            "personalization_dialog_score": 0.0,
            "overall_dialog_score": 0.0,
            "error": str(e),
        }

    scores = result.get("scores", {})
    summary = result.get("summary", "")

    personalization_subscore = 0.0
    if DIALOG_PERSONALIZATION_KEYS:
        p_vals = [scores.get(k) for k in DIALOG_PERSONALIZATION_KEYS if scores.get(k) is not None]
        personalization_subscore = sum(p_vals) / len(p_vals) if p_vals else 0.0

    overall = _compute_weighted_avg(
        scores, DIALOG_PERSONALIZATION_KEYS, DIALOG_QUALITY_KEYS
    )

    return {
        "scores": scores,
        "summary": summary,
        "personalization_dialog_score": round(personalization_subscore, 2),
        "overall_dialog_score": round(overall, 2),
    }


async def evaluate_transcript(
    transcript_path: str | Path,
    skip_turns: bool = False,
    temperature: float = 0.2,
) -> dict:
    """
    Evaluate a transcript file (from conversation runner output).

    Args:
        transcript_path: Path to transcript JSON (must contain 'transcript' and 'entry')
        skip_turns: If True, only run dialog-level evaluation (faster)
        temperature: LLM temperature for evaluation

    Returns:
        Full evaluation result with turn_scores and dialog_scores
    """
    path = Path(transcript_path)
    if not path.exists():
        raise FileNotFoundError(f"Transcript not found: {path}")

    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    transcript = data.get("transcript", [])
    entry = data.get("entry", {})

    if not entry:
        raise ValueError("Transcript must contain 'entry' (benchmark entry with profile, gaps, task)")

    result = {
        "entry_id": data.get("entry_id", "unknown"),
        "transcript_path": str(path),
        "actual_turns": len([m for m in transcript if m.get("role") == "student"]),
        "turn_scores": [],
        "dialog_scores": {},
        "personalization_dialog_score": 0.0,
        "overall_dialog_score": 0.0,
        "summary": "",
    }

    # Turn-level evaluation
    if not skip_turns:
        turn_idx = 0
        for i in range(len(transcript)):
            msg = transcript[i]
            if msg.get("role") == "student" and i + 1 < len(transcript):
                next_msg = transcript[i + 1]
                if next_msg.get("role") == "tutor":
                    student_msg = msg.get("content", "")
                    tutor_msg = next_msg.get("content", "")
                    turn_idx += 1
                    conv_before = transcript[:i]  # Everything before this student message
                    turn_result = await evaluate_turn(
                        entry=entry,
                        transcript_up_to_turn=conv_before,
                        student_message=student_msg,
                        tutor_response=tutor_msg,
                        turn_index=turn_idx,
                        temperature=temperature,
                    )
                    result["turn_scores"].append(turn_result)
                    logger.info(
                        "Turn %d: overall=%.2f, personalization=%.2f",
                        turn_idx,
                        turn_result["overall_turn_score"],
                        turn_result["personalization_subscore"],
                    )

    # Dialog-level evaluation
    dialog_result = await evaluate_dialog(
        entry=entry,
        transcript=transcript,
        temperature=temperature,
    )
    result["dialog_scores"] = dialog_result.get("scores", {})
    result["personalization_dialog_score"] = dialog_result.get("personalization_dialog_score", 0.0)
    result["overall_dialog_score"] = dialog_result.get("overall_dialog_score", 0.0)
    result["summary"] = dialog_result.get("summary", "")

    # Weighted average: turn 40%, dialog 60% (when turn scores exist)
    turn_avg_overall = 0.0
    turn_avg_personalization = 0.0
    if result["turn_scores"]:
        turn_avg_overall = sum(t["overall_turn_score"] for t in result["turn_scores"]) / len(
            result["turn_scores"]
        )
        turn_avg_personalization = sum(
            t["personalization_subscore"] for t in result["turn_scores"]
        ) / len(result["turn_scores"])

    result["turn_avg_overall"] = round(turn_avg_overall, 2)
    result["turn_avg_personalization"] = round(turn_avg_personalization, 2)

    if result["turn_scores"]:
        result["combined_overall_score"] = round(
            0.4 * turn_avg_overall + 0.6 * result["overall_dialog_score"], 2
        )
        result["combined_personalization_score"] = round(
            0.4 * turn_avg_personalization + 0.6 * result["personalization_dialog_score"], 2
        )
    else:
        result["combined_overall_score"] = result["overall_dialog_score"]
        result["combined_personalization_score"] = result["personalization_dialog_score"]

    return result
