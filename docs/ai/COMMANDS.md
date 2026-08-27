# Validation commands

Run from a Discourse checkout with this repository installed under `plugins/discourse-marketplace`.

## Targeted first
- One Ruby spec: `LOAD_PLUGINS=1 bin/rspec plugins/discourse-marketplace/spec/path/to/example_spec.rb`
- Plugin Ruby specs: `bundle exec rake "plugin:spec[discourse-marketplace]"`
- Plugin QUnit, only if frontend tests exist: `CI=1 bundle exec rake "plugin:qunit[discourse-marketplace]"`
- After plugin migration changes: `LOAD_PLUGINS=1 bundle exec rake db:migrate`

## CI status
No `.github/workflows` directory was present on `main` when this file was created (2026-08-27). Do not report GitHub Actions as GREEN unless a workflow/check actually exists and ran for the exact head SHA.

## Discipline
Use the narrowest relevant check first. Do not run a full suite merely to discover the first error. Never claim a command passed unless it actually ran.
