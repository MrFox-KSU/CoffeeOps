# Windows Setup (Supabase Cloud only)

This project is intentionally designed to run on Windows **without local Supabase**.

## Prereqs

1) Install **Node.js LTS** (18.18+ recommended) from nodejs.org
2) Install **Git** (optional but recommended)
3) Ensure you can run in PowerShell:

```powershell
node -v
npm -v
```

## Steps

### 1) Download / unzip repo

Unzip the repo into a folder, e.g.:

```powershell
C:\dev\coffeeops-exec-bi
```

### 2) Install dependencies

```powershell
cd C:\dev\coffeeops-exec-bi
npm install
```

### 3) Create your Supabase project

- Create a Supabase project (free tier is fine)
- Go to **Project Settings → API**
  - Copy the **Project URL**
  - Copy the **anon public** key

### 4) Configure `.env.local`

```powershell
copy .env.example .env.local
notepad .env.local
```

Fill:

- `NEXT_PUBLIC_SUPABASE_URL=...`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY=...`

### 5) Apply the SQL migrations

Supabase Dashboard → SQL Editor → run:

- `supabase/migrations/0001_iteration1_foundation.sql`

Then run:

- `supabase/migrations/0002_iteration2_import_center.sql`

This creates the Import Center tables and the private Storage bucket `imports`.

### 6) Run the app

```powershell
npm run dev
```

Open:

- http://localhost:3000

If env vars are missing, the app will route you to:

- http://localhost:3000/setup

## Troubleshooting

### If you see RPC errors like `function create_org does not exist`

You likely haven’t run the SQL migration yet.

### If uploads fail with Storage permission errors

You likely haven’t run the Iteration 2 migration yet (it creates the `imports` bucket and Storage RLS policies).

### If sign-up requires email verification

Supabase Auth settings may have email confirmation enabled. Confirm the email, then sign in.

