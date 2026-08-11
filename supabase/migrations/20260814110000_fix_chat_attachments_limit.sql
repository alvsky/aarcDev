-- B16 dogradnja: chat-attachments je stvoren ranije (dashboard) pa ga je
-- prethodna migracija (20260814100000) preskočila preko `on conflict do
-- nothing` — ostao je bez file_size_limit/allowed_mime_types. avatars (novi
-- bucket) je limite dobio odmah. Izjednačavamo eksplicitnim update-om.
update storage.buckets
   set file_size_limit = 5242880,
       allowed_mime_types = array['image/jpeg']
 where id = 'chat-attachments';
