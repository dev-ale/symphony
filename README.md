# Symphony

Symphony turns project work into isolated, autonomous implementation runs, allowing teams to manage
work instead of supervising coding agents.

[![Symphony demo video preview](.github/media/symphony-demo-poster.jpg)](.github/media/symphony-demo.mp4)

_In this [demo video](.github/media/symphony-demo.mp4), Symphony monitors a Linear board for work and spawns agents to handle the tasks. The agents complete the tasks and provide proof of work: CI status, PR review feedback, complexity analysis, and walkthrough videos. When accepted, the agents land the PR safely. Engineers do not need to supervise Codex; they can manage the work at a higher level._

> [!WARNING]
> Symphony is a low-key engineering preview for testing in trusted environments.

## Running Symphony

### Requirements

Symphony works best in codebases that have adopted
[harness engineering](https://openai.com/index/harness-engineering/). Symphony is the next step --
moving from managing coding agents to managing work that needs to get done.

### Option 1. Make your own

Tell your favorite coding agent to build Symphony in a programming language of your choice:

> Implement Symphony according to the following spec:
> https://github.com/openai/symphony/blob/main/SPEC.md

### Option 2. Use our experimental reference implementation

Check out [elixir/README.md](elixir/README.md) for instructions on how to set up your environment
and run the Elixir-based Symphony implementation. You can also ask your favorite coding agent to
help with the setup:

> Set up Symphony for my repository based on
> https://github.com/openai/symphony/blob/main/elixir/README.md

---

## Changes from upstream

This fork (`dev-ale/symphony`) tracks work on top of the initial
[`openai/symphony`](https://github.com/openai/symphony) drop (commit `fa75ec6`). Changes
since then, grouped by area:

### Elixir reference implementation

- Move observability dashboard to Phoenix ([b0e0ff0](https://github.com/dev-ale/symphony/commit/b0e0ff0), #29)
- Refactor config access around an Ecto schema ([e65f5ee](https://github.com/dev-ale/symphony/commit/e65f5ee))
- Align workflow config spec with schema behavior ([8afebb3](https://github.com/dev-ale/symphony/commit/8afebb3))
- Stabilize orchestration and policy handling ([c9ec3f1](https://github.com/dev-ale/symphony/commit/c9ec3f1))
- Add a real live Linear/Codex E2E target ([b1863e8](https://github.com/dev-ale/symphony/commit/b1863e8))
- Add SSH worker support ([ff65c7c](https://github.com/dev-ale/symphony/commit/ff65c7c))
- Keep SSH retries in orchestrator ([a164593](https://github.com/dev-ale/symphony/commit/a164593), #54)
- Fix malformed JSON event from Codex message ([1f86bac](https://github.com/dev-ale/symphony/commit/1f86bac), #50)
- Configure Codex app-server model via config ([58cf97d](https://github.com/dev-ale/symphony/commit/58cf97d))

### Spec & CI

- Clarify Symphony service specification ([eaa457d](https://github.com/dev-ale/symphony/commit/eaa457d), #61)
- Pin GitHub Actions workflow references ([9e89dd9](https://github.com/dev-ale/symphony/commit/9e89dd9), #57)

### Contributors

- Alex Kotliarskyi
- Kevin Wang
- mstrautmann-oai (Mathias Strautmann)
- Drew Hintz

For the authoritative log, see `git log` or the
[commit history](https://github.com/dev-ale/symphony/commits/main).

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
