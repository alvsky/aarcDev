import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { isOnline } from 'src/composables/useNetwork'

// Jedini izvor za ono što aplikacija prikazuje o samoj sebi (Postavke → O
// aplikaciji, Popis promjena) — vidi migraciju 20260903110000_app_releases.sql
// za zašto (dosad su AboutPage i ChangelogPage svaki imali svoju hardkodiranu
// kopiju, i lako se dogodilo da se jedna zaboravi ažurirati uz novi build).
export const useReleasesStore = defineStore('releases', {
  persist: ['releases'],

  state: () => ({
    releases: [], // { build, version, released_at, summary, items[] }, najnoviji prvi
    loading: false,
  }),

  getters: {
    // Prazan dok se prvi put ne dohvati (i offline bez keša) — stranice
    // moraju podnijeti null, ne pretpostaviti da nešto uvijek postoji.
    latest: (state) => state.releases[0] ?? null,
  },

  actions: {
    async fetchReleases() {
      // Offline: zadrži keširano stanje (persist plugin ga već hidrira)
      if (!isOnline()) return
      this.loading = true
      const { data, error } = await supabase
        .from('app_releases')
        .select('*')
        .order('build', { ascending: false })
      this.loading = false
      if (error) throw error
      this.releases = data ?? []
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useReleasesStore, import.meta.hot))
}
