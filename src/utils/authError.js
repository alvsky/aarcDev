// GoTrue zna vratiti praznu ili sirovu poruku (npr. "{}" na 500 grešku bez
// tijela, ili "Database error saving new user") — ružno i nerazumljivo za
// prikazati korisniku. Poznati slučajevi se prevode, sve ostalo nečitljivo
// svede se na općenitu poruku umjesto da procuri sirovo na ekran.
const KNOWN = [
  ['Invalid login credentials', 'auth.errorInvalidCredentials'],
  ['User already registered', 'auth.errorUserExists'],
  ['Email not confirmed', 'auth.errorEmailNotConfirmed'],
  ['Password should be at least', 'auth.errorPasswordTooShort'],
]

export function authErrorMessage(e, t) {
  const msg = e?.message ?? ''
  for (const [needle, key] of KNOWN) {
    if (msg.includes(needle)) return t(key)
  }
  if (!msg || msg.trim().startsWith('{') || /database error|unexpected/i.test(msg)) {
    return t('auth.errorGeneric')
  }
  return msg
}
