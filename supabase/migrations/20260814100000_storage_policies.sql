-- B16: politike Storagea u migraciju (dosad postojale samo u dashboardu,
-- neverzionirane) + putanja koja konačno sadrži projectId, pa se pristup
-- prilozima uopće MOŽE ograničiti po projektu preko can_access_project —
-- stara putanja (${userId}/${file}) to nije dopuštala, projekt se iz nje
-- ne da pročitati.
--
-- Nova putanja: chat-attachments/${projectId}/${userId}/${uuid}.jpg
-- Avatari sele u zaseban bucket (nisu projektni): avatars/${userId}/${uuid}.jpg
--
-- ⚠️ Namjerno bez migracije postojećih objekata — dev okruženje, prihvaćen
-- prekid (stari screenshotovi/avatari mogu postati nedostupni dok se
-- ponovno ne uploadaju). Retci u items/messages/profiles koji na njih
-- pokazuju NISU dirani.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

-- chat-attachments bucket već postoji (stvoren ranije u dashboardu) — samo
-- osiguravamo da ima iste razumne limite, bez diranja ako već postoji.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-attachments', 'chat-attachments', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- chat-attachments: putanja je (project_id, user_id, filename).
-- storage.foldername(name) vraća text[] segmenata putanje BEZ imena datoteke,
-- pa je [1] = project_id, [2] = user_id.
-- ---------------------------------------------------------------------------
-- Jednoargumentna can_access_project(pid) (auth.uid() implicitno) — DVOargumentna
-- verzija je namjerno revoke-ana iz authenticated (D1, samo za edge funkciju), pa
-- bi je politika ovdje pozvana od običnog korisnika odbila s "permission denied".
drop policy if exists chat_attachments_select on storage.objects;
create policy chat_attachments_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'chat-attachments'
    and public.can_access_project(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists chat_attachments_insert on storage.objects;
create policy chat_attachments_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-attachments'
    and public.can_access_project(((storage.foldername(name))[1])::uuid)
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- Samo vlastita mapa — isto poznato ograničenje kao kod ostalih Storage
-- brisanja u kodu (E3): admin koji briše tuđu stavku neće uspjeti obrisati
-- njezin screenshot (tiho, bez greške), objekt ostaje siroče. Nije
-- regresija, postojeće ponašanje.
drop policy if exists chat_attachments_delete on storage.objects;
create policy chat_attachments_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'chat-attachments'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- avatars: putanja je (user_id, filename) — nije projektna.
-- Vidljivost prati profiles_select (can_see_profile): vlastiti avatar ili
-- suradnik iz iste organizacije. Prije je avatar dijelio bucket/politike s
-- chat-attachments, pa ovo pravilo nije ni postojalo eksplicitno.
-- ---------------------------------------------------------------------------
drop policy if exists avatars_select on storage.objects;
create policy avatars_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'avatars'
    and public.can_see_profile(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists avatars_insert on storage.objects;
create policy avatars_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
