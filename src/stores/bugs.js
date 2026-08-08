import { defineStore } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'
import { removeCachedImage } from 'src/utils/imageCache'
import { discardReplacedScreenshot } from 'src/utils/screenshots'

export const useBugsStore = defineStore('bugs', {
  persist: ['bugs'],

  state: () => ({
    bugs: [],
  }),

  getters: {
    open: (state) => state.bugs.filter((b) => b.status === 'open'),
    confirmed: (state) => state.bugs.filter((b) => b.status === 'confirmed'),
    promoted: (state) => state.bugs.filter((b) => b.status === 'promoted'),
  },

  actions: {
    async fetchBugs(projectId) {
      // Offline: zadrži keširano stanje
      if (!isOnline()) return
      const auth = useAuthStore()

      const { data, error } = await supabase
        .from('bugs')
        .select('*')
        .eq('project_id', projectId)
        .order('created_at', { ascending: false })
      if (error) throw error

      if (!data?.length) {
        this.bugs = []
        return
      }

      const userIds = [...new Set(data.map((b) => b.created_by).filter(Boolean))]
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, avatar_url')
        .in('id', userIds)

      const bugIds = data.map((b) => b.id)

      const [{ data: counts }, { data: reads }] = await Promise.all([
        supabase
          .from('thread_message_counts')
          .select('item_id, message_count')
          .eq('item_type', 'bug')
          .in('item_id', bugIds),
        supabase
          .from('item_reads')
          .select('item_id')
          .eq('user_id', auth.user.id)
          .eq('item_type', 'bug')
          .in('item_id', bugIds),
      ])

      // console.log('bugIds:', bugIds)
      // console.log('counts:', JSON.stringify(counts))

      const readIds = new Set(reads?.map((r) => r.item_id) ?? [])
      const mapped = data.map((b) => ({
        ...b,
        profiles: profiles?.find((p) => p.id === b.created_by) ?? null,
        message_count: Number(counts?.find((c) => c.item_id === b.id)?.message_count ?? 0),
        is_new: !readIds.has(b.id) && b.created_by !== auth.user.id && b.status !== 'closed',
      }))

      this.bugs = [...this.bugs.filter((b) => b.project_id !== projectId), ...mapped]
    },

    async createBug({
      projectId,
      title,
      description,
      priority,
      screenshotUrl = null,
      screenshotType = null,
      screenshotName = null,
    }) {
      const auth = useAuthStore()
      const { error } = await supabase.from('bugs').insert({
        project_id: projectId,
        title,
        description,
        priority,
        created_by: auth.user.id,
        screenshot_url: screenshotUrl,
        screenshot_type: screenshotType,
        screenshot_name: screenshotName,
      })
      if (error) throw error
      await this.fetchBugs(projectId)
    },

    async updateBug(id, updates) {
      // Optimistično: inline promjena statusa/prioriteta mora izgledati trenutna,
      // realtime UPDATE stigne kasnije i samo potvrdi isto stanje.
      const idx = this.bugs.findIndex((b) => b.id === id)
      const previous = idx !== -1 ? { ...this.bugs[idx] } : null
      if (idx !== -1) this.bugs[idx] = { ...this.bugs[idx], ...updates }

      const { error } = await supabase.from('bugs').update(updates).eq('id', id)
      if (error) {
        if (previous) this.bugs[idx] = previous
        throw error
      }

      await discardReplacedScreenshot(previous?.screenshot_url, updates.screenshot_url)
    },

    async deleteBug(id) {
      const bug = this.bugs.find((b) => b.id === id)
      const projectId = bug?.project_id
      if (bug?.screenshot_url) {
        await supabase.storage.from('chat-attachments').remove([bug.screenshot_url])
        await removeCachedImage(bug.screenshot_url)
      }
      const { error } = await supabase.from('bugs').delete().eq('id', id)
      if (error) throw error
      if (projectId) await this.fetchBugs(projectId)
    },

    async promoteToBug(bug) {
      const { useTbiStore } = await import('./tbi')
      const tbiStore = useTbiStore()

      await tbiStore.createItem({
        projectId: bug.project_id,
        bugId: bug.id,
        sourceType: 'bug',
        title: bug.title,
        description: bug.description,
        priority: bug.priority,
      })

      await this.updateBug(bug.id, {
        status: 'promoted',
        promoted_at: new Date().toISOString(),
      })
    },

    handleIncoming({ event, payload }) {
      if (event === 'INSERT') {
        if (!this.bugs.find((b) => b.id === payload.new.id)) {
          this.bugs.unshift(payload.new)
        }
      }
      if (event === 'UPDATE') {
        const idx = this.bugs.findIndex((b) => b.id === payload.new.id)
        if (idx !== -1) {
          this.bugs[idx] = { ...this.bugs[idx], ...payload.new }
        }
      }
      if (event === 'DELETE') {
        this.bugs = this.bugs.filter((b) => b.id !== payload.old.id)
      }
    },
  },
})
