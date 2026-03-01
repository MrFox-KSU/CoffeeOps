begin;

create or replace function public.request_org_access(p_org_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.org_members(org_id, user_id, role, status)
  values (p_org_id, v_user, 'member', 'pending')
  on conflict (org_id, user_id) do update
    set status = 'pending';

  return jsonb_build_object('ok', true, 'org_id', p_org_id);
end $$;

revoke all on function public.request_org_access(uuid) from public;
grant execute on function public.request_org_access(uuid) to authenticated;

select pg_notify('pgrst','reload schema');
commit;