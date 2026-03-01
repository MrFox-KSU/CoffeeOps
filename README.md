# CoffeeOps Executive BI (Iteration 3)

This repository is the **Iteration 3 deliverable** for your production-grade “executive BI” web app:

- **Frontend:** Next.js (App Router) + Bootstrap 5 + premium dark executive styling
- **Backend:** Supabase Cloud (Auth + Postgres + RLS + Storage + Edge Functions)
- **Core workflow:** CSV-first ingestion via **Import Center**

> This repo is designed to work with **hosted Supabase only** (no local Supabase dependency).

---

## 1) Install dependencies

```bash
npm install
```

---

## 2) Environment

This repo includes a `.env.local` already (per your request).

If you ever need to recreate it:

```bash
cp .env.example .env.local
```

Required:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

Optional:

- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server-only, future iterations)

---

## 3) Apply database migrations (Supabase Cloud)

Supabase Dashboard → **SQL Editor** → run these **in order**:

1. `supabase/migrations/0001_iteration1_foundation.sql`
2. `supabase/migrations/0002_iteration2_import_center.sql`
3. `supabase/migrations/0003_iteration3_parsing_mapping.sql`

Iteration 3 adds (important):

- **GRANT privileges** for `authenticated` (fixes `permission denied for table ...` 403s)
- Missing RLS write policies for `import_job_rows`
- RPC helpers:
  - `list_my_orgs()`
  - `list_import_job_rows(p_job_id, p_limit)`
  - `save_import_job_mapping(p_job_id, p_mapping)`

---

## 4) Deploy the Edge Function (Supabase)

Iteration 3 uses an Edge Function to parse CSV server-side and stage rows.

### Install Supabase CLI (Mac)

```bash
brew install supabase/tap/supabase
```

### Login + link

```bash
supabase login
supabase link --project-ref lpuynflticmrnogprabp
```

### Deploy

From the repo root:

```bash
supabase functions deploy parse_csv_to_staging
```

---

## 5) Run the app

```bash
npm run dev
```

Open `http://localhost:3000`.

- Sign up / sign in
- Create an org (`/onboarding/org`)
- Go to Import Center (`/dashboard/import`)
- Upload a CSV → open the job detail page
- Click **Parse CSV** → preview rows appear with row-level validation errors
- Map columns → **Save mapping + Validate**

---

## Windows notes

See `scripts/windows-setup.md`.
