import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { isOnline } from 'src/composables/useNetwork'
import { useAuthStore } from './auth'

// Globalni prekidači za funkcije koje se žele uključivati/isključivati bez
// punog deploy ciklusa — vidi migraciju 20260919100000_feature_flags.sql.
// Čita svatko; piše (RLS) samo admin/owner organizacije aarc d.o.o., kroz
// skriveni dijalog u OrgPage.vue (tapni 7x na naziv organizacije).
export const useFeatureFlagsStore = defineStore('featureFlags', {
  persist: ['flags'],

  state: () => ({
    flags: {}, // { [key]: boolean }
  }),

  getters: {
    isEnabled: (state) => (key) => !!state.flags[key],
  },

  actions: {
    async fetchFlags() {
      // Offline: zadrži keširano stanje
      if (!isOnline()) return
      const { data, error } = await supabase.from('feature_flags').select('key, enabled')
      if (error) throw error
      this.flags = Object.fromEntries((data ?? []).map((f) => [f.key, f.enabled]))
    },

    // Optimistično + rollback na grešku (isti obrazac kao projectsStore.togglePin) —
    // RLS odbija tihim ostankom na staroj vrijednosti ako pozivatelj nije admin
    // organizacije aarc.
    async setFlag(key, enabled) {
      const previous = this.flags[key]
      this.flags = { ...this.flags, [key]: enabled }

      const auth = useAuthStore()
      const { error } = await supabase
        .from('feature_flags')
        .update({ enabled, updated_at: new Date().toISOString(), updated_by: auth.user?.id })
        .eq('key', key)

      if (error) {
        this.flags = { ...this.flags, [key]: previous }
        throw error
      }
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useFeatureFlagsStore, import.meta.hot))
}
