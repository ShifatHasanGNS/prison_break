# Minimax in Prison Break

## What it does

`MinimaxController` drives **RusherRed**, the aggressive prisoner. Every simulation tick
it runs alpha-beta minimax to depth 4 over Red's legal moves, treating Red as the
maximiser and the police as the minimiser, and returns the best move.

## Algorithm overview

```
for each legal move from Red's current tile:
    score = alphabeta(move, police_pos, blue_pos, exit, depth=3, α=-∞, β=+∞, maximising=false)
    score -= oscillation_penalty × 1.25
pick move with highest score; break ties with pick_stable_move()
```

The transposition table **persists across ticks** and is cleared only when it exceeds the cap.

## Key design choices

| Choice                          | Detail                                                                                                                                                                                                     |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Alpha-beta pruning**          | Standard negamax α-β; hard depth cap of 4. Prunes branches that can't affect the root decision.                                                                                                            |
| **Dual-prisoner minimiser**     | Blue's position is threaded through the entire tree. Police minimises `min(dist_to_red, dist_to_blue × 1.1)`, modelling the real threat of guarding two prisoners simultaneously.                          |
| **Zobrist transposition table** | Key hashes (red_pos, police_pos, depth, maximising). Persists between ticks for genuine reuse; cleared only on cap overflow (~10 k entries).                                                               |
| **Tile-unit distances**         | All evaluation distances are Manhattan tile counts. No pixel math anywhere in the heuristic.                                                                                                               |
| **Exit rotation penalty**       | If `dist_to_exit > ticks_until_next_rotation`, the current exit is unreachable before it rotates; adds +80 to `guard_penalty` so the tree seeks alternatives.                                              |
| **Progress-first baseline**     | A\* from Red's position to the active exit is computed first. If no path exists, BFS fallback moves toward the tile farthest from police. Minimax only refines moves that A\* already confirmed are legal. |
| **Oscillation guard**           | Inherited from `AIController`: 8-position rolling history; `pick_stable_move` breaks ABAB loops after minimax selects.                                                                                     |

## Evaluation function

```
score = w_exit × (−dist_to_exit)
      + w_risk × (−danger_cost)
      + w_opp  × (−1 / max(dist_to_police, 1))
      + w_stam × (stamina / max_stamina)
      − guard_penalty − fire_penalty − wall_penalty

guard_penalty:
  +800   if dist_to_police ≤ 2 tiles         (imminent capture)
  +grad  if dist_to_police ≤ 5 tiles         (gradient up to 60, proportional to zone)
  +80    if exit rotates before Red arrives   (rotation timing)

fire_penalty  = 600  if danger_cost ≥ 14 (fire tile cost ≈ 17 at DANGER_WEIGHT=2)
wall_penalty  = 300  if danger_cost = ∞  (unwalkable)
```

All weights `w_exit`, `w_risk`, `w_opp`, `w_stam` are in `data/ai/minimax_config.tres`.

## Tunable parameters (`data/ai/minimax_config.tres`)

| Parameter   | Default | Effect                                 |
| ----------- | ------- | -------------------------------------- |
| `max_depth` | 4       | Search depth (hard cap)                |
| `cache_cap` | 10 000  | Transposition table size before flush  |
| `w_exit`    | —       | Weight on distance-to-exit term        |
| `w_risk`    | —       | Weight on danger-cost term             |
| `w_opp`     | —       | Weight on inverse police-distance term |
| `w_stam`    | —       | Weight on stamina ratio term           |

## Signal output

Each tick emits `EventBus.minimax_decision(agent_id, top_candidates, chosen)`:

- `top_candidates` — up to 5 root moves with score and `police_responses` (top 3 police counter-moves with their scores, sorted worst-for-Red first)
- `chosen` — selected tile, score, `reason` string (`"exit progress · police far"`, `"safer lane · score lead"`, etc.), `pruned_branches`, `evaluated_nodes`, `search_depth`

Used by `DecisionOverlay` and `HudRoot` to display the live decision tree.

---

## Q & A

**Q: Why depth 4 specifically?**  
A: At 4 Hz (0.25 s/tick), depth 4 with alpha-beta on a 28×20 grid stays well under
budget. Depth 5 risks frame spikes with full branching; depth 3 misses two-move police
traps. The transposition table makes depth 4 faster in practice than a cold search.

**Q: Why does the minimiser also consider Blue's position?**  
A: Without it the police tree models a one-on-one chase and may choose moves that ignore
the nearer prisoner. Threading `blue_pos` lets the minimiser pick moves that apply dual
pressure — it moves toward whichever prisoner is cheaper to close on, weighted 10 % in
Red's favour so Red remains the primary threat in Red's own tree.

**Q: Why persist the transposition table between ticks instead of clearing it?**  
A: Clearing every tick wastes the cache — positions reached at depth 4 this tick often
reappear at depth 2 or 3 next tick (agents move one tile). Persisting gives genuine
speedup. The only risk is stale entries from state changes, which are acceptable because
the Zobrist key encodes position and depth; a stale value at the same key is still a
reasonable approximation.

**Q: How is guard_penalty a gradient rather than a cliff?**  
A: Within 5 tiles, `(5 − dist) / 5 × 60` adds up to 60 points of penalty proportional
to how deep inside the pressure zone Red is. The hard +800 at ≤ 2 tiles still makes
capture-adjacent positions essentially forbidden, but the gradient makes the tree route
around the zone early rather than waiting for the hard cliff.

**Q: What stops Red from always heading for a soon-to-rotate exit?**  
A: The exit rotation timing penalty adds +80 to `guard_penalty` when
`dist_to_exit > ticks_until_next_rotation`. This makes the current exit artificially
dangerous in the evaluation, pushing the tree to find routes toward other exits or to
wait in a safe position until the rotation completes.

**Q: How does the signal's `police_responses` field help the HUD?**  
A: For each top candidate move, the controller re-runs a single minimiser ply and records
the three worst police counter-moves (worst = lowest score for Red). The HUD can show
these as branches in a live decision tree, making the adversarial reasoning visible.

**Q: What happens when no exit is reachable at all?**  
A: `get_baseline_path` returns empty → BFS floods the walkable graph from Red's tile,
finds the tile with maximum minimum-distance to any police position, and returns a greedy
move toward it. Minimax is skipped entirely in this case.
