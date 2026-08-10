import { defineStore } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { isOnline } from 'src/composables/useNetwork'

export const useProjectsStore = defineStore('projects', {
  persist: ['projects'],

  state: () => ({
    projects: [],
  }),

  getters: {
    getById: (state) => (id) => state.projects.find((p) => p.id === id),
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

    async addMember(projectId, email) {
      const { data: profile, error } = await supabase
        .from('profiles')
        .select('id')
        .eq('email', email)
        .single()
      if (error || !profile) throw new Error('Korisnik nije pronađen')

      const { error: memberError } = await supabase.from('project_members').insert({
        project_id: projectId,
        user_id: profile.id,
        role: 'member',
      })
      if (memberError) throw memberError
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

    async changeRole(projectId, userId, role) {
      const { error } = await supabase
        .from('project_members')
        .update({ role })
        .eq('project_id', projectId)
        .eq('user_id', userId)
      if (error) throw error
      await this.fetchProjects()
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
