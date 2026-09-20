-- Više od jednog screenshota po ideji/bugu/zadatku — dosad je items imao
-- samo jedan slot (screenshot_url/screenshot_type/screenshot_name). Ova
-- tablica ih zamjenjuje; postojeći pojedinačni screenshotovi se prebacuju
-- prije brisanja starih stupaca.
create table if not exists public.item_screenshots (
  id         uuid primary key default gen_random_uuid(),
  item_id    uuid not null references public.items(id) on delete cascade,
  url        text not null,
  type       text,
  name       text,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now()
);

alter table public.item_screenshots enable row level security;

-- Isti obrazac kao message_reactions_select: vidljivost stavke (items_select,
-- can_access_project) se prenosi kroz EXISTS join, ne duplicira se ovdje.
create policy "item_screenshots_select" on public.item_screenshots
  for select to authenticated using (
    exists (select 1 from public.items i where i.id = item_screenshots.item_id)
  );

create policy "item_screenshots_insert" on public.item_screenshots
  for insert to authenticated with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.items i
      where i.id = item_screenshots.item_id and public.can_access_project(i.project_id)
    )
  );

-- Brisanje: tko ga je dodao, ili tko smije brisati samu stavku (autor stavke
-- ili admin organizacije — isto pravilo kao items_delete).
create policy "item_screenshots_delete" on public.item_screenshots
  for delete to authenticated using (
    created_by = auth.uid()
    or exists (
      select 1 from public.items i
      where i.id = item_screenshots.item_id
        and (i.created_by = auth.uid() or public.is_project_org_admin(i.project_id))
    )
  );

create index item_screenshots_item_idx on public.item_screenshots (item_id);

insert into public.item_screenshots (item_id, url, type, name, created_by, created_at)
select id, screenshot_url, screenshot_type, screenshot_name, created_by, created_at
  from public.items
 where screenshot_url is not null;

alter table public.items
  drop column screenshot_url,
  drop column screenshot_type,
  drop column screenshot_name;
