// DB RPC funkcije i okidači (supabase/schema.sql) uvijek bacaju hrvatski
// tekst — Postgres ne zna za i18n. Bez ovoga bi engleski korisnik vidio
// sirovu hrvatsku grešku (npr. "Nisi član te organizacije") umjesto
// prevedene poruke. Isti obrazac kao authError.js, generaliziran na sve DB
// poruke umjesto samo GoTrue/auth greške — .includes umjesto točnog
// podudaranja jer 'Nepoznata uloga: %' ima dinamički dio (ime uloge).
const KNOWN = [
  ['Nepoznata uloga:', 'dbErrors.unknownRole'],
  ['Organizacija mora imati barem jednog vlasnika', 'dbErrors.orgNeedsOwner'],
  ['Potrebna je prijava', 'dbErrors.loginRequired'],
  ['Pozivnica ne postoji ili je već iskorištena', 'dbErrors.inviteNotFound'],
  ['Pozivnica je istekla', 'dbErrors.inviteExpired'],
  ['Pozivnica je izdana na drugu e-mail adresu', 'dbErrors.inviteWrongEmail'],
  ['Naziv organizacije je obavezan', 'dbErrors.orgNameRequired'],
  ['Naziv projekta je obavezan', 'dbErrors.projectNameRequired'],
  ['Nisi član te organizacije', 'dbErrors.notOrgMember'],
  ['Gost ne može stvarati projekte', 'dbErrors.guestCannotCreateProjects'],
  ['Nemaš pristup ovom projektu', 'dbErrors.noProjectAccess'],
  ['Vidljivost projekta može mijenjati samo admin organizacije', 'dbErrors.onlyAdminCanChangeVisibility'],
  ['Samo vlasnik organizacije može vidjeti statistiku', 'dbErrors.onlyOwnerCanSeeStats'],
  ['Osoba nije član ove organizacije', 'dbErrors.personNotOrgMember'],
  ['Samo admin ili vlasnik može uklanjati članove', 'dbErrors.onlyAdminCanRemoveMembers'],
  ['Vlasnika može ukloniti samo vlasnik', 'dbErrors.onlyOwnerCanRemoveOwner'],
  ['Samo admin ili vlasnik može mijenjati uloge', 'dbErrors.onlyAdminCanChangeRoles'],
  ['Vlasništvo može mijenjati samo vlasnik', 'dbErrors.onlyOwnerCanTransferOwnership'],
  ['Nemaš ovlasti za upravljanje članovima ovog projekta', 'dbErrors.noPermissionManageProjectMembers'],
  ['Osoba nije član ovog projekta', 'dbErrors.personNotProjectMember'],
]

export function dbErrorMessage(e, t) {
  const msg = e?.message ?? ''
  for (const [needle, key] of KNOWN) {
    if (msg.includes(needle)) return t(key)
  }
  return msg
}
