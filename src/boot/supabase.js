import { createClient } from '@supabase/supabase-js'
import { boot } from 'quasar/wrappers'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    storage: window.localStorage,
    // G1: implicit tok stavlja token u #access_token=... — isti # koji
    // koristi naš hash router. Vue Router normalizira/dira taj fragment
    // prije nego ga Supabase stigne pročitati (utrka), pa se recovery
    // sesija nikad ne uspostavi (vidi 2026-08-12, prazna stranica +
    // #/access_token=... umjesto stvarne prijave). PKCE stavlja token u
    // ?code=... — pravi query string, PRIJE #, router ga uopće ne dira.
    flowType: 'pkce',
  },
})

// Samo u razvoju: klijent u konzoli, da se RLS politike mogu provjeriti onako
// kako ih napadač i vidi — izravnim pozivom, mimo sučelja. U produkcijskom
// buildu ovoga nema (import.meta.env.DEV je tada false).
if (import.meta.env.DEV) {
  window.supabase = supabase
}

export default boot(({ app }) => {
  app.config.globalProperties.$supabase = supabase
})
