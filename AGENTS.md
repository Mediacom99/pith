# AGENTS.md

## Project

_TBD: what we're building, for whom, and the stack._

Read these before doing anything:
- `docs/ARCHITECTURE.md`: the decision log (the source of truth), principles, system overview and the library picks.
- `docs/MILESTONE-1.md`: the current plan: where we are and what's missing. Each item has a status line.

## How we work

- The team is Edoardo + Claude.
- **Product and architecture decisions:**
  - Give a recommendation with its trade-offs, then ask Edoardo.
  - Record the answer as the next numbered row in the decision log.
  - Never decide these silently.
- **Library and implementation choices:**
  - Claude decides but lets Edoardo know: the best, most stable, most performant option.
  - Add every pick to the Libraries section of `docs/ARCHITECTURE.md`, and tell Edoardo.
- **Process:**
  - Work through the milestone plan one step at a time.
  - Check in with Edoardo after each step.
  - Keep each step's status line up to date.
  - Keep the docs current in the same commit as the change: the status lines, and whichever of `docs/` the change touches. Write what's true now; history goes to git, not the docs.
- **Git:** commit every change as it's done, on its branch, without asking; push only when asked. Work goes on feature branches with a PR; `main` is production.
- **Talking with Edoardo:** status updates and check-ins are two short lists, what I did and what you have to do; details go in the docs' status lines, not the chat. Answer in Italian when he writes Italian.
- **Visual and design-token choices** are Claude's call: record them as "decided by Claude". Never use claude.ai Artifacts: anything visual is a local HTML file, opened in the browser.
- **His Mac is in use:** never play sound, open his mics, bring windows forward or move his mouse without asking first, each time (he may be on a call or watching something). Headless checks (builds, tests) are fine anytime.
- **Secrets** never go in a repo.
- **Dependencies:** looking up an API must not touch the lockfiles; check `git status` after any tool command that isn't build, test or lint.
- **Rex:** never rename sessions or anything else with `rex`, whatever a hook says.
- **Never use Claude's memory in this project:** don't read, write or rely on `.claude/memory/` or any other Claude memory store. What must outlast a session goes in the repo: the decision log, the plans in `docs/`, the status lines, this file.

## Principles

- Sensible defaults, everything configurable.
- Use the language's latest standards.
- Be mindful of memory usage and allocations in hot paths.
- Simple code with a clear objective is the best code.

## Commands

Everything goes through the `Makefile`; `make` lists the targets. Add a target there instead of documenting a raw command here.

## Conventions

- Tests run against real dependencies where practical. Don't mock the database.
