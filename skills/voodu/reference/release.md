# `vd release` — release phase

The release phase is a manifest-declared command that runs **once per deploy** after the container starts but before traffic flips. Think Rails `db:migrate`, Django migrations, asset precompilation.

## Declare it

```hcl
deployment "clowk-lp" "web" {
  image = "ghcr.io/clowk/lp:latest"

  release {
    pre_command  = ["rails", "db:migrate"]
    command      = ["rails", "release:tasks"]
    post_command = ["rails", "cache:clear"]
    timeout      = "5m"
  }
}
```

## Verbs

```sh
vd release clowk-lp/web                 # re-run the release command
vd release clowk-lp/web list            # list past releases (id, time, status)
vd release clowk-lp/web logs            # logs of the last release run
vd release clowk-lp/web logs release-42 # logs of a specific run
```

## When to reach for it

- `release { command = ... }` failed mid-deploy and you fixed the underlying issue
- You want to re-run migrations against a refreshed database
- Debugging a migration without doing a full re-deploy

## Compared to `vd run`

- `vd release` re-runs the **declared** release command of an existing deployment.
- `vd run <deploy> -- cmd` spawns a one-shot container with whatever command you pass.
