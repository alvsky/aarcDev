import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { isOnline } from 'src/composables/useNetwork'
import { useAuthStore } from './auth'

export const useProjectsStore = defineStore('projects', {
  persist: ['projects'],

  state: () => ({
    projects: [],
  }),

  getters: {
    getById: (state) => (id) => state.projects.find((p) => p.id === id),

    // project_members je od 2026-08-11 pretplata, ne dozvola za pristup —
    // vidi supabase/migrations/20260811100000_project_following.sql. Redak
    // postoji čim netko piše u projekt ili mu se nešto dodijeli; ovaj getter
    // samo čita jesi li već u tom popisu.
    isFollowing: (state) => (projectId) => {
      const auth = useAuthStore()
      const project = state.projects.find((p) => p.id === projectId)
      return !!project?.project_members?.some((m) => m.user_id === auth.user?.id)
    },
  },

  actions: {
    async fetchProjects() {
      // Offline: zadrži keširano stanje
      if (!isOnline()) return
      const { data: projects, error } = await supabase
        .from('projects')
        .select('*')
        .order('created_at', { ascending: false })
      if (error) throw error

      if (!projects?.length) {
        this.projects = []
        return
      }

      // Dohvati članove
      const { data: members } = await supabase
        .from('project_members')
        .select(
          'project_id, user_id, role, badge_enabled, notif_messages, notif_ideas, notif_bugs, notif_tbi',
        )
        .in(
          'project_id',
          projects.map((p) => p.id),
        )

      // Dohvati profile za sve membere
      const userIds = [...new Set(members?.map((m) => m.user_id) ?? [])]

      let profiles = []
      if (userIds.length) {
        const { data } = await supabase
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .in('id', userIds)
        profiles = data ?? []
      }

      // Spoji sve
      this.projects = projects.map((p) => ({
        ...p,
        project_members: (members ?? [])
          .filter((m) => m.project_id === p.id)
          .map((m) => ({
            ...m,
            profiles: profiles.find((pr) => pr.id === m.user_id) ?? null,
          })),
      }))
    },

    // Sve ide kroz create_project RPC (jedna transakcija). Raniji postupak
    // "ubaci → dohvati najnoviji → dodaj sebe" imao je utrku, a nakon
    // organizacija se ni ne bi mogao dovršiti: projekt nastaje privatan, pa ga
    // vlastiti tvorac ne može pročitati dok nema članski redak.
    async createProject({ name, description, color }) {
      const { useOrgsStore } = await import('./orgs')
      const orgs = useOrgsStore()
      if (!orgs.current) await orgs.fetchOrgs()

      const orgId = orgs.current?.id
      if (!orgId) throw new Error('Nema odabrane organizacije')

      const { data: newId, error } = await supabase.rpc('create_project', {
        p_org: orgId,
        p_name: name,
        p_description: description ?? null,
        p_color: color ?? null,
      })
      if (error) throw error

      await this.fetchProjects()
      return newId
    },

    async updateProject(id, updates) {
      const { error } = await supabase.from('projects').update(updates).eq('id', id)
      if (error) throw error
      await this.fetchProjects()
    },

    async deleteProject(id) {
      console.log('Deleting project:', id)
      const { error } = await supabase.from('projects').delete().eq('id', id)
      console.log('Delete error:', error)
      if (error) throw error
      this.projects = this.projects.filter((p) => p.id !== id)
      await this.fetchProjects()
    },

    // Zamjenjuje stari addMember(projectId, email): traženje po e-mailu je
    // pretpostavljalo da svatko smije postati član bilo kojeg projekta, a
    // project_members_insert (B12) to odbija ako osoba nije član ORGANIZACIJE
    // tog projekta. Otkad postoji adresar (orgsStore.members), biranje po
    // e-mailu je nepotrebno — biraš izravno iz ljudi koji već mogu biti
    // pozvani (uključujući goste, namjerno: to je jedini način da gost uopće
    // dobije pristup — eksplicitan redak na privatnom projektu).
    async addProjectMember(projectId, userId, role = 'member') {
      const { error } = await supabase
        .from('project_members')
        .insert({ project_id: projectId, user_id: userId, role })
      if (error) throw error
      await this.fetchProjects()
    },

    async removeMember(projectId, userId) {
      const { error } = await supabase
        .from('project_members')
        .delete()
        .eq('project_id', projectId)
        .eq('user_id', userId)
      if (error) throw error
      await this.fetchProjects()
    },

    // set_member_role je za organizacije (B12); ovo je isti obrazac za ulogu na
    // POJEDINOM projektu — direktan UPDATE ne prolazi otkad je project_members
    // UPDATE grantom sužen na postavke obavijesti (B12), pa čak ni admin
    // organizacije ne bi mogao izravno promijeniti tuđu ulogu.
    async setProjectMemberRole(projectId, userId, role) {
      const { error } = await supabase.rpc('set_project_member_role', {
        p_project: projectId,
        p_user: userId,
        p_role: role,
      })
      if (error) throw error
      await this.fetchProjects()
    },

    // Optimistično bilježi da je auto-praćenje upravo okinuto na poslužitelju
    // (poruka/dodjela — vidi 20260811100000_project_following.sql), da UI ne
    // mora čekati novi fetchProjects() da bi znao da sad prati.
    markFollowingLocally(projectId) {
      const auth = useAuthStore()
      const project = this.projects.find((p) => p.id === projectId)
      if (!project || this.isFollowing(projectId)) return
      project.project_members = [
        ...(project.project_members ?? []),
        {
          project_id: projectId,
          user_id: auth.user.id,
          role: 'member',
          badge_enabled: true,
          notif_messages: true,
          notif_ideas: true,
          notif_bugs: true,
          notif_tbi: true,
          profiles: null,
        },
      ]
    },

    // Otključavanje ide izravnim DELETE-om (postojeća project_members_delete
    // politika već dopušta brisanje vlastitog retka) — RPC ovdje ne treba.
    async unfollowProject(projectId) {
      const auth = useAuthStore()
      const { error } = await supabase
        .from('project_members')
        .delete()
        .eq('project_id', projectId)
        .eq('user_id', auth.user.id)
      if (error) throw error

      const project = this.projects.find((p) => p.id === projectId)
      if (project) {
        project.project_members = project.project_members.filter((m) => m.user_id !== auth.user.id)
      }
    },

    handleIncoming({ event, payload }) {
      if (event === 'UPDATE') {
        const idx = this.projects.findIndex((p) => p.id === payload.new.id)
        if (idx !== -1) {
          this.projects[idx] = { ...this.projects[idx], ...payload.new }
        }
      }
      if (event === 'DELETE') {
        this.projects = this.projects.filter((p) => p.id !== payload.old.id)
      }
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useProjectsStore, import.meta.hot))
}
