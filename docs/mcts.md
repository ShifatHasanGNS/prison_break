# Monte Carlo Tree Search in Prison Break

## What it does

`MctsController` drives **SneakyBlue**, the stealth prisoner. Every simulation tick it
runs a flat UCT-MCTS over Blue's legal moves, selects the best action, and returns it
to the simulation loop.

## Algorithm overview

```
for 200 iterations:
    1. SELECT   — UCT over root children (legal moves from current tile)
    2. ROLLOUT  — random-biased depth-18 simulation from selected move
    3. BACKPROP — accumulate score into the selected root child
pick child with highest decision_score (avg rollout + exit proximity − oscillation penalty)
```

The tree is **reset every tick** — there is no persistent tree between decisions.

## Key design choices

| Choice                  | Detail                                                                                                                                                                         |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Flat tree**           | Only root children are expanded; no recursive node creation. Depth comes from rollout, not the tree.                                                                           |
| **UCT selection**       | `exploit + C·√(ln(N)/n)`, C = 1.414 (`√2`). Unvisited nodes are prioritised (UCT = ∞).                                                                                         |
| **Adversarial rollout** | Police positions advance one Manhattan step toward Blue each rollout step, modelling active pursuit.                                                                           |
| **Exit rotation**       | `_simulate_exit_at_tick(step)` predicts which exit will be active at each rollout step using `ticks_until_next_rotation()`. Paths toward a soon-to-vanish exit are discounted. |
| **Danger bias**         | 70 % of rollout steps use `_pick_best_rollout_step` (low-danger + police-avoidance heuristic); 30 % are random.                                                                |
| **Stamina penalty**     | Rollout score is penalised if simulated stamina ratio < 0.25, steering Blue away from exhaustion routes.                                                                       |
| **BFS fallback**        | If A\* finds no path to any exit, a BFS floods from current position and returns the tile farthest from police.                                                                |
| **Oscillation guard**   | Inherited from `AIController`: rolling 8-position history detects ABAB loops; `pick_stable_move` breaks them.                                                                  |

## Rollout score formula

```
score = (exit_score + safety_score) × 0.5 − stamina_penalty − rotation_penalty

exit_score    = 1 / (1 + dist_to_exit × 0.1)          # closer = better
safety_score  = min(min_police_dist / 10, 1.0)         # farther = safer
               − pressure_penalty if police ≤ 5 tiles
stamina_pen   = (0.25 − stamina_ratio) × 0.6 if stamina < 25 %
rotation_pen  = exit_score × 0.5 if exit rotates before Blue arrives
```

Terminal conditions during rollout: reaching the active exit → `1.0`; police within 2 tiles → `0.0`.

## Tunable parameters (`data/ai/mcts_config.tres`)

| Parameter              | Default | Effect                                       |
| ---------------------- | ------- | -------------------------------------------- |
| `max_iterations`       | 200     | Search budget per tick                       |
| `rollout_depth`        | 18      | Steps per simulation                         |
| `exploration_constant` | 1.414   | UCT exploration weight                       |
| `low_danger_bias`      | 0.7     | Fraction of guided (vs random) rollout steps |

## Signal output

Each tick emits `EventBus.mcts_decision(agent_id, root_visits, top_candidates, chosen)`:

- `root_visits` — total iterations run
- `top_candidates` — up to 5 moves with visit count, average score, and UCT value
- `chosen` — selected move with reason string (`"exit route"`, `"danger avoided"`, etc.)

Used by `DecisionOverlay` and `HudRoot` to display live AI reasoning.

---

## Q & A

**Q: Why flat MCTS instead of a full tree?**  
A: Blue makes one decision per 0.25 s tick. With a 200-iteration budget and an 18-step
rollout, a flat tree (expand root children only) yields good move discrimination without
the overhead of managing a growing node graph that would be discarded immediately anyway.

**Q: Why reset the tree every tick?**  
A: The game state changes every tick (all agents move, danger map rebuilds, exit may
rotate). Reusing stale visit counts from a previous state would bias selection toward
moves that were good in a different context.

**Q: How does the rollout know where the police will be?**  
A: It doesn't use the real game state — it steps each police position one Manhattan tile
toward Blue's simulated position after every rollout step. This is a simple adversarial
approximation that makes the rollout pessimistic without requiring full game simulation.

**Q: What if Blue is stuck (no legal moves)?**  
A: `choose_action` returns WAIT immediately. If moves exist but no exit is reachable via
A\*, the BFS fallback runs and Blue moves toward the tile farthest from the nearest police.

**Q: How does MCTS interact with the exit rotation system?**  
A: Two ways. `_simulate_exit_at_tick(step)` predicts the active exit at each rollout
step using `ticks_until_next_rotation()`, so the rollout targets the _future_ exit, not
the current one. The final `rotation_penalty` then discounts the exit score if the exit
will rotate before Blue can reach it from the rollout's end position.

**Q: Why 1.414 as the exploration constant?**  
A: `√2` is the theoretically optimal constant for UCT when rewards are in `[0, 1]`. The
rollout score is designed to stay in `[0, 1]` so the default is appropriate without
further tuning.

**Q: How is the final move chosen from the MCTS results?**  
A: Not purely by visit count. Each root child gets a `decision_score`:
`avg_rollout_score + 0.25 × (1/(1+dist_to_exit)) − 0.18 × oscillation_penalty`.
The highest `decision_score` wins. `pick_stable_move` then rejects it if it would
recreate a recently detected oscillation pattern.
