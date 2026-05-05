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
[`openai/symphony`](https://github.com/openai/symphony) drop. Notable changes since the
initial commit:

- Move Elixir observability dashboard to Phoenix (#29)
- Refactor config access around an Ecto schema
- Align workflow config spec with schema behavior
- Stabilize Symphony Elixir orchestration and policy handling
- Add a real live Linear/Codex E2E target
- Add SSH worker support to Symphony Elixir
- Fix malformed JSON event from Codex message (#50)
- Keep SSH retries in orchestrator (#54)
- Pin GitHub Actions workflow references (#57)
- Clarify Symphony service specification (#61)
- Configure Codex app-server model via config

### Contributors

- Alex Kotliarskyi
- Kevin Wang
- mstrautmann-oai
- Drew Hintz

For the authoritative log, see `git log` or the
[commit history](https://github.com/dev-ale/symphony/commits/main).

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
