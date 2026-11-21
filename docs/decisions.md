# Decisions

Lasting decisions made during the steps, newest last. One line each: date, step, decision, why.

- 2026-11-21 · plan · Languages EN + RU; one shared family with guardian invites; kid view on a shared phone pairs the phone as a kid device; password reset by emailed code. See docs/poc-plan.md section 10.
- 2026-11-21 · SET-01 · Make targets wrap scripts (api/scripts/*.sh) that own the 0/1/2 exit codes and the RESULT last line, because make exits 2 on any failed recipe. · keeps the agent contract exact.
- 2026-11-21 · plan · Steps run with the tdd-step workflow: Opus plans, Sonnet implements test-first, one PR per step.
