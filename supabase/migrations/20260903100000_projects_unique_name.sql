-- Onemogući dva projekta s istim nazivom unutar iste organizacije.
-- Case-insensitive (lower(name)), po uzoru na invitations_pending_idx.
-- Namjerno bez WHERE — za razliku od pozivnica, ovdje nema stanja poput
-- accepted_at koje bi opravdalo ponovnu upotrebu naziva.
create unique index projects_org_name_idx
  on public.projects (org_id, lower(name));
