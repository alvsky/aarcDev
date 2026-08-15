-- Poziva send-invitation Edge Function nakon svake nove pozivnice — isti obrazac
-- kao push-on-item/push-on-message (supabase_functions.http_request webhook).
-- Do sada su pozivnice postojale samo kao kopirljiv link (B21, svjesno prije G2);
-- sad kad e-mail dostava stvarno radi (Resend domena verificirana), šalje se i mail.
CREATE TRIGGER "send-invitation-email"
  AFTER INSERT ON "public"."invitations"
  FOR EACH ROW
  EXECUTE FUNCTION "supabase_functions"."http_request"(
    'https://uwtmnbliuuoqkmwjwzid.supabase.co/functions/v1/send-invitation',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '5000'
  );
