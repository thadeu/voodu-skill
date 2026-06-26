# `vd run` — one-shot verb

Three behaviours, picked by ref shape:

```sh
# 1. Declared job → trigger once
vd run clowk-lp/migrate

# 2. Declared cronjob → force-tick (bypass schedule)
vd run clowk-lp/nightly-backup

# 3. Deployment + command → one-shot exec into a fresh container
vd run clowk-lp/web -- rails db:migrate
vd run clowk-lp/web -- rake clean
```

Without a command, `vd run` only works on a `job` or `cronjob` (the resources that mean "trigger me once").

## When to use which verb

| You want | Verb |
|---|---|
| Trigger a declared job | `vd run clowk-lp/migrate` |
| Force-run a cronjob now | `vd run clowk-lp/nightly-backup` |
| One-shot from a deployment | `vd run clowk-lp/web -- bin/rake task` |
| Enter a live container | `vd exec clowk-lp/web -- bash` |
| Persistent change to state | `vd apply -f voodu.hcl` |

## Recipes

```sh
# Run a Rails migration from the prod image:
vd run clowk-lp/migrate
vd logs clowk-lp/migrate -f

# Test a cronjob without waiting for the schedule:
vd run clowk-lp/nightly-backup

# Ad-hoc maintenance without declaring a job:
vd run clowk-lp/web -- rake "users:cleanup[14days]"
```
