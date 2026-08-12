import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { i18n } from 'src/boot/i18n'
import { clearAll } from 'src/utils/persistence'
import { clearImageCache } from 'src/utils/imageCache'

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null,
    profile: null,
    lang: localStorage.getItem('lang') ?? 'en',
    darkMode: localStorage.getItem('darkMode') === 'true',
    fontSize: localStorage.getItem('fontSize') ?? 'medium',
  }),

  getters: {
    isLoggedIn: (state) => !!state.user,
    fullName: (state) => state.profile?.full_name ?? state.user?.email ?? '',
    initials: (state) => {
      const name = state.profile?.full_name ?? ''
      return (
        name
          .split(' ')
          .map((w) => w[0])
          .join('')
          .toUpperCase()
          .slice(0, 2) || '?'
      )
    },
  },

  actions: {
    async init() {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      this.user = session?.user ?? null
      if (this.user) await this.fetchProfile()
      this.applyLang(this.lang)
      this.applyDarkMode()
      this.applyFontSize()

      supabase.auth.onAuthStateChange((_event, session) => {
        this.user = session?.user ?? null
        if (this.user) this.fetchProfile()
      })
    },

    async fetchProfile() {
      const { data } = await supabase.from('profiles').select('*').eq('id', this.user.id).single()
      this.profile = data
      if (data?.lang) this.applyLang(data.lang)
    },

    applyLang(lang) {
      this.lang = lang
      i18n.global.locale.value = lang
      localStorage.setItem('lang', lang)
    },

    async setLang(lang) {
      this.applyLang(lang)
      if (this.user) {
        await supabase.from('profiles').update({ lang }).eq('id', this.user.id)
      }
    },

    async login(email, password) {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) throw error
    },

    // G1: redirectTo je goli origin — router (index.js) prepozna ?code= u
    // adresi i sam odvede na /reset-password. Mora biti na Supabase
    // Redirect URLs allow-listi (Auth → URL Configuration) za svaku
    // okolinu (dev localhost, produkcija) inače Supabase tiho padne natrag
    // na Site URL.
    async requestPasswordReset(email) {
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: window.location.origin + '/',
      })
      if (error) throw error
    },

    // Za razliku od changePassword (Profile, traži current_password) — ovdje
    // postojanje recovery sesije (klik na mail link) JEST reautentikacija,
    // GoTrue ne traži staru lozinku (korisnik ju je po definiciji zaboravio).
    async confirmPasswordReset(newPassword) {
      const { error } = await supabase.auth.updateUser({ password: newPassword })
      if (error) throw error
    },

    // Vraća { session } — session je null dok "Confirm email" čeka potvrdu
    // (G2). Pozivatelj (LoginPage) mora provjeriti prije nego pretpostavi da
    // je korisnik odmah prijavljen.
    async register(email, password, fullName) {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: { data: { full_name: fullName } },
      })
      if (error) throw error
      return { session: data.session }
    },

    // current_password ide izravno u updateUser() (supabase-js >= 2.102.0) —
    // odvojeni signInWithPassword reauth prije ovoga NIJE dovoljan, GoTrue
    // svejedno traži current_password u samom pozivu i baca "Current
    // password required when setting new password" bez njega.
    async changePassword(currentPassword, newPassword) {
      const { error } = await supabase.auth.updateUser({
        password: newPassword,
        current_password: currentPassword,
      })
      if (error) throw error
    },

    async updateProfile(updates) {
      const { error } = await supabase.from('profiles').update(updates).eq('id', this.user.id)
      if (error) throw error
      this.profile = { ...this.profile, ...updates }
    },

    async deleteAccount() {
      // Provjeri sole-owner projekte
      const { data: owned } = await supabase
        .from('project_members')
        .select('project_id, projects(name)')
        .eq('user_id', this.user.id)
        .eq('role', 'owner')

      const soleOwned = []
      for (const row of owned ?? []) {
        const { count } = await supabase
          .from('project_members')
          .select('*', { count: 'exact', head: true })
          .eq('project_id', row.project_id)
          .eq('role', 'owner')
        if (count === 1) soleOwned.push(row.projects.name)
      }

      if (soleOwned.length) {
        throw { type: 'sole_owner', projects: soleOwned }
      }

      const { error } = await supabase.rpc('delete_own_account')
      if (error) throw error

      await clearAll(this.user.id)
      await clearImageCache()
      this.user = null
      this.profile = null
    },

    async logout() {
      const userId = this.user?.id
      await supabase.auth.signOut()
      if (userId) await clearAll(userId)
      await clearImageCache()
      this.user = null
      this.profile = null
    },

    toggleDarkMode() {
      this.darkMode = !this.darkMode
      localStorage.setItem('darkMode', this.darkMode)
      this.applyDarkMode()
    },

    applyDarkMode() {
      if (this.darkMode) {
        document.body.classList.add('dark-mode')
      } else {
        document.body.classList.remove('dark-mode')
      }
    },

    setFontSize(size) {
      this.fontSize = size
      localStorage.setItem('fontSize', size)
      this.applyFontSize()
    },

    applyFontSize() {
      const sizes = {
        small: '14px',
        medium: '16px',
        large: '18px',
        xlarge: '20px',
      }
      document.documentElement.style.setProperty('--aarc-font-size', sizes[this.fontSize] ?? '16px')

      // Bezdimenzijski faktor (medium = 16px = 1) za komponente koje trebaju skalirati
      // veličinu (npr. avatar), ne samo font-size teksta — calc() ne dijeli dvije
      // dužine, pa CSS treba gotov broj.
      const scales = { small: 0.875, medium: 1, large: 1.125, xlarge: 1.25 }
      document.documentElement.style.setProperty('--aarc-font-scale', scales[this.fontSize] ?? 1)
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAuthStore, import.meta.hot))
}
