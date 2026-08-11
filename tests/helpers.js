import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL
const anonKey = process.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  throw new Error(
    'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY nedostaju — ovi testovi zovu pravi dev ' +
      'Supabase projekt i trebaju .env kao i aplikacija.',
  )
}

// persistSession: false — svaki klijent drži svoju sesiju samo u memoriji (nema
// localStorage u Node-u), pa dva "korisnika" u istom test procesu ne mogu
// slučajno dijeliti/pregaziti jedan drugom sesiju.
export function newClient() {
  return createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  })
}

// Nasumičan test korisnik — registracija pa dohvat sesije (email potvrda je
// isključena u dev okruženju, isto na čemu se oslanja i normalan signup flow
// u aplikaciji, vidi LoginPage.vue).
export async function createTestUser(label) {
  const client = newClient()
  const email = `rls-test-${label}-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`
  const password = `Test${Math.random().toString(36).slice(2)}!`
  const fullName = `RLS Test ${label}`

  const { data, error } = await client.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName } },
  })
  if (error) throw error
  if (!data.session) {
    throw new Error(
      `Signup za ${email} nije odmah vratio sesiju — provjeri je li email confirm ` +
        'isključen u dev projektu (Auth → Providers → Email → Confirm email = off).',
    )
  }

  return { client, email, password, fullName, userId: data.user.id }
}

// Best-effort čišćenje: brisanje organizacije kaskadno briše sve njene
// projekte/poruke/stavke (org_id/project_id FK-ovi su ON DELETE CASCADE), pa
// je dovoljno obrisati organizaciju koju je test korisnik stvorio kao owner.
export async function cleanupOrg(client, orgId) {
  if (!orgId) return
  await client.from('organizations').delete().eq('id', orgId)
}
