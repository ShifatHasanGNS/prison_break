# Prison Break: Triple Threat Escape Challenge

**Artificial Intelligence Laboratory (CSE 3209)** · Godot Engine 4.2 · Multi-Agent Strategy Game

## Overview

**Prison Break** is a multi-agent AI simulation built in Godot Engine 4.2 for an AI laboratory course. Three agents compete inside a tile-based prison escape environment, each controlled by a distinct AI algorithm. The project is designed as a decision-visualization system — not just a game — where AI reasoning is observable in real time through overlays, a live HUD, and a post-match AI analysis page.

## Agents & AI Algorithms

| Agent            | Algorithm                      | Behavior                                                                           |
| ---------------- | ------------------------------ | ---------------------------------------------------------------------------------- |
| 🔴 Rusher Red    | Minimax + Alpha-Beta Pruning   | Aggressive; plans adversarially against the Police/Hunter                          |
| 🔵 Sneaky Blue   | Monte Carlo Tree Search (MCTS) | Cautious; estimates future escape paths via rollouts                               |
| 🚔 Police/Hunter | Fuzzy Logic Inference System   | Defensive; chases, intercepts, investigates, or patrols based on uncertain signals |

## Environment

A tile-based prison grid with the following hazards and obstacles:

| Element            | Effect                                                      |
| ------------------ | ----------------------------------------------------------- |
| Walls / Boundaries | Block movement, force route planning                        |
| Doors / Barriers   | Restrict or delay paths                                     |
| Fire Hazards       | Danger map penalties, burning/elimination pressure          |
| CCTV Cameras       | Detect prisoners, increase Police/Hunter alert              |
| Dog NPC            | Mobile threat; patrol → alert → sniff → chase → latch cycle |
| Active Exit        | Rotating escape objective                                   |
| Decoy Exits        | Mislead path choices, add route penalties                   |

## Win Conditions

- **Prisoners win** — both reach the active exit
- **Police wins** — all prisoners are captured or eliminated
- **Partial escape** — at least one prisoner escapes
- **Timeout** — 60-second match expires before resolution

## System Architecture

```
Game Scene
├── Tick Clock
└── Simulation Loop
    ├── Grid Engine / Cost Map / Danger Map
    ├── EventBus
    ├── Scoring System
    ├── AI Decision Recorder
    ├── Police/Hunter — Fuzzy Logic Controller
    ├── Red Prisoner — Minimax Controller
    ├── Blue Prisoner — MCTS Controller
    ├── Dog NPC + CCTV System
    └── HUD, Overlays, Result Screen, Replay, Benchmark
```

## Project Structure

```
Prison_break/
├── ai/          # Fuzzy, Minimax, and MCTS controllers and configs
├── autoloads/   # EventBus, sound manager, sprite loader, user settings
├── core/        # Simulation loop, grid/cost/danger maps, scoring, replay
├── data/        # AI, simulation, scoring, and agent config resources
├── gameplay/    # Agents, dog NPC, abilities, status effects, CCTV, doors, fire
├── scenes/      # Main, intro, title, and result screen scenes
├── ui/          # HUD, overlays, pause, debug displays
├── world/       # Map generator, grid renderer, exit rotation
├── tools/       # Benchmark runner, replay exporter/importer, step debugger
├── assets/      # Audio, portraits, video
└── docs/        # Report, slides, screenshots, videos
```

## Tech Stack

- **Engine:** Godot 4.2
- **Language:** GDScript
- **AI Techniques:** Fuzzy Logic, Minimax + Alpha-Beta Pruning, Monte Carlo Tree Search
- **Architecture:** Signal/event-driven simulation

## How to Run

1. Open the project in **Godot Engine 4.2**
2. Load `scenes/main.tscn`
3. Press **Run**

## Authors

**Course:** CSE 3209 — Artificial Intelligence Laboratory  
**Institution:** Khulna University of Engineering & Technology  
**Submitted to:** Mehrab Hossain Opi & Waliul Islam Sumon  
**Student IDs:** 2107067 · 2107078 · 2107087
