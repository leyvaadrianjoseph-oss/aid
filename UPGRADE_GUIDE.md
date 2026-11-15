# Python Garden platform upgrade

This branch upgrades Adventure, Garden, Toolbox, and Progress while preserving existing user accounts and stored progress.

## Included

- Adventure: three additional chapters and 15 lessons written for the existing beginner Python interpreter.
- Garden: seed purchases go into stackable inventory, bulk purchases are supported, planting consumes one seed, mature plants can be harvested, decorations can be picked back up, and the day/night clock no longer causes a full plot redraw every second.
- Toolbox: category and difficulty filters, richer topic metadata, searchable common mistakes, copyable examples, and links back to the related Adventure lesson.
- Progress: activity calendar, concept mastery, attempt totals, persistent achievement records, more milestones, and higher XP ranks.
- Backend: atomic lesson reward and garden purchase/plant/harvest/decor-pickup operations, plus indexes for common lookups.

## Supabase setup

Back up the project before applying database changes.

For a new database, run these files in order:

1. `sql/schema.sql`
2. `sql/seed.sql`
3. `sql/platform_upgrade.sql`
4. `sql/adventure_content_upgrade.sql`

For the existing project, do not rerun `schema.sql` or `seed.sql` if their tables and seed data are already present. Run only the two upgrade scripts above.

Both upgrade scripts are designed to be rerunnable and additive. They do not drop profiles, lessons, user progress, XP, seeds, or garden plots.

The platform upgrade creates the garden inventory/decor/daily-purchase tables if needed, adds toolbox metadata, adds indexes and RPC functions, and migrates legacy tool/decor items from plant plots where possible.

## Vercel

The PHP API continues to use the existing environment variables:

- `SUPABASE_URL`: project base URL only, without `/rest/v1`
- `SUPABASE_SERVICE_KEY` or `SUPABASE_SECRET_KEY`: server-only Supabase key
- `SESSION_SECRET`: at least 32 characters

Never expose the service key in frontend JavaScript or commit it to GitHub.

## Validation notes

The lesson editor uses the existing in-browser Python subset interpreter. The API now rechecks lesson structure and uses a database transaction to prevent duplicate reward payouts. Exact Python output evaluation is still performed in the browser; production-grade anti-cheat would require moving code execution into an isolated server-side runtime.

Apply the Supabase migrations before testing the upgraded pages. A GitHub branch does not automatically replace the production deployment; merge or deploy the branch through your normal Vercel workflow after reviewing the preview.
