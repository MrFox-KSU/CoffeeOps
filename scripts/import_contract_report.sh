#!/usr/bin/env bash
set -euo pipefail

echo "# Import Contract Report"
echo "Generated (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Repo root: $(pwd)"
echo

echo "## App roots"
if [ -d "src/app" ]; then echo "- src/app: EXISTS"; else echo "- src/app: (missing)"; fi
if [ -d "app" ]; then echo "- app: EXISTS"; else echo "- app: (missing)"; fi
echo

echo "## Templates (public/templates) header rows"
if [ -d "public/templates" ]; then
  for f in public/templates/*.csv; do
    [ -f "$f" ] || continue
    echo "### $f"
    head -n 1 "$f"
  done
else
  echo "(public/templates missing)"
fi
echo

echo "## Frontend contract signals (required fields + canonical keys)"
# Search for where the UI defines required fields / canonical keys
rg -n --hidden --glob '!node_modules/**' \
  "requiredFields|required_fields|requirements|canonical|entity.*products|entity.*sales|entity.*expenses|entity.*labor|product_name|invoice_date|external_invoice_number|net_sales|expense_date|work_date" \
  app src lib components 2>/dev/null || true
echo

echo "## Import Center pages (paths + key snippets)"
for f in \
  app/dashboard/import/page.tsx \
  app/dashboard/import/\[jobId\]/page.tsx \
  src/app/dashboard/import/page.tsx \
  src/app/dashboard/import/\[jobId\]/page.tsx
do
  if [ -f "$f" ]; then
    echo "### $f"
    rg -n "requiredFields|required_fields|requirements|mapping|entity|parseCsv|saveMapping|template|Download CSV templates" "$f" || true
    echo
  fi
done

echo "## Edge Function contract signals"
if [ -f "supabase/functions/parse_csv_to_staging/index.ts" ]; then
  echo "### supabase/functions/parse_csv_to_staging/index.ts"
  rg -n "type Entity|requiredFields\\(|requiredFields\\s*\\(|validateRow\\(|Missing required field|product_name|invoice_date|net_sales|expense_date|work_date" \
    supabase/functions/parse_csv_to_staging/index.ts || true
else
  echo "(Edge function not found at supabase/functions/parse_csv_to_staging/index.ts)"
fi
echo

echo "## Migrations affecting import tables"
rg -n "create table public.import_jobs|create table public.import_job_rows|import_job_rows|import_jobs" supabase/migrations 2>/dev/null || true
