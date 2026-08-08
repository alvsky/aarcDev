-- Push notifikacije i za nove ideje/bugove/TBI stavke, ne samo poruke.
-- push-on-message edge funkcija je proširena da grana po payload.table.
create trigger "push-on-idea" after insert on "public"."ideas"
  for each row execute function "supabase_functions"."http_request"(
    'https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message',
    'POST', '{"Content-type":"application/json"}', '{}', '5000'
  );

create trigger "push-on-bug" after insert on "public"."bugs"
  for each row execute function "supabase_functions"."http_request"(
    'https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message',
    'POST', '{"Content-type":"application/json"}', '{}', '5000'
  );

create trigger "push-on-tbi" after insert on "public"."tbi_items"
  for each row execute function "supabase_functions"."http_request"(
    'https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/push-on-message',
    'POST', '{"Content-type":"application/json"}', '{}', '5000'
  );
