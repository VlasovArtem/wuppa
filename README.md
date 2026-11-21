# Wuppa

Wuppa is a family app that turns household jobs into achievements: guardians create tasks, kids do them, guardians approve, kids earn points and spend them on rewards.
This repository holds the proof of concept: a Go API (`api/`) and one Flutter app for iOS and Android (`app/`).

## Layout

- `api/` Go API, migrations, OpenAPI contract
- `app/` Flutter app
- `docs/` specification and task plan

## Lint

```
make -C api lint             # golangci-lint v2.15
make -C api lint-workflows   # actionlint on .github/workflows
make -C api ci               # all of the above plus the lint self-test
```

See [docs/poc-plan.md](docs/poc-plan.md) for the full plan.
