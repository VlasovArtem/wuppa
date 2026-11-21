# Wuppa POC — specification and implementation plan

Status legend: `[ ]` not started · `[x]` done. Claude Code ticks a task only when every "Done when" check passes.

## 1. Goal

Build the smallest working version of Wuppa's core loop and put it in the hands of 3–5 real families for two weeks:

1. Guardian signs up (email + password); a family is created.
2. Guardian adds a kid (nickname, preset avatar, age band).
3. Guardian pairs the kid's device with a 6-digit code.
4. Guardian creates a task: title, points, max times per day or week, which kid.
5. Kid sees the task and taps "Done".
6. Guardian gets a push, approves or rejects.
7. Kid's points go up; streak and badges update.
8. Guardian creates rewards (e.g. "Movie night — 100 points").
9. Kid requests a reward; points are held; guardian approves (points spent) or refuses (points returned).

On a shared phone, the guardian can switch to "kid view" for one kid; there the kid ticks tasks and requests rewards just like on their own device; leaving it requires a 4-digit PIN.

A family can have several guardians (e.g. both parents). A guardian invites another one with an invite code; all guardians of a family have the same rights and see the same kids, tasks, points and rewards.

### Out of scope (do not build)

Payments, AI, web dashboard, scoreboards, statistics, photo proof, task schedules beyond day/week limits, languages other than English and Russian, polished design.

## 2. Architecture

```
Flutter app (iOS/Android) ──HTTPS/JSON──> Go API ──> PostgreSQL
                                             └────> FCM (push)
```

- One Go binary, stateless, configured by environment variables.
- One Flutter app with two route trees: guardian and kid.
- All rules (limits, points, permissions) are enforced in the API.
- Languages: English and Russian. The app follows the device language (fallback English). The API keeps the guardian's `locale` (for emails) and each push token's `locale` (for push texts).

### Configuration (env vars)

| Variable | Example | Notes |
| --- | --- | --- |
| `PORT` | `8080` | |
| `DATABASE_URL` | `postgres://wuppa:wuppa@localhost:5432/wuppa?sslmode=disable` | |
| `JWT_SECRET` | 32+ random bytes, base64 | HS256 signing key |
| `FCM_CREDENTIALS_FILE` | `/secrets/fcm.json` | Optional; push disabled with a warning log if empty |
| `FCM_PROJECT_ID` | `wuppa-poc` | |
| `LOG_LEVEL` | `info` | |
| `SMTP_URL` | `smtp://user:pass@smtp.example.eu:587` | Locally `smtp://localhost:1025` (Mailpit). Empty → reset emails disabled with a warning log |
| `MAIL_FROM` | `Wuppa <no-reply@example.eu>` | |
| `TRUSTED_PROXY_HOPS` | `0` | Number of proxies in front of the API; used to read the client IP from `X-Forwarded-For` |

## 3. Authentication and roles

| Caller | Credential | Lifetime | Allowed |
| --- | --- | --- | --- |
| Guardian | JWT access token (HS256), claims `sub` (guardian id), `fam` (family id), `role: "guardian"` | 15 min | All endpoints for their own family |
| Guardian | Refresh token: 32 random bytes, base64url; DB stores SHA-256 | 30 days, rotated on every use | `POST /v1/auth/refresh`, `/logout` |
| Kid device | Opaque token: 32 random bytes, base64url, prefix `kd_`; DB stores SHA-256 | No expiry; revocable | Kid endpoints only |

- Header: `Authorization: Bearer <token>`. Tokens starting with `kd_` are kid tokens; all others are parsed as JWT.
- Middleware `RequireGuardian` and `RequireKid` put `{guardianID|kidID, familyID}` in the request context.
- Kid token on a guardian endpoint → `403 forbidden`. Guardian token on a kid endpoint (`/v1/me/...`) → `403 forbidden`.
- Resource of another family → `404 not_found`.
- Refresh token reuse: a token rotated **less than 10 s ago** used again → `401 unauthorized` without revoking (a parallel refresh from the same app); rotated longer ago → revoke all refresh tokens of that guardian, `401 unauthorized`.
- Passwords: min 10 characters; argon2id (memory 64 MiB, iterations 3, parallelism 2, salt 16 bytes, key 32 bytes); store encoded as `$argon2id$v=19$m=65536,t=3,p=2$<salt>$<hash>`.

## 4. API conventions

- Base path `/v1`; JSON only; request body limit 1 MB; unknown JSON fields rejected (`DisallowUnknownFields`).
- Timestamps RFC 3339 in UTC; IDs UUID v7 strings.
- Lists: `{"items": [...]}`; no pagination in the POC.
- Errors: `{"error": {"code": "...", "message": "..."}}`.
- `Idempotency-Key` header (UUID) supported on `POST /v1/tasks/{id}/complete` and `POST /v1/rewards/{id}/redeem`, stored in `idempotency_keys` keyed by (key, caller, method + request path — the path includes the task / reward id):
  - first `INSERT ... ON CONFLICT DO NOTHING` a row without a response; if the row already exists with a response from the last 24 h → return that response; if it has no response yet → `409 request_in_progress`;
  - after handling, store status and body (4xx results too); on a 5xx delete the row so the client can retry.
- Client IP (rate limits): the socket address; with `TRUSTED_PROXY_HOPS=n` the n-th address from the right of `X-Forwarded-For`.

### Error codes

| HTTP | Code | When |
| --- | --- | --- |
| 400 | `invalid_request` | Malformed JSON, unknown fields |
| 422 | `validation_failed` | Field rules broken; `message` names the field |
| 401 | `unauthorized` | Missing / invalid / expired token |
| 401 | `invalid_credentials` | Wrong email or password |
| 403 | `forbidden` | Wrong role for the endpoint |
| 404 | `not_found` | Missing or belongs to another family |
| 409 | `email_taken` | Sign-up with an existing email |
| 409 | `already_decided` | Approve / reject / refuse something not pending |
| 409 | `limit_reached` | Task done the maximum times this period |
| 409 | `not_enough_points` | Redeem with too few points |
| 409 | `request_in_progress` | Same `Idempotency-Key` is still being processed |
| 409 | `task_inactive` / `reward_inactive` | Acting on a paused item |
| 410 | `invalid_code` | Pairing, invite or password-reset code wrong, used or expired |
| 429 | `rate_limited` | Too many attempts |
| 500 | `internal` | Anything else (details only in logs) |

## 5. Data model

Create these as goose migrations in `api/migrations/` (one file per group is fine).

```sql
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE families (
  id         uuid PRIMARY KEY,
  name       text NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
  timezone   text NOT NULL DEFAULT 'Europe/Berlin',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE guardians (
  id            uuid PRIMARY KEY,
  family_id     uuid NOT NULL REFERENCES families(id),
  email         citext NOT NULL UNIQUE,
  password_hash text NOT NULL,
  display_name  text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 40),
  locale        text NOT NULL DEFAULT 'en' CHECK (locale IN ('en','ru')),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
  id          uuid PRIMARY KEY,
  guardian_id uuid NOT NULL REFERENCES guardians(id),
  token_hash  bytea NOT NULL UNIQUE,
  expires_at  timestamptz NOT NULL,
  rotated_at  timestamptz,
  revoked_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE guardian_invites (
  code       char(8) PRIMARY KEY,
  family_id  uuid NOT NULL REFERENCES families(id),
  created_by uuid NOT NULL REFERENCES guardians(id),
  expires_at timestamptz NOT NULL,
  used_at    timestamptz,
  used_by    uuid REFERENCES guardians(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE password_resets (
  id          uuid PRIMARY KEY,
  guardian_id uuid NOT NULL REFERENCES guardians(id),
  code_hash   bytea NOT NULL,             -- SHA-256 of the 6-digit code
  attempts    int  NOT NULL DEFAULT 0,
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE kids (
  id         uuid PRIMARY KEY,
  family_id  uuid NOT NULL REFERENCES families(id),
  nickname   text NOT NULL CHECK (length(nickname) BETWEEN 1 AND 20),
  avatar     text NOT NULL CHECK (avatar IN ('fox','bear','owl','cat','dog','rabbit','panda','frog')),
  age_band   text NOT NULL CHECK (age_band IN ('4-6','7-9','10-12','13-15')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE pairing_codes (
  code       char(6) PRIMARY KEY,
  kid_id     uuid NOT NULL REFERENCES kids(id),
  expires_at timestamptz NOT NULL,
  used_at    timestamptz
);

CREATE TABLE kid_devices (
  id         uuid PRIMARY KEY,
  kid_id     uuid NOT NULL REFERENCES kids(id),
  token_hash bytea NOT NULL UNIQUE,
  platform   text NOT NULL CHECK (platform IN ('ios','android')),
  shared       boolean NOT NULL DEFAULT false,  -- kid view on a guardian's phone
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz,
  revoked_at   timestamptz
);

CREATE TABLE push_tokens (
  id         uuid PRIMARY KEY,
  owner_type text NOT NULL CHECK (owner_type IN ('guardian','kid')),
  owner_id   uuid NOT NULL,
  token      text NOT NULL UNIQUE,
  platform   text NOT NULL CHECK (platform IN ('ios','android')),
  locale     text NOT NULL DEFAULT 'en' CHECK (locale IN ('en','ru')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE tasks (
  id             uuid PRIMARY KEY,
  family_id      uuid NOT NULL REFERENCES families(id),
  kid_id         uuid NOT NULL REFERENCES kids(id),
  title          text NOT NULL CHECK (length(title) BETWEEN 1 AND 80),
  points         int  NOT NULL CHECK (points BETWEEN 1 AND 1000),
  max_per_period int  NOT NULL CHECK (max_per_period BETWEEN 1 AND 20),
  period         text NOT NULL CHECK (period IN ('day','week')),
  active         boolean NOT NULL DEFAULT true,
  created_by     uuid NOT NULL REFERENCES guardians(id),
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE completions (
  id         uuid PRIMARY KEY,
  task_id    uuid NOT NULL REFERENCES tasks(id),
  kid_id     uuid NOT NULL REFERENCES kids(id),
  points     int  NOT NULL,             -- task points at completion time
  status     text NOT NULL CHECK (status IN ('pending','approved','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_by uuid REFERENCES guardians(id),
  decided_at timestamptz
);
CREATE INDEX completions_task_created_idx ON completions (task_id, created_at);
CREATE INDEX completions_kid_status_idx  ON completions (kid_id, status);

CREATE TABLE ledger_entries (
  id         uuid PRIMARY KEY,
  kid_id     uuid NOT NULL REFERENCES kids(id),
  amount     int  NOT NULL CHECK (amount <> 0),
  reason     text NOT NULL CHECK (reason IN ('task_approved','redemption','refund')),
  ref_id     uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (reason, ref_id)
);
CREATE INDEX ledger_kid_created_idx ON ledger_entries (kid_id, created_at);

CREATE TABLE rewards (
  id         uuid PRIMARY KEY,
  family_id  uuid NOT NULL REFERENCES families(id),
  title      text NOT NULL CHECK (length(title) BETWEEN 1 AND 60),
  cost       int  NOT NULL CHECK (cost BETWEEN 1 AND 100000),
  active     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE redemptions (
  id         uuid PRIMARY KEY,
  reward_id  uuid NOT NULL REFERENCES rewards(id),
  kid_id     uuid NOT NULL REFERENCES kids(id),
  cost       int  NOT NULL,             -- cost at request time
  status     text NOT NULL CHECK (status IN ('requested','approved','refused')),
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_by uuid REFERENCES guardians(id),
  decided_at timestamptz
);

CREATE TABLE kid_badges (
  kid_id    uuid NOT NULL REFERENCES kids(id),
  badge     text NOT NULL CHECK (badge IN ('first_task','ten_tasks','streak_3','streak_7','first_reward')),
  earned_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (kid_id, badge)
);

CREATE TABLE idempotency_keys (
  key         uuid NOT NULL,
  caller_id   uuid NOT NULL,            -- guardian id or kid device id
  endpoint    text NOT NULL,            -- method + path, e.g. 'POST /v1/tasks/<id>/complete'
  status_code int,                      -- NULL while in progress
  response    jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (key, caller_id, endpoint)
);
```

## 6. Business rules

Put these in `api/internal/domain/` as pure functions where possible, with unit tests.

1. **Period start** — `PeriodStart(now time.Time, period string, tz *time.Location) time.Time`:
   - `day` → local midnight of `now` in `tz`.
   - `week` → local Monday 00:00 of the week containing `now` in `tz`.
   - Return in UTC. Must be correct across daylight-saving changes.
2. **Repeat limit** — count completions of the task with `status IN ('pending','approved')` and `created_at >= PeriodStart`. If `count >= max_per_period` → `limit_reached`. Rejected completions do not count. `remaining = max_per_period - count`.
3. **Mark done** — one transaction: `SELECT ... FROM tasks WHERE id=$1 FOR UPDATE`, check active + ownership, count (rule 2), insert `pending` with `points = task.points`.
4. **Balance** = `SUM(amount)` of the kid's ledger entries (0 if none). Never stored.
5. **Approve completion** — one transaction: `UPDATE completions SET status='approved', decided_by=$g, decided_at=now() WHERE id=$1 AND status='pending'`; 0 rows → `already_decided`; insert ledger `+completion.points`, reason `task_approved`, `ref_id = completion.id`; then run badge check (rule 9).
6. **Reject completion** — same update with `status='rejected'`; no ledger entry.
7. **Redeem** — one transaction: `SELECT ... FROM kids WHERE id=$1 FOR UPDATE`; reward must be active and in the same family; compute balance; if `balance < cost` → `not_enough_points`; insert redemption (`requested`, `cost` = current reward cost); insert ledger `-cost`, reason `redemption`, `ref_id = redemption.id`.
8. **Decide redemption** — approve: `requested → approved` (no ledger change), then badge check. Refuse: `requested → refused` and insert ledger `+cost`, reason `refund`, `ref_id = redemption.id`. Not `requested` → `already_decided`.
9. **Badges** — after every approval and every redemption approval, insert with `ON CONFLICT DO NOTHING`:
   - `first_task`: ≥ 1 approved completion
   - `ten_tasks`: ≥ 10 approved completions
   - `streak_3`: streak ≥ 3
   - `streak_7`: streak ≥ 7
   - `first_reward`: ≥ 1 approved redemption
   Return newly earned badges so the push / UI can celebrate.
10. **Streak** — consecutive local days (family tz) with ≥ 1 approved completion, where the day is the completion's `created_at` date. Start from today if today has one, otherwise from yesterday; count backwards until a day has none.
11. **Pairing code** — 6 digits from `crypto/rand` (000000–999999), unique among unused unexpired codes; expires in 10 minutes; creating a new code deletes unused codes for the same kid and every code that expired more than a day ago; on a primary-key conflict generate again (up to 5 tries, then `500 internal`).
12. **Password reset** — `request`: always `202` (no hint whether the email exists); if it exists, delete the guardian's unused codes, create a 6-digit code (`crypto/rand`), store its SHA-256, expiry 15 min, and send the email in the guardian's `locale` after the response (so timing does not reveal the email). Rate limit 3 / hour per email and 10 / hour per IP. `confirm`: one transaction; take the guardian's newest unused, unexpired code; wrong code → `attempts + 1`, at 5 the code is dead; every failure → `410 invalid_code`; success → validate the new password (≥ 10), update the hash, mark the code used, revoke all refresh tokens, issue new tokens.
13. **Kid last seen** — `RequireKid` sets `kid_devices.last_seen_at = now()` when it is NULL or older than 5 minutes (at most one write per device per 5 min). Used to measure whether kids open the app on their own.
14. **Guardian invite** — 8 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (`crypto/rand`), single use, expires in 72 h; same clean-up and retry as rule 11. Sign-up with `invite_code`: one transaction, `SELECT ... FOR UPDATE` the invite; unused and unexpired, else `410 invalid_code`; create the guardian in the invite's family; mark the invite used. A guardian belongs to exactly one family; removing a guardian is out of scope.
15. **Shared device** — `POST /v1/pair` with `shared: true` marks the device as kid view on a guardian's phone. The app registers no kid push token for shared devices.

## 7. Endpoints

All bodies are JSON. "G" = guardian token, "K" = kid token.

| Method | Path | Auth | Request | Response | Task |
| --- | --- | --- | --- | --- | --- |
| GET | `/healthz` | — | — | `200 {"status":"ok"}` (checks DB) | BE-01 |
| POST | `/v1/auth/signup` | — | `{email, password, display_name, locale}` + either `{family_name, timezone}` (new family) or `{invite_code}` (join) | `201 Tokens` | BE-03 |
| POST | `/v1/auth/login` | — | `{email, password}` | `200 Tokens` | BE-03 |
| POST | `/v1/auth/refresh` | — | `{refresh_token}` | `200 Tokens` | BE-03 |
| POST | `/v1/auth/logout` | G | `{refresh_token}` | `204` | BE-03 |
| POST | `/v1/auth/password-reset/request` | — | `{email}` | `202` (always) | BE-14 |
| POST | `/v1/auth/password-reset/confirm` | — | `{email, code, new_password}` | `200 Tokens` | BE-14 |
| GET | `/v1/family` | G | — | `200 Family` | BE-04 |
| POST | `/v1/family/invites` | G | — | `201 {code, expires_at}` | BE-15 |
| POST | `/v1/kids` | G | `{nickname, avatar, age_band}` | `201 Kid` | BE-04 |
| PATCH | `/v1/kids/{id}` | G | any of `{nickname, avatar, age_band}` | `200 Kid` | BE-04 |
| POST | `/v1/kids/{id}/pairing-code` | G | — | `201 {code, expires_at}` | BE-05 |
| GET | `/v1/kids/{id}/devices` | G | — | `200 {items: [Device]}` | BE-05 |
| DELETE | `/v1/kids/{id}/devices/{deviceId}` | G | — | `204` | BE-05 |
| POST | `/v1/pair` | — | `{code, platform, shared?}` | `201 {device_token, kid: Kid}` | BE-05 |
| GET | `/v1/me` | K | — | `200 Kid` | BE-05 |
| POST | `/v1/tasks` | G | `{kid_id, title, points, max_per_period, period}` | `201 Task` | BE-06 |
| PATCH | `/v1/tasks/{id}` | G | any of `{title, points, max_per_period, period, active}` | `200 Task` | BE-06 |
| GET | `/v1/tasks?kid_id=` | G | — | `200 {items: [Task]}` | BE-06 |
| GET | `/v1/me/tasks` | K | — | `200 {items: [KidTask]}` (active only) | BE-06 |
| POST | `/v1/tasks/{id}/complete` | K | — (+ `Idempotency-Key`) | `201 Completion` | BE-07 |
| GET | `/v1/completions?status=pending` | G | — | `200 {items: [CompletionView]}` | BE-08 |
| POST | `/v1/completions/{id}/approve` | G | — | `200 {completion, new_badges: []}` | BE-08 |
| POST | `/v1/completions/{id}/reject` | G | — | `200 Completion` | BE-08 |
| GET | `/v1/me/points` | K | — | `200 Points` | BE-09 |
| GET | `/v1/kids/{id}/points` | G | — | `200 Points` | BE-09 |
| GET | `/v1/rewards` | G or K | — | `200 {items: [Reward]}` (kid: active only) | BE-11 |
| POST | `/v1/rewards` | G | `{title, cost}` | `201 Reward` | BE-11 |
| PATCH | `/v1/rewards/{id}` | G | any of `{title, cost, active}` | `200 Reward` | BE-11 |
| POST | `/v1/rewards/{id}/redeem` | K | — (+ `Idempotency-Key`) | `201 Redemption` | BE-11 |
| GET | `/v1/me/redemptions` | K | — | `200 {items: [Redemption]}` (last 20) | BE-11 |
| GET | `/v1/redemptions?status=requested` | G | — | `200 {items: [RedemptionView]}` | BE-11 |
| POST | `/v1/redemptions/{id}/approve` | G | — | `200 {redemption, new_badges: []}` | BE-11 |
| POST | `/v1/redemptions/{id}/refuse` | G | — | `200 Redemption` | BE-11 |
| GET | `/v1/me/progress` | K | — | `200 Progress` | BE-12 |
| GET | `/v1/kids/{id}/progress` | G | — | `200 Progress` | BE-12 |
| POST | `/v1/push-tokens` | G or K | `{token, platform, locale}` | `204` | BE-10 |

### Schemas

```jsonc
// Tokens
{ "access_token": "eyJ...", "access_expires_at": "2026-12-01T10:15:00Z",
  "refresh_token": "b64url...", "guardian": { "id": "...", "display_name": "Anna", "email": "anna@example.com", "locale": "en" } }

// Family
{ "id": "...", "name": "Schmidt", "timezone": "Europe/Berlin",
  "guardians": [ { "id": "...", "display_name": "Anna" } ], "kids": [Kid] }

// Kid
{ "id": "...", "nickname": "Leo", "avatar": "fox", "age_band": "7-9" }

// Device
{ "id": "...", "platform": "android", "shared": false, "created_at": "...", "last_seen_at": "..." }

// Task (guardian view)
{ "id": "...", "kid_id": "...", "title": "Tidy your room", "points": 20,
  "max_per_period": 1, "period": "day", "active": true, "created_at": "..." }

// KidTask (kid view)
{ "id": "...", "title": "Tidy your room", "points": 20, "max_per_period": 1,
  "period": "day", "remaining": 0, "pending": 1 }

// Completion
{ "id": "...", "task_id": "...", "kid_id": "...", "status": "pending", "created_at": "..." }

// CompletionView (guardian pending list)
{ "id": "...", "status": "pending", "created_at": "...",
  "kid": { "id": "...", "nickname": "Leo", "avatar": "fox" },
  "task": { "id": "...", "title": "Tidy your room", "points": 20 } }   // points = completion.points

// Points
{ "balance": 140, "entries": [ { "id": "...", "amount": 20, "reason": "task_approved",
  "title": "Tidy your room", "created_at": "..." } ] }   // last 50, newest first

// Reward
{ "id": "...", "title": "Movie night", "cost": 100, "active": true }

// Redemption
{ "id": "...", "reward_id": "...", "kid_id": "...", "title": "Movie night", "cost": 100,
  "status": "requested", "created_at": "..." }

// RedemptionView = Redemption + "kid": { id, nickname, avatar }

// Progress
{ "streak": 4, "badges": [ { "badge": "first_task", "earned_at": "..." } ] }
```

### Push events (BE-10)

| Event | Recipients | Title / body (EN) | Title / body (RU) | Data payload |
| --- | --- | --- | --- | --- |
| Completion created | All guardians of the family | "{nickname} finished a task" / "{task title} — tap to check" | "{nickname}: задание выполнено" / "{task title} — нажмите, чтобы проверить" | `{type: "completion", id}` |
| Completion approved | The kid's devices | "+{points} points!" / "{task title} was approved" | "Очки: +{points}!" / "Задание «{task title}» одобрено" | `{type: "approved", id}` |
| Completion rejected | The kid's devices | "Not yet: {task title}" / "Ask your parent what to fix" | "Пока нет: {task title}" / "Спроси у родителей, что поправить" | `{type: "rejected", id}` |
| Redemption requested | All guardians | "{nickname} wants a reward" / "{reward title} — {cost} points" | "{nickname} хочет награду" / "{reward title} — стоимость: {cost}" | `{type: "redemption", id}` |
| Redemption approved | The kid's devices | "You got {reward title}!" / "Enjoy!" | "Награда «{reward title}» твоя!" / "Наслаждайся!" | `{type: "reward_approved", id}` |
| Redemption refused | The kid's devices | "{reward title}: not now" / "Your {cost} points are back" | "«{reward title}»: не сейчас" / "Очки вернулись: {cost}" | `{type: "reward_refused", id}` |

Texts are chosen by the push token's `locale` (fallback `en`); the RU texts avoid number and gender forms on purpose.

Send after the transaction commits, in a goroutine with a 5 s timeout; never fail the request because of push. Delete tokens FCM reports as `UNREGISTERED`.

## 8. App screens

| Screen | Mode | Purpose |
| --- | --- | --- |
| Welcome | — | "I'm a parent" / "I'm a kid" |
| Sign up / Log in | Guardian | Email + password forms; "Forgot password?" link; "I have an invite code" on sign-up |
| Forgot password | Guardian | Email → 6-digit code from the email + new password |
| Add / edit kid | Guardian | Nickname, avatar grid (8), age band chips |
| Guardian home | Guardian | Kids list with points; pending approvals count; reward requests count |
| Kid detail | Guardian | Tasks of the kid, "Connect device", devices, "Hand phone to {kid}" |
| Pairing code | Guardian | Big 6-digit code + countdown + "New code" |
| Task form | Guardian | Title (+ quick picks), points (5/10/20/50 or custom), times per day/week |
| Approvals | Guardian | Pending list grouped by kid, "OK" / "Not yet" |
| Rewards | Guardian | List + add / edit / pause; requests with "Give" / "Not now" |
| Settings | Guardian | Set / change PIN, guardians list, "Invite a parent" (code, copy, share), log out |
| Enter code | Kid | 6 digit boxes |
| Kid home | Kid | Avatar + "Hi, {nickname}!", points, streak, badges, task cards with "Done" |
| Reward shop | Kid | Cards with cost and progress bar; "Get it" |
| Points history | Kid | Balance + list |
| PIN lock | Kid view on shared phone | 4-digit PIN to exit; "Forgot PIN?" → guardian password |

Assets (in `app/assets/`): `avatars/{fox,bear,owl,cat,dog,rabbit,panda,frog}.png`, `badges/{first_task,ten_tasks,streak_3,streak_7,first_reward}.png`. Until the designer delivers them, use coloured circles with the first letter as placeholders.

---

## 9. Tasks

Tasks are ordered for one implementer and run with the `tdd-step` workflow (see "Step workflow" in `CLAUDE.md`): `plan: opus` = Opus writes `plan.md` and the user approves it; `plan: direct` = the step session plans from the issue. `review:` is the review level. **[Human]** marks steps Claude Code cannot do (accounts, keys, devices); stop and ask the user when you reach one. All of them are collected in [issue #1](https://github.com/VlasovArtem/wuppa/issues/1).

### Phase 0 — Foundations

#### [x] SET-01 · Monorepo, CI, linting · [#2](https://github.com/VlasovArtem/wuppa/issues/2) · plan: direct · review: fast

- Create `api/` and `app/` folders, root `README.md`, `.gitignore` (Go, Flutter, IDE, `.env`); delete the IDE sample `main.go`, the root `go.mod` and the stray `gitignore.gitignore`. Go module: `github.com/VlasovArtem/wuppa/api`.
- GitHub Actions:
  - `api.yml` (on changes under `api/**`): setup Go, start PostgreSQL service, `make lint`, `make sqlc` + check no diff, `make migrate`, `make test`.
  - `app.yml` (on changes under `app/**`): setup Flutter stable, `flutter analyze`, `flutter test`.
- `api/.golangci.yml` with `govet`, `staticcheck`, `errcheck`, `gosec`, `revive`.

Done when:
- [x] Both workflows exist and are valid YAML; a deliberate lint error makes `make lint` fail locally.

#### [ ] SET-02 · Local environment · [#3](https://github.com/VlasovArtem/wuppa/issues/3) · plan: opus · review: standard

- `api/docker-compose.yml`: `postgres:16`, user/password/db `wuppa`, port 5432, named volume; `axllent/mailpit` (SMTP 1025, web UI 8025) for password-reset emails.
- `api/Makefile` targets: `db-up`, `db-down`, `migrate`, `migrate-down`, `seed`, `run`, `test-unit`, `test-integration`, `test` (both), `lint`, `check` (lint + test), `sqlc`, `openapi-lint`.
- Test split: integration tests carry `//go:build integration` and use the real database; everything else is a unit test. `test-integration` starts the database itself if needed (`db-up`, waits until healthy, migrates a separate `wuppa_test` database) and runs with `-p 1`.
- Agent-friendly output for `test-unit`, `test-integration` and `lint`, following the contract in `CLAUDE.md` ("Step workflow"): narrowing with `PKG=` and `RUN=`, full log in `api/.out/<target>.log`, a short failure summary, one final `RESULT:` line, exit codes 0 / 1 / 2. The test summary comes from a small standard-library program `api/tools/testsummary` that reads `go test -json` (no new dependency).
- `api/.env.example` with all variables from section 2.

Done when:
- [ ] `make db-up && make migrate` succeeds on a clean machine (after BE-02 exists, re-check).
- [ ] `api/tools/testsummary` has unit tests (pass, fail with file:line, panic, build error, 60-line cap).
- [ ] A deliberately failing test makes `make test-unit` print only the failing test with its file:line and message, end with `RESULT: FAIL ...` and exit 1; with the database down, `make test-integration` brings it up by itself; an unknown `PKG` exits 2.

#### [ ] BE-01 · API skeleton, conventions, OpenAPI draft · [#4](https://github.com/VlasovArtem/wuppa/issues/4) · plan: opus · review: standard

- `cmd/api/main.go`: load config, open pgx pool, build router, graceful shutdown on SIGTERM (10 s).
- Middleware: request ID (`X-Request-ID`), slog JSON request log (method, path, status, duration, request id — no bodies), panic recovery → `500 internal`, 10 s timeout.
- `internal/http/respond.go`: `JSON(w, status, v)`, `Error(w, status, code, message)`, `Decode(r, &v)` (1 MB limit, unknown fields rejected → `400 invalid_request`).
- `GET /healthz` pings the DB.
- `openapi.yaml` (OpenAPI 3.1) covering every endpoint and schema in section 7; `make openapi-lint` uses `npx @redocly/cli lint`.

Done when:
- [ ] `make run` then `curl localhost:8080/healthz` → `{"status":"ok"}`.
- [ ] Tests for `Decode` (unknown field, too large) and `Error` output shape.
- [ ] `make openapi-lint` passes.

#### [ ] BE-02 · Database schema v1 · [#5](https://github.com/VlasovArtem/wuppa/issues/5) · plan: direct · review: standard

- Migrations with the exact SQL from section 5 (split by group; each has a working `-- +goose Down`).
- `sqlc.yaml` (engine postgresql, pgx/v5, emit JSON tags off, queries in `internal/db/queries/`).
- First queries: `CreateFamily`, `CreateGuardian`, `GetGuardianByEmail`, `GetGuardianByID`.
- Test helper `testdb.New(t)` that creates a fresh schema per test (or truncates all tables) so tests are independent.

Done when:
- [ ] `make migrate && make migrate-down && make migrate` succeeds.
- [ ] `make sqlc` produces no diff in CI.

#### [ ] SET-03 · Flutter app skeleton · [#6](https://github.com/VlasovArtem/wuppa/issues/6) · plan: direct · review: fast

- `flutter create --org app.wuppa --project-name wuppa app` (iOS + Android only).
- Flavours / entry points: `lib/main_local.dart` (API `http://10.0.2.2:8080` on Android emulator, `http://localhost:8080` on iOS simulator), `lib/main_test.dart` (test server URL from `--dart-define=API_BASE_URL`).
- Dependencies: `flutter_riverpod`, `dio`, `go_router`, `flutter_secure_storage`, `freezed_annotation`, `json_annotation`, `intl`, `flutter_localizations` (SDK), `flutter_timezone`; dev: `build_runner`, `freezed`, `json_serializable`, `mocktail`.
- Folder structure from `CLAUDE.md`.
- `app/Makefile` with `test-unit` (`flutter test --reporter json` summarised by `app/tool/test_summary.dart`), `test-integration` (prints `RESULT: PASS test-integration tests=0 (none in the POC)`), `lint` (`dart format --output=none --set-exit-if-changed` + `flutter analyze`) and `check`, with the same agent-friendly contract as the API (`NAME=` narrows to a test file or name; log in `app/.out/`).

Done when:
- [ ] `make -C app check` passes and ends with `RESULT:` lines; a deliberately failing widget test is reported with its file:line; app runs on an emulator showing a placeholder screen.

#### [ ] MOB-01 · App shell, navigation, theme, API client · [#7](https://github.com/VlasovArtem/wuppa/issues/7) · plan: opus · review: heavy

- Theme: one primary colour, one accent, rounded cards, large buttons; kid screens use larger text (scale 1.2).
- `go_router` with redirect logic based on `SessionState`: `none` → welcome; `guardian` → guardian home; `kid` → kid home; `guardianKidView(kidId)` → kid home with PIN exit.
- `SessionStore` on `flutter_secure_storage`: access token, refresh token, guardian email, kid device token (kid's own device), kid-view tokens per kid id (shared phone), PIN hash + salt, kid-view kid id.
- API client: hand-written dio services per feature that mirror `openapi.yaml` (simpler than codegen for the POC); `freezed` models for every schema in section 7.
- Dio interceptor: adds `Authorization`; on `401` with a guardian session, refreshes and retries once; parallel 401s share **one** refresh call (single-flight) and the others wait for it; on failure clears the session.
- `ApiException(code, message)` mapped from the error body; a shared error snackbar.
- Localisation: `gen-l10n` with `lib/l10n/app_en.arb` and `lib/l10n/app_ru.arb` (ICU plurals, needed for Russian, e.g. "осталось 2 раза"); locale follows the device, fallback English; no hard-coded user-facing strings in widgets.
- Mock mode (`--dart-define=MOCK=true`): repositories return fixed data.

Done when:
- [ ] Unit tests for the interceptor refresh flow (mocked dio), including 3 parallel 401s → exactly one refresh call, and error mapping.
- [ ] In mock mode, the app navigates welcome → guardian home and welcome → kid home.
- [ ] The placeholder screens show English and Russian texts depending on the device language.

### Phase 1 — Accounts, kids, pairing

#### [ ] BE-03 · Guardian sign-up, login, tokens · [#8](https://github.com/VlasovArtem/wuppa/issues/8) · plan: opus · review: heavy

- Package `internal/auth`: `HashPassword`, `VerifyPassword` (constant-time), `NewAccessToken`, `ParseAccessToken`, `NewOpaqueToken(prefix)` returning token + SHA-256 hash.
- `POST /v1/auth/signup`: validate (email format, password ≥ 10, names, `timezone` loads with `time.LoadLocation`, `locale` is `en` or `ru`), create family (with that timezone) + guardian in one transaction, issue tokens; `409 email_taken`.
- `POST /v1/auth/login`: `401 invalid_credentials` for unknown email or wrong password (same timing: hash a dummy password when the email is unknown).
- `POST /v1/auth/refresh`: look up by hash; expired / revoked → 401; already rotated → within 10 s: 401 only; later: reuse detected → revoke all of this guardian's tokens, 401; else mark rotated, issue a new pair.
- `POST /v1/auth/logout`: revoke the given refresh token.
- In-memory rate limiter (token bucket keyed by IP + email): 5 / minute on login and signup → `429 rate_limited`; client IP per section 4.
- Middleware `RequireGuardian`.

Done when:
- [ ] Tests: signup, invalid timezone / locale → 422, duplicate email, login ok, wrong password, unknown email, refresh rotation, refresh reuse within 10 s does not revoke, later reuse revokes all, logout, expired access token → 401, rate limit.

#### [ ] BE-14 · Password reset · [#9](https://github.com/VlasovArtem/wuppa/issues/9) · plan: opus · review: heavy

- Package `internal/mail`: `Mailer` interface; SMTP implementation on the standard library (`net/smtp`, STARTTLS) using `SMTP_URL` / `MAIL_FROM`; logging no-op when `SMTP_URL` is empty (log the event, never the code or the email).
- Plain-text reset email in EN and RU (`internal/mail/templates`), chosen by `guardians.locale`.
- `POST /v1/auth/password-reset/request` and `/confirm` per rule 12.

Done when:
- [ ] Tests (fake mailer): unknown email → 202 and no email; code works once; wrong code 5 times kills it; expired code → 410; success revokes old refresh tokens; rate limit → 429.
- [ ] Manual: request a reset locally and read the email in Mailpit (`localhost:8025`).

#### [ ] BE-04 · Family and kid profiles · [#10](https://github.com/VlasovArtem/wuppa/issues/10) · plan: direct · review: standard

- `GET /v1/family`, `POST /v1/kids`, `PATCH /v1/kids/{id}` with validation from section 5.
- Every query filters by `family_id` from the context.

Done when:
- [ ] Tests: create, edit, invalid avatar / age band → 422, kid of another family → 404.

#### [ ] BE-05 · Kid device pairing · [#11](https://github.com/VlasovArtem/wuppa/issues/11) · plan: opus · review: heavy

- Pairing code rules from section 6 (rule 11); `POST /v1/kids/{id}/pairing-code`.
- `POST /v1/pair`: in one transaction check code (unused, not expired), mark used, create `kid_devices` (with `shared`) and a `kd_` token; wrong → `410 invalid_code`. Rate limit 10 / minute per IP.
- Middleware `RequireKid` (hash lookup, reject revoked, update `last_seen_at` per rule 13); `GET /v1/me`.
- `GET /v1/kids/{id}/devices`, `DELETE /v1/kids/{id}/devices/{deviceId}` (sets `revoked_at`).
- Role checks: kid token on guardian routes → 403; guardian token on `/v1/me*` → 403.

Done when:
- [ ] Tests: pair ok, expired code, used code, wrong code, new code invalidates old, code generation retries on a primary-key conflict, revoked device → 401, kid token on `POST /v1/kids` → 403.

#### [ ] BE-15 · Guardian invites · [#12](https://github.com/VlasovArtem/wuppa/issues/12) · plan: opus · review: heavy

- `POST /v1/family/invites` (rule 14); `GET /v1/family` returns `guardians`.
- Sign-up with `invite_code` instead of `family_name` + `timezone`; both or neither → `422 validation_failed`.
- Pending lists and push recipients already cover all guardians of the family; check that no query filters by `created_by`.

Done when:
- [ ] Tests: invite → sign-up joins the family and sees the same kids, tasks and pending items; used or expired invite → 410; `family_name` + `invite_code` together → 422; two guardians deciding the same completion → second gets 409 `already_decided`.

#### [ ] MOB-02 · Sign-up and log-in · [#13](https://github.com/VlasovArtem/wuppa/issues/13) · plan: direct · review: standard

- Welcome screen with two big buttons.
- Sign-up form (display name, family name, email, password with show/hide) and log-in form with a "Forgot password?" link; sign-up also sends the device timezone (`flutter_timezone`) and language (`ru` if the device is Russian, else `en`); inline validation matching the API rules; show API errors.
- On success store tokens and go to guardian home (or "Add your first kid" if the family has no kids).
- Settings screen with log-out (calls `/v1/auth/logout`, clears storage).

Done when:
- [ ] Widget tests for form validation; manual: sign up, kill app, reopen → still logged in.

#### [ ] MOB-13 · Forgot password · [#14](https://github.com/VlasovArtem/wuppa/issues/14) · plan: direct · review: standard

- Step 1: email → `password-reset/request` → "If this email is registered, we sent a code".
- Step 2: 6-digit code + new password (show / hide) → `password-reset/confirm` → store tokens, go to guardian home. `invalid_code` → "Code is wrong or expired" with "Send a new code".

Done when:
- [ ] Widget tests for both steps; manual: full reset against the local API with Mailpit.

#### [ ] MOB-03 · Family setup and add kid · [#15](https://github.com/VlasovArtem/wuppa/issues/15) · plan: direct · review: fast

- Add / edit kid form: nickname, 8-avatar grid, age band chips.
- Guardian home: list of kids (avatar, nickname, points placeholder); tap → kid detail.

Done when:
- [ ] A guardian can add and edit two kids against the local API.

#### [ ] MOB-04 · Pairing on both devices · [#16](https://github.com/VlasovArtem/wuppa/issues/16) · plan: opus · review: standard

- Guardian kid detail → "Connect device" → pairing code screen with countdown and "New code"; devices list with "Disconnect".
- Kid: welcome → "I'm a kid" → 6 digit boxes (auto-advance, paste support) → on success store kid token, go to kid home ("Hi, {nickname}!").
- Kid app: on `401` from a kid endpoint, clear the session and return to welcome.

Done when:
- [ ] Manual: pair an emulator with a second emulator / device; disconnecting returns the kid device to welcome on the next request.

#### [ ] MOB-14 · Invite a second guardian · [#17](https://github.com/VlasovArtem/wuppa/issues/17) · plan: direct · review: fast

- Settings: guardians list; "Invite a parent" → code, expiry, "Copy" and the system share sheet (`share_plus`).
- Sign-up: an "I have an invite code" switch replaces the family name field with an invite-code field.

Done when:
- [ ] Manual: guardian A invites B on a second device; B signs up with the code and sees A's kids.

### Phase 2 — The earn loop

#### [ ] BE-06 · Tasks with repeat limits · [#18](https://github.com/VlasovArtem/wuppa/issues/18) · plan: opus · review: standard

- `internal/domain/period.go`: `PeriodStart` (rule 1) with table tests: just after midnight, Sunday 23:59 → Monday, the last Sunday of March and October in `Europe/Berlin`.
- Task CRUD (`POST`, `PATCH`, `GET ?kid_id=`); `kid_id` must belong to the family. No delete; `active=false` pauses.
- `GET /v1/me/tasks`: active tasks of the kid with `remaining` (rule 2) and `pending` (count of pending in the period).

Done when:
- [ ] Period tests pass; tests for create / edit / pause and `remaining` across day and week boundaries (inject a clock: `domain.Clock` interface, real and fake implementations).

#### [ ] BE-07 · Mark task done · [#19](https://github.com/VlasovArtem/wuppa/issues/19) · plan: opus · review: heavy

- `POST /v1/tasks/{id}/complete` per rule 3; `409 task_inactive`, `409 limit_reached`.
- Idempotency middleware for this route (section 4).
- Emit an internal event `CompletionCreated` (interface `Notifier`, no-op until BE-10).

Done when:
- [ ] Tests: success, limit reached, rejected completion frees a slot, same `Idempotency-Key` returns the same completion, same key while the first request still runs → 409 `request_in_progress`, same key on another task is a separate request, 10 parallel requests with limit 1 create exactly one completion.

#### [ ] BE-08 · Approve / reject and ledger · [#20](https://github.com/VlasovArtem/wuppa/issues/20) · plan: opus · review: heavy

- `GET /v1/completions?status=pending` (newest first) as `CompletionView`.
- Approve (rule 5) and reject (rule 6); `409 already_decided`.
- Badge check hook (rule 9) — implement fully in BE-12; return `new_badges: []` until then.
- Emit `CompletionApproved` and `CompletionRejected` to the `Notifier`.

Done when:
- [ ] Tests: approve writes exactly one ledger entry with the completion's points (even if the task's points changed meanwhile); approving twice → 409 and still one entry; reject writes none; another family's completion → 404.

#### [ ] BE-09 · Balance and points history · [#21](https://github.com/VlasovArtem/wuppa/issues/21) · plan: direct · review: standard

- `GET /v1/me/points` and `GET /v1/kids/{id}/points` (rule 4); entries newest first, max 50, with `title` from the task or reward.

Done when:
- [ ] Test: balance equals the sum of entries after a mix of approvals.

#### [ ] MOB-06 · Create and edit tasks · [#22](https://github.com/VlasovArtem/wuppa/issues/22) · plan: direct · review: fast

- Task form: title with 6 quick picks per age band (static list in `lib/features/tasks/quick_picks.dart`), points stepper with presets 5 / 10 / 20 / 50, "times per" picker (1–20) + day / week toggle, kid picker.
- Kid detail lists tasks with edit and pause / resume.

Done when:
- [ ] Widget test for form validation; manual: create a daily and a weekly task.

#### [ ] MOB-07 · Kid task list and "Done" · [#23](https://github.com/VlasovArtem/wuppa/issues/23) · plan: direct · review: standard

- Kid home: header (avatar, greeting, points), task cards (title, points, "2 left today" / "1 left this week", "Waiting for OK" when pending > 0).
- "Done" sends a new `Idempotency-Key` per tap; button disabled while sending; `limit_reached` shows "All done for today / this week".
- Refresh on pull and when the app returns to the foreground.

Done when:
- [ ] Widget tests for card states (available, pending, used up); manual against the local API.

#### [ ] MOB-08 · Pending approvals · [#24](https://github.com/VlasovArtem/wuppa/issues/24) · plan: direct · review: standard

- Guardian home shows the pending count; approvals screen grouped by kid with "OK" / "Not yet"; optimistic removal with rollback and error snackbar.

Done when:
- [ ] Manual: approve on the guardian device, kid's points update after refresh.

#### [ ] MOB-05 · Kid view on a shared phone, PIN lock · [#25](https://github.com/VlasovArtem/wuppa/issues/25) · plan: opus · review: heavy

- Settings: set / change 4-digit PIN (store salted SHA-256 in secure storage).
- Kid detail → "Hand phone to {nickname}": the first time, the app creates a pairing code (`POST /v1/kids/{id}/pairing-code`) and pairs itself (`POST /v1/pair` with `shared: true`), then keeps that kid token for this kid; later it reuses the token. Kid view shows the same kid screens as the kid app (kid home with "Done", and later the reward shop and history) with that token, so every rule is the same.
- Kid sessions in kid view register no push token; the guardian keeps getting their own pushes on this phone.
- If the kid token gets `401` (device disconnected), drop it and pair again on the next "Hand phone to …".
- Exit needs the PIN; 5 wrong tries → 30 s lockout.
- "Forgot PIN?" on the PIN screen: the guardian types their password; the app calls `POST /v1/auth/login` with the stored guardian email; on success it saves the new tokens, leaves kid view and asks for a new PIN. Password tries fall under the API rate limit, not the PIN lockout.

Done when:
- [ ] Widget tests for the PIN screen lockout and the forgot-PIN flow; kid view shows no guardian actions; manual: the kid ticks a task in kid view, the guardian leaves kid view with the PIN and approves it.

### Phase 3 — Rewards and motivation

#### [ ] BE-11 · Rewards and redemptions · [#26](https://github.com/VlasovArtem/wuppa/issues/26) · plan: opus · review: heavy

- Rewards CRUD; kids see active rewards only.
- Redeem (rule 7) with idempotency; `GET /v1/me/redemptions`; guardian list of `requested`; approve / refuse (rule 8).
- Emit `RedemptionRequested`, `RedemptionApproved` and `RedemptionRefused`.

Done when:
- [ ] Tests: not enough points → 409; 5 parallel redeems with balance for 2 → exactly 2 succeed; refuse refunds exactly the cost; approve does not touch the ledger; decide twice → 409.

#### [ ] BE-12 · Streaks and badges · [#27](https://github.com/VlasovArtem/wuppa/issues/27) · plan: opus · review: standard

- `internal/domain/streak.go` (rule 10) and `badges.go` (rule 9); wire into BE-08 approve and BE-11 approve.
- `GET /v1/me/progress`, `GET /v1/kids/{id}/progress`.

Done when:
- [ ] Table tests: streak over midnight, missed day resets, today without approval keeps yesterday's streak; each badge awarded exactly once; `new_badges` returned on the approval that earned them.

#### [ ] MOB-10 · Points, reward shop, requests · [#28](https://github.com/VlasovArtem/wuppa/issues/28) · plan: direct · review: standard

- Guardian rewards screen: list, add / edit / pause; requests list with "Give" / "Not now".
- Kid reward shop: cards with cost and progress bar (`balance / cost`), "Get it" disabled when too few points; my requests with status.
- Kid points history screen.

Done when:
- [ ] Manual: request → points drop → refuse → points return; request → give → shows as approved.

#### [ ] MOB-11 · Streak and badges display · [#29](https://github.com/VlasovArtem/wuppa/issues/29) · plan: direct · review: fast

- Kid home: flame icon + streak; badge row (earned in colour, others greyed).
- Confetti (package `confetti`) once per newly earned badge (remember seen badges locally).

Done when:
- [ ] Widget test: new badge triggers the celebration once.

### Phase 4 — Push notifications

#### [ ] BE-10 · Push (FCM) · [#30](https://github.com/VlasovArtem/wuppa/issues/30) · plan: opus · review: standard

- `internal/push`: FCM HTTP v1 client using a service-account JSON (`golang.org/x/oauth2/google`); implements `Notifier`.
- `POST /v1/push-tokens` upsert for both roles.
- Events and EN / RU texts from section 7, picked by the token's `locale`; async with 5 s timeout; delete `UNREGISTERED` tokens.
- If `FCM_CREDENTIALS_FILE` is empty, use a logging no-op notifier.

Done when:
- [ ] Unit tests with a fake HTTP server for FCM (payload shape, RU text for a `ru` token, `en` fallback, token cleanup).
- [ ] **[Human]** Provide a Firebase project and service-account key; then verify pushes arrive on a device.

#### [ ] MOB-09 · Push and deep links · [#31](https://github.com/VlasovArtem/wuppa/issues/31) · plan: opus · review: standard

- `firebase_core` + `firebase_messaging`; ask permission after the guardian creates the first task, and for kids after pairing (not in shared kid view).
- Register / refresh the token with `/v1/push-tokens`, sending the app's current locale; register again when the device language changes.
- Tap handling: `completion` → approvals, `approved` → kid home, `redemption` → reward requests, `rejected` → kid home, `reward_approved` / `reward_refused` → kid's requests (cold start and background).
- **[Human]** Add `google-services.json`, `GoogleService-Info.plist`, and the APNs key in Firebase.

Done when:
- [ ] Manual on a real device: each push type opens the right screen from a closed app.

### Phase 5 — Ship to test families

#### [ ] SEED-01 · Seed data · [#32](https://github.com/VlasovArtem/wuppa/issues/32) · plan: direct · review: fast

- `make seed`: family "Demo" (guardian `demo@wuppa.test` / `demo-password-123`), kids Leo (7-9) and Mia (10-12), 3 tasks each, 2 rewards, a few approved completions over the last 4 days.

Done when:
- [ ] `make seed` is idempotent (running twice does not duplicate).

#### [ ] BE-13 · Test environment · [#33](https://github.com/VlasovArtem/wuppa/issues/33) · plan: opus · review: standard

- Multi-stage `api/Dockerfile` (build with `golang:1.23`, run on `gcr.io/distroless/static`), non-root user.
- Run migrations on start (`goose up` in `main` behind a `MIGRATE_ON_START=true` flag).
- **[Human]** Choose the hosting provider (EU region), create managed PostgreSQL, pick an EU SMTP provider (`SMTP_URL`, `MAIL_FROM`), set secrets (and `TRUSTED_PROXY_HOPS` for the provider's load balancer), domain `api-test.<domain>`. Then add a deploy job to `api.yml` for merges to `main`.

Done when:
- [ ] `docker build` succeeds locally; the deployed `/healthz` returns 200.

#### [ ] MOB-12 · Test builds · [#34](https://github.com/VlasovArtem/wuppa/issues/34) · plan: direct · review: fast

- App icon and name "Wuppa"; version from `pubspec.yaml`; `main_test.dart` points at the test API.
- **[Human]** Apple Developer and Google Play accounts, bundle id `app.wuppa`, signing, upload to TestFlight and Play internal testing.

Done when:
- [ ] Someone outside the team installs both builds and completes the 9-step flow.

#### [ ] QA-01 · End-to-end check · [#35](https://github.com/VlasovArtem/wuppa/issues/35) · plan: opus · review: standard

- Run the 9 steps from section 1 on 2 iOS and 2 Android devices (one older Android).
- Edge cases: no network when tapping Done (show error, nothing duplicated), expired pairing code, redeem with too few points, two guardians' devices approving the same item at once (second gets 409 and refreshes), password reset end to end, forgot PIN, the whole flow with the device set to Russian.
- Write found issues to `docs/known-issues.md`.

Done when:
- [ ] All 9 steps pass on all 4 devices; no open blocker.

## 10. Decisions and open questions

- **Q1** Kid view on a shared phone can tick tasks and redeem: **yes**; the phone pairs itself as a shared kid device (MOB-05).
- **Q2** Hosting provider and domain: tracked in [issue #1](https://github.com/VlasovArtem/wuppa/issues/1).
- **Q3** Mobile framework: **Flutter**, confirmed.
- **Q4** Repository `https://github.com/VlasovArtem/wuppa`, Go module `github.com/VlasovArtem/wuppa/api`.
- **Q5** Several guardians: **one shared family**, joined with an invite code (BE-15, MOB-14).
- **Q6** SMTP provider: tracked in [issue #1](https://github.com/VlasovArtem/wuppa/issues/1).
