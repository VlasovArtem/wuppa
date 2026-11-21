# Wuppa — POC Plan

Nov 8, 2026 · @Artem Vlasov

## Plan in brief

In 6 weeks we find out whether real families will use Wuppa's core loop: 4 weeks to build a simple working app, then 2 weeks of 3–5 families using it at home.

|  |  |
| --- | --- |
| Duration | 6 weeks: build weeks 1–4, family testing weeks 5–6 |
| Team | 1 backend developer (Go), 1 mobile developer, 1 designer part-time (week 1 mostly), you as product owner |
| Stack | Go API + PostgreSQL; one mobile app for iOS and Android (Flutter assumed; see Technical spec) |
| Not in the POC | Payments, AI, web dashboard, scoreboards, stats, multiple guardians, polish |

**How to read this plan**

- Every task has an ID: `SET` = setup, `BE` = backend, `MOB` = mobile, `DES` = design, `QA` = testing
- Estimates are in working days for one person
- The **Technical spec** tab holds what all tasks share: stack, data model, API, rules
- The **Task specs** tab explains each task: what to build, how, and when it is done

## What we build

One app with two modes. The POC is done when a family can go through these steps without help:

1. **Parent signs up** with email and password; a family is created automatically.
2. **Parent adds a kid**: nickname, avatar (from 8 presets), age band.
3. **Parent pairs the kid's device**: the app shows a 6-digit code, the kid types it on their device.
4. **Parent creates a task**: title, points, how often per day or week, which kid.
5. **Kid sees the task** and taps "Done".
6. **Parent gets a push**, opens the pending list, approves or rejects.
7. **Kid's points go up**; the streak and badges update.
8. **Parent creates rewards** (e.g. "Movie night — 100 points").
9. **Kid requests a reward**; points are held; parent confirms (points spent) or refuses (points back).

If the family shares one phone, the parent can switch it to kid view; leaving kid view needs the parent's 4-digit PIN.

## Timeline

&#91;embedded content: POC timeline · 6 weeks by owner\]

Each cell lists the task IDs for that week; look them up in the table below or in the Task specs tab.

## All tasks

34 tasks: backend \~18 days, mobile \~17 days, design 4 days, plus family testing. Mobile builds against the OpenAPI spec and mock data, so it never waits long for the backend.

| ID | Task | Owner | Days | Week | Depends on |
| --- | --- | --- | --- | --- | --- |
| SET-01 | Repositories, CI, linting | Backend | 1 | 1 | — |
| SET-02 | Local environment: Docker Compose, PostgreSQL, migrations | Backend | 0.5 | 1 | SET-01 |
| SET-03 | Mobile framework decision and app skeleton | Mobile | 2 | 1 | — |
| DES-01 | User flow and wireframes (\~12 screens) | Design | 2 | 1 | — |
| DES-02 | Visual basics: colours, type, 8 avatars, 5 badges | Design | 2 | 1–2 | DES-01 |
| BE-01 | API skeleton, conventions, OpenAPI draft | Backend | 1.5 | 1 | SET-02 |
| BE-02 | Database schema v1 | Backend | 1 | 1 | SET-02 |
| BE-13 | Test environment in the EU, deploy pipeline | Backend | 1 | 1 | BE-01 |
| MOB-01 | App shell, navigation, theme, API client | Mobile | 2 | 1 | SET-03, BE-01 |
| BE-03 | Guardian sign-up, login, tokens | Backend | 2 | 2 | BE-01, BE-02 |
| BE-04 | Family and kid profiles | Backend | 1 | 2 | BE-03 |
| BE-05 | Kid device pairing | Backend | 1.5 | 2 | BE-04 |
| MOB-02 | Sign-up and login screens | Mobile | 1.5 | 2 | MOB-01, BE-03 |
| MOB-03 | Family setup and add kid | Mobile | 1 | 2 | MOB-02, BE-04 |
| MOB-04 | Pairing on both devices | Mobile | 1.5 | 2 | MOB-03, BE-05 |
| BE-06 | Tasks with repeat limits | Backend | 1.5 | 3 | BE-04 |
| BE-07 | Mark task done (completions) | Backend | 1 | 3 | BE-06 |
| BE-08 | Approve / reject and ledger | Backend | 1.5 | 3 | BE-07 |
| BE-09 | Balance and points history | Backend | 0.5 | 3 | BE-08 |
| MOB-05 | Kid view on a shared phone, PIN lock | Mobile | 1 | 3 | MOB-03 |
| MOB-06 | Create and edit tasks | Mobile | 1 | 3 | BE-06 |
| MOB-07 | Kid task list and "Done" | Mobile | 1.5 | 3 | BE-07 |
| MOB-08 | Pending approvals list | Mobile | 1 | 3 | BE-08 |
| BE-10 | Push notifications (FCM) | Backend | 1 | 4 | BE-07 |
| BE-11 | Rewards and redemptions | Backend | 1.5 | 4 | BE-09 |
| BE-12 | Streaks and badges | Backend | 1 | 4 | BE-08 |
| MOB-09 | Push and deep links | Mobile | 1 | 4 | BE-10 |
| MOB-10 | Points, reward shop, requests | Mobile | 1.5 | 4 | BE-11 |
| MOB-11 | Streak and badges display | Mobile | 0.5 | 4 | BE-12 |
| MOB-12 | Test builds: TestFlight and Play internal testing | Mobile | 1 | 4 | all MOB |
| QA-01 | End-to-end test, seed data, bug fixing | Both | 1 each | 4 | all |
| TST-01 | Onboard 3–5 families | Product owner | — | 5 | MOB-12 |
| TST-02 | Support, logs, fixes | Both devs | — | 5–6 | TST-01 |
| TST-03 | Interviews and go / no-go | Product owner | — | 6 | TST-02 |

## Family testing (weeks 5–6)

The build is only useful if real families use it without us in the room; these two weeks tell us whether to continue to the MVP.

**Week 5 — start**

- [ ] Invite 3–5 families with at least one kid aged 6–12 (TestFlight / Play internal testing links)
- [ ] Watch one family set up live (video call is fine); note every point where they hesitate
- [ ] Give every family a short guide: install, pair, create 3 tasks and 2 rewards
- [ ] Developers watch logs and crash reports daily; fix blockers within a day

**Week 6 — learn**

- [ ] Pull usage numbers per family (see exit gate)
- [ ] 20-minute interview with each guardian; 5 minutes with each kid if the parent agrees
- [ ] Write down: which tasks and rewards families created, points they chose, what they asked for
- [ ] Go / no-go meeting at the end of week 6

**Interview questions**

- Would you keep using it next week? Why or why not?
- What was annoying or confusing?
- Did approving tasks feel like work?
- What did your kid say about it?
- What is missing before you would pay for it?

## Exit gate

Go to the MVP only if most of these hold; the targets are proposals, adjust them before week 5.

| Check | Target (proposal) | How we measure |
| --- | --- | --- |
| Families active in week 2 of testing | At least 3 of 5 | At least one approved task per day on 4+ days |
| Kids open the app on their own | Most days | App opens on the kid device (server log of kid API calls) |
| Approval speed | Most tasks approved within 24 h | completed\_at → decided\_at |
| Rewards used | Every active family redeemed at least once | Redemptions table |
| Would keep using it | Most guardians say yes | Interviews |
| Setup without help | Most families | Live setup session + interviews |

## Risks

| Risk | What we do |
| --- | --- |
| Mobile waits for backend | Agree on the OpenAPI spec in week 1; mobile uses mocks |
| Parents forget to approve | Push on every completion (BE-10); ask about reminders in interviews |
| Pairing confuses parents | Watch the live setup; simplify before MVP |
| Store test builds take time | Set up TestFlight and Play internal testing in week 1, not week 4 |
| Scope creep | Anything not in the task list goes to the MVP backlog |
