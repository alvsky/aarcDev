import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'

// Organizacije: prebacivač, ekran organizacije (B20), pozivnice (B21).
//
// ⚠️ Pozivnice su svjesno izgrađene PRIJE G2 (potvrda e-maila), na izričit
// zahtjev — za mali, povjerljiv tim rizik je nizak. accept_invitation
// uspoređuje e-mail sesije s pozivnicom, ali ta provjera vrijedi onoliko
// koliko vrijedi da je adresa stvarno vlasnikova. Zatvoriti s G2 prije
// javnog izlaska (BACKLOG B21).
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
    // Adresar tekuće organizacije — { user_id, role, profiles }. Odvojeno od
    // `orgs` jer je puno rjeđe potreban (samo B20a kandidati za izvršitelja i
    // B20 ekran organizacije), pa se dohvaća lijeno preko fetchMembers().
    members: [],
    // Pozivnice na čekanju za tekuću organizaciju — vidljivo samo adminu.
    invitations: [],
    // Statistika po članu (projects_count/ideas_created/bugs_created/
    // tasks_created/assigned_count), keyed by user_id — samo owner, vidi
    // fetchMemberStats.
    memberStats: {},
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

    // Pozivnice na čekanju za organizaciju — vidljivo samo adminu
    // (invitations_select), pa se poziv tiho vraća prazan za nekog drugog.
    async fetchInvitations(orgId) {
      if (!isOnline() || !orgId) return
      const { data, error } = await supabase
        .from('invitations')
        .select('*')
        .eq('org_id', orgId)
        .is('accepted_at', null)
        .order('created_at', { ascending: false })
      if (error) throw error
      this.invitations = data ?? []
    },

    // .select().single() da se dobije natrag token — treba odmah za link koji
    // admin dijeli, jer još nema slanja e-mailova (BACKLOG K, izvan opsega).
    // Jedinstveni indeks (org_id, lower(email)) WHERE accepted_at IS NULL javi
    // se kao 23505 ako već postoji neprihvaćena pozivnica na tu adresu —
    // pretvoreno u čitljivu poruku umjesto sirove Postgres greške.
    async createInvitation(orgId, email, role) {
      const auth = useAuthStore()
      const { data, error } = await supabase
        .from('invitations')
        .insert({
          org_id: orgId,
          email: email.trim().toLowerCase(),
          role,
          invited_by: auth.user.id,
        })
        .select()
        .single()
      if (error) {
        if (error.code === '23505') {
          throw new Error('Već postoji neprihvaćena pozivnica na tu adresu.')
        }
        throw error
      }
      this.invitations = [data, ...this.invitations]
      return data
    },

    async revokeInvitation(invitationId) {
      const { error } = await supabase.from('invitations').delete().eq('id', invitationId)
      if (error) throw error
      this.invitations = this.invitations.filter((i) => i.id !== invitationId)
    },

    // Bez prijave, bez članstva — token sam po sebi otključava pregled
    // (get_invitation_preview, B21). Vraća null za nepostojeću/isteklu/već
    // prihvaćenu pozivnicu, ne baca grešku — "nije pronađeno" je normalno
    // stanje ovog poziva, ne kvar.
    async getInvitationPreview(token) {
      const { data, error } = await supabase.rpc('get_invitation_preview', { p_token: token })
      if (error) throw error
      return data?.[0] ?? null
    },

    async acceptInvitation(token) {
      const { data: orgId, error } = await supabase.rpc('accept_invitation', { p_token: token })
      if (error) throw error
      await this.fetchOrgs()
      this.setCurrent(orgId)
      return orgId
    },

    // Adresar organizacije — za koga vrijedi vidljivost 'org'. Politika
    // org_members_select vraća cijeli popis (uključujući goste) svakome tko
    // sam nije gost; gosti se ovdje ionako ne uzimaju u obzir kao kandidati.
    //
    // FK na auth.users, ne na profiles — ručno spajanje (invarijanta 1).
    async fetchMembers(orgId) {
      if (!isOnline() || !orgId) return

      const { data: rows, error } = await supabase
        .from('org_members')
        .select('user_id, role')
        .eq('org_id', orgId)
      if (error) throw error

      const userIds = (rows ?? []).map((r) => r.user_id)
      const { data: profiles } = userIds.length
        ? await supabase
            .from('profiles')
            .select('id, full_name, email, avatar_url')
            .in('id', userIds)
        : { data: [] }

      const byId = new Map((profiles ?? []).map((p) => [p.id, p]))
      this.members = (rows ?? []).map((r) => ({ ...r, profiles: byId.get(r.user_id) ?? null }))
    },

    // Samo owner (RPC sama provjerava, baca ako nisi) — ostali članovi vide
    // samo osnovne podatke iz fetchMembers/members. Odvojeno od fetchMembers
    // jer je puno rjeđe potrebno i skuplje za izračunati.
    async fetchMemberStats(orgId) {
      if (!isOnline() || !orgId) return
      const { data, error } = await supabase.rpc('org_member_stats', { p_org: orgId })
      if (error) throw error
      this.memberStats = Object.fromEntries((data ?? []).map((row) => [row.user_id, row]))
    },

    setCurrent(orgId) {
      this.currentId = orgId
      if (orgId) localStorage.setItem(CURRENT_KEY, orgId)
      else localStorage.removeItem(CURRENT_KEY)
    },

    // Isti obrazac kao create_project (C2): organizacija i prvi član (vlasnik)
    // nastaju u jednoj transakciji na poslužitelju.
    async createOrg(name) {
      const { data: id, error } = await supabase.rpc('create_organization', { p_name: name })
      if (error) throw error
      await this.fetchOrgs()
      this.setCurrent(id)
      return id
    },

    async renameOrg(orgId, name) {
      // .select() je nužan: PostgREST na UPDATE koji RLS tiho odbije (0 pogođenih
      // redaka) ne vraća error — samo praznu listu. Bez ovoga bi lokalno stanje
      // pokazalo "uspjeh" dok baza ne bi promijenila ništa, a promjena bi
      // nestala čim se store idući put napuni sa servera (fetchOrgs na Homeu).
      const { data, error } = await supabase
        .from('organizations')
        .update({ name: name.trim() })
        .eq('id', orgId)
        .select()
      if (error) throw error
      if (!data?.length) {
        throw new Error('Preimenovanje nije uspjelo — provjeri jesi li admin ove organizacije.')
      }
      const org = this.orgs.find((o) => o.id === orgId)
      if (org) org.name = name.trim()
    },

    // set_member_role / remove_org_member su RPC-evi iz B12 — provjeravaju
    // ulogu pozivatelja i zadnjeg vlasnika sami, ovdje se samo zove i lokalno
    // stanje osvježi.
    async setMemberRole(orgId, userId, role) {
      const { error } = await supabase.rpc('set_member_role', {
        p_org: orgId,
        p_user: userId,
        p_role: role,
      })
      if (error) throw error
      const member = this.members.find((m) => m.user_id === userId)
      if (member) member.role = role
      if (userId === useAuthStore().user?.id) await this.fetchOrgs()
    },

    async removeMember(orgId, userId) {
      const { error } = await supabase.rpc('remove_org_member', {
        p_org: orgId,
        p_user: userId,
      })
      if (error) throw error
      this.members = this.members.filter((m) => m.user_id !== userId)
      if (userId === useAuthStore().user?.id) await this.fetchOrgs()
    },

    async deleteOrg(orgId) {
      const { error } = await supabase.from('organizations').delete().eq('id', orgId)
      if (error) throw error
      this.orgs = this.orgs.filter((o) => o.id !== orgId)
      if (this.currentId === orgId) this.setCurrent(this.orgs[0]?.id ?? null)
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useOrgsStore, import.meta.hot))
}
