# Launch checklist

## Build + CI
- npm run ci passes
- npm run build passes

## Supabase
- RLS enabled on all org-scoped tables
- Service role key only used in Edge Functions / server-side
- Storage bucket policies validated (imports private)
- Backups enabled
- Migrations strategy documented

## Imports
- Upload -> Parse -> Validate -> Import works for:
  - products
  - sales
  - expenses
- Idempotency confirmed (re-import does not duplicate)
- Audit trail present (imports + allocation audit)

## Dashboards
- /dashboard loads
- /dashboard/sales loads
- /dashboard/expenses loads
- Allocation editor saves and status updates

## Monitoring
- Add error tracking (Sentry) [optional]
