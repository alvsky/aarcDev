alter table "public"."messages"
  add column "reply_to_id" uuid;

alter table "public"."messages"
  add constraint "messages_reply_to_id_fkey"
  foreign key ("reply_to_id") references "public"."messages"("id") on delete set null;

create index "messages_reply_to_id_idx" on "public"."messages" using btree ("reply_to_id");
