extends Resource
class_name FuzzyConfig

# ── Distance membership breakpoints ────────────────────────────────────────────
# MODERATE #1 FIX: Cleaned up near/medium overlap.
#
# OLD values:  NEAR_FULL=3.0, NEAR_ZERO=5.5, MEDIUM_LOW=3.5, MEDIUM_PEAK=6.5
#   → 2-tile overlap (3.5–5.5): near_mu and medium_mu both active simultaneously.
#   → At 4.5 tiles with fluctuating alert, police flipped CHASE↔INVESTIGATE
#     every tick, producing visible zigzag movement.
#
# NEW values:  NEAR_FULL=3.0, NEAR_ZERO=4.5, MEDIUM_LOW=4.0, MEDIUM_PEAK=7.0
#   → 0.5-tile overlap (4.0–4.5) — narrow and intentional for smooth blending.
#   → Clean separation means behaviour commits properly once distance stabilises.
@export var dist_close:      float = 3.0   # NEAR_FULL  — fully "near" up to here
@export var dist_near_zero:  float = 5.5   # NEAR_ZERO  — widened to 5.5 so near covers d=4-5 (Bug 1 fix)
@export var dist_medium_low:  float = 3.5  # MEDIUM_LOW — lowered to 3.5 for overlap at transition (Bug 1 fix)
@export var dist_medium_peak: float = 7.0  # MEDIUM_PEAK — keep
@export var dist_medium_high: float = 11.0 # MEDIUM_HIGH — was 10.0; extended for smoother fade
@export var dist_far_zero:   float = 7.0   # FAR_ZERO  — aligned with new medium_peak
@export var dist_far:        float = 12.0  # FAR_FULL  — fully "far" from here

# ── Alert level thresholds ─────────────────────────────────────────────────────
@export var alert_suspicious: float = 0.35  # ALERT_SUSPICIOUS_THRESHOLD
@export var alert_alarmed:    float = 0.50  # ALERT_ALARMED_THRESHOLD

# ── Behaviour score weights (applied as multipliers) ──────────────────────────
@export var w_chase:     float = 1.25
@export var w_investigate: float = 1.0
@export var w_intercept: float = 1.0
@export var w_patrol:    float = 1.0

# ── Alert-level influence on chase score ──────────────────────────────────────
# Added to chase_score as:  alert_level * alert_chase_weight
# Replaces the hard early-return bypasses (Critical #3 fix).
@export var alert_chase_weight:     float = 0.80
@export var alert_chase_base_bias:  float = 0.40

# ── Exit-threat fuzzy membership thresholds ───────────────────────────────────
# Escape urgency is normalized to 0..10, where 0 means no immediate exit threat
# and 10 means the prisoner is at/very near the active exit. These values match
# Fig 8 in the report: Low, Medium, and High exit-threat memberships.
@export var exit_low_full: float = 2.0
@export var exit_low_zero: float = 4.5
@export var exit_medium_low: float = 3.0
@export var exit_medium_peak: float = 5.0
@export var exit_medium_high: float = 7.5
@export var exit_high_zero: float = 6.0
@export var exit_high_full: float = 8.0

# ── CCTV-confidence fuzzy membership thresholds ───────────────────────────────
# CCTV confidence is normalized to 0..1. These values match Fig 9 in the report:
# Weak, Medium, and Strong CCTV-confidence memberships.
@export var cctv_weak_full: float = 0.25
@export var cctv_weak_zero: float = 0.50
@export var cctv_medium_low: float = 0.25
@export var cctv_medium_peak: float = 0.50
@export var cctv_medium_high: float = 0.75
@export var cctv_strong_zero: float = 0.55
@export var cctv_strong_full: float = 0.75

# ── Weights for exit-threat and CCTV fuzzy rules ──────────────────────────────
@export var w_exit_low_patrol: float = 0.35
@export var w_exit_medium_investigate: float = 0.45
@export var w_exit_medium_intercept: float = 0.55
@export var w_exit_high_intercept: float = 1.35
@export var w_cctv_weak_investigate: float = 0.25
@export var w_cctv_medium_investigate: float = 0.80
@export var w_cctv_strong_chase: float = 0.45
@export var w_cctv_strong_intercept: float = 0.90


# ── Legacy visibility / noise / threat fields (kept for compatibility) ─────────
@export var vis_low: float    = 0.2
@export var vis_medium: float = 0.5
@export var vis_high: float   = 0.8

@export var noise_quiet:  float = 2.0
@export var noise_medium: float = 5.0
@export var noise_loud:   float = 8.0

@export var threat_low:    float = 2.0
@export var threat_medium: float = 5.0
@export var threat_high:   float = 8.0
