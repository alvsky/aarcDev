-- Statistika po članu organizacije — samo za ownera (ne i admina, za sad
-- namjerno uže; može se proširiti kasnije ako zatreba). Ostali članovi i
-- dalje vide samo osnovne podatke (avatar/ime/email/uloga) koje već daje
-- org_members_select politika preko orgsStore.members — ovo je zaseban,
-- stroži dohvat.
create or replace function public.org_member_stats(p_org uuid)
returns table (
  user_id uuid,
  projects_count bigint,
  ideas_created bigint,
  bugs_created bigint,
  tasks_created bigint,
  assigned_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_org_owner(p_org) then
    raise exception 'Samo vlasnik organizacije može vidjeti statistiku';
  end if;

  return query
    select
      om.user_id,
      -- "Aktivan u X projekata" — projekti u kojima je nešto prijavio ili mu
      -- je nešto dodijeljeno, ne project_members (to je od B25 pretplata,
      -- ne stvarna aktivnost).
      count(distinct i.project_id) filter (
        where i.created_by = om.user_id or i.assignee_id = om.user_id
      ) as projects_count,
      count(*) filter (where i.created_by = om.user_id and i.kind = 'idea') as ideas_created,
      count(*) filter (where i.created_by = om.user_id and i.kind = 'bug') as bugs_created,
      count(*) filter (where i.created_by = om.user_id and i.kind = 'task') as tasks_created,
      count(*) filter (where i.assignee_id = om.user_id) as assigned_count
    from org_members om
    left join projects p on p.org_id = om.org_id
    left join items i on i.project_id = p.id
    where om.org_id = p_org
    group by om.user_id;
end;
$$;

revoke all on function public.org_member_stats(uuid) from public, anon;
grant execute on function public.org_member_stats(uuid) to authenticated;
