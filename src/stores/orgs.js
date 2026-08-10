import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'

// Minimalni store za organizacije — dovoljno da se zna u kojoj se radi i koja
// je moja uloga. Prebacivač, ekran organizacije i pozivnice dolaze s B20/B21.
//
// Odabrana organizacija ide u localStorage, ne u IndexedDB keš: to je postavka
// uređaja, ne podatak, i mora biti poznata prije nego se išta dohvati.

const CURRENT_KEY = 'currentOrgId'
const ADMIN_ROLES = ['owner', 'admin']

export const useOrgsStore = defineStore('orgs', {
  persist: ['orgs'],

  state: () => ({
    orgs: [], // { id, name, slug, plan, role }
    currentId: localStorage.getItem(CURRENT_KEY) ?? null,
  }),

  getters: {
    // Ako spremljena više ne vrijedi (izbačen si, obrisana je), padni na prvu.
    current: (state) => state.orgs.find((o) => o.id === state.currentId) ?? state.orgs[0] ?? null,
    currentRole() {
      return this.current?.role ?? null
    },
    isAdmin() {
      return ADMIN_ROLES.includes(this.currentRole)
    },
    isOwner() {
      return this.currentRole === 'owner'
    },
    isGuest() {
      return this.currentRole === 'guest'
    },
  },

  actions: {
    async fetchOrgs() {
      if (!isOnline()) return
      const auth = useAuthStore()
      if (!auth.user) return

      // org_members.org_id ima pravi strani ključ na organizations, pa PostgREST
      // ugnježđivanje ovdje RADI — za razliku od profila, čiji FK ide na
      // auth.users (invarijanta 1).
      const { data, error } = await supabase
        .from('org_members')
        .select('role, organizations(id, name, slug, plan)')
        .eq('user_id', auth.user.id)
      if (error) throw error

      this.orgs = (data ?? [])
        .filter((r) => r.organizations)
        .map((r) => ({ ...r.organizations, role: r.role }))

      if (!this.orgs.some((o) => o.id === this.currentId)) {
        this.setCurrent(this.orgs[0]?.id ?? null)
      }
    },

    setCurrent(orgId) {
      this.currentId = orgId
      if (orgId) localStorage.setItem(CURRENT_KEY, orgId)
      else localStorage.removeItem(CURRENT_KEY)
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useOrgsStore, import.meta.hot))
}
