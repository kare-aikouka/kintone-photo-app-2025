# Heroku-24 deployment and rollback runbook

## Purpose

This runbook is for switching the production Heroku app to the `heroku-24` stack when production deploys are triggered by GitHub push. Keep a quick rollback path ready before enabling a deploy.

## Before changing production

Record these values from the Heroku Dashboard before changing the stack or deploying:

- App name
- Current stack
- Latest release number
- Latest deployed Git commit
- Buildpacks and their order
- Current dyno formation
- Current add-ons
- Required config vars are present

Take a Heroku Postgres backup from the Dashboard before production deploy. Do not run irreversible database migrations in the same deploy as the stack change.

## Repository-side change

`app.json` includes:

```json
"stack": "heroku-24"
```

This keeps Review Apps and Heroku CI aligned with Heroku-24. For an existing production app, `app.json` alone does not change the production stack. Change the production stack from the Heroku Dashboard app settings.

## Dashboard deploy flow

1. Confirm the current production app is healthy.
2. Confirm GitHub auto-deploy settings and target branch.
3. In Heroku Dashboard, change the app stack to Heroku-24. The change is pending until the next deploy.
4. Push the Heroku-24 repository change to GitHub.
5. Let the normal GitHub -> Heroku deploy run.
6. Watch the Heroku activity/build log and runtime logs in the Dashboard.

## Smoke checks after deploy

- App boots without H10/H12/H14 errors.
- Login page opens.
- Sign in works.
- Machine list opens.
- Photo list/detail opens.
- Photo upload works.
- Blackboard burn-in works.
- Pending offline upload banner/retry still works.
- kintone read/update works.

## Emergency rollback

Preferred Dashboard rollback:

1. Open Heroku Dashboard > App > Activity.
2. Find the last working release before the Heroku-24 deploy.
3. Use Roll back to here.
4. Confirm the app boots and run the smoke checks again.

If rollback does not recover the app and the failure appears stack-specific:

1. In Heroku Dashboard, change the stack back to the previous stack.
2. Re-deploy the last known-good Git commit or revert the Heroku-24 change in GitHub and push.
3. Watch logs and run smoke checks.

Rollback does not restore external state such as add-on data. Treat this stack migration as platform-only and keep database changes out of the same deploy.
