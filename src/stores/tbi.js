import { defineStore } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'
import { removeCachedImage } from 'src/utils/imageCache'
import { discardReplacedScreenshot } from 'src/utils/screenshots'

export const useTbiStore = defineStore('tbi', {
  persist: ['items'],

  state: () => ({
    items: [],
  }),

  getters: {
    pending: (state) => state.items.filter((i) => i.status !== 'done'),
    done: (state) => state.items.filter((i) => i.status === 'done'),
    byStatus: (state) => (status) => state.items.filter((i) => i.status === status),
    bySource: (state) => (source) => state.items.filter((i) => i.source_type === source),
  },

  actions: {
    async fetchItems(projectId) {
      // Offline: zadrži keširano stanje
      if (!isOnline()) return
      const auth = useAuthStore()

      const { data, error } = await supabase
        .from('tbi_items')
        .select('*')
        .eq('project_id', projectId)
        .order('created_at', { ascending: false })
      if (error) throw error

      if (!data?.length) {
        this.items = []
        return
      }

      const userIds = [
        ...new Set(
          [...data.map((i) => i.created_by), ...data.map((i) => i.assignee_id)].filter(Boolean),
        ),
      ]

      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, avatar_url')
        .in('id', userIds)

      const tbiIds = data.map((i) => i.id)
      const ideaIds = data.map((i) => i.idea_id).filter(Boolean)
      const bugIds = data.map((i) => i.bug_id).filter(Boolean)
      const allIds = [...tbiIds, ...ideaIds, ...bugIds]

      const [{ data: counts }, { data: reads }] = await Promise.all([
        supabase
          .from('thread_message_counts')
          .select('item_id, item_type, message_count')
          .in('item_id', allIds),
        supabase
          .from('item_reads')
          .select('item_id')
          .eq('user_id', auth.user.id)
          .eq('item_type', 'tbi')
          .in('item_id', tbiIds),
      ])

      // console.log('tbi counts:', JSON.stringify(counts))

      const readIds = new Set(reads?.map((r) => r.item_id) ?? [])

      // this.items = data.map((i) => {
      const mapped = data.map((i) => {
        const tbiCount =
          counts?.find((c) => c.item_id === i.id && c.item_type === 'tbi')?.message_count ?? 0
        const ideaCount =
          counts?.find((c) => c.item_id === i.idea_id && c.item_type === 'idea')?.message_count ?? 0
        const bugCount =
          counts?.find((c) => c.item_id === i.bug_id && c.item_type === 'bug')?.message_count ?? 0

        return {
          ...i,
          profiles: profiles?.find((p) => p.id === i.created_by) ?? null,
          assignee: profiles?.find((p) => p.id === i.assignee_id) ?? null,
          message_count: Number(tbiCount) + Number(ideaCount) + Number(bugCount),
          is_new: !readIds.has(i.id) && i.created_by !== auth.user.id && i.status !== 'done',
        }
      })

      this.items = [...this.items.filter((i) => i.project_id !== projectId), ...mapped]
    },

    async createItem({
      projectId,
      title,
      description,
      priority = 'med',
      ideaId = null,
      bugId = null,
      sourceType = 'manual',
      screenshotUrl = null,
      screenshotType = null,
      screenshotName = null,
    }) {
      const auth = useAuthStore()
      const { error } = await supabase.from('tbi_items').insert({
        project_id: projectId,
        title,
        description,
        priority,
        idea_id: ideaId,
        bug_id: bugId,
        source_type: sourceType,
        created_by: auth.user.id,
        promoted_at: ideaId || bugId ? new Date().toISOString() : null,
        screenshot_url: screenshotUrl,
        screenshot_type: screenshotType,
        screenshot_name: screenshotName,
      })
      if (error) throw error
    },

    async updateItem(id, updates) {
      const previousScreenshot = this.items.find((i) => i.id === id)?.screenshot_url
      const { error } = await supabase.from('tbi_items').update(updates).eq('id', id)
      if (error) throw error
      await discardReplacedScreenshot(previousScreenshot, updates.screenshot_url)
    },

    async markDone(id) {
      await this.updateItem(id, {
        status: 'done',
        completed_at: new Date().toISOString(),
      })
    },

    async markUndone(id) {
      await this.updateItem(id, {
        status: 'tbi',
        completed_at: null,
      })
    },

    async assignUser(id, userId) {
      await this.updateItem(id, { assignee_id: userId })
    },

    async deleteItem(id) {
      const item = this.items.find((i) => i.id === id)
      if (item?.screenshot_url) {
        await supabase.storage.from('chat-attachments').remove([item.screenshot_url])
        await removeCachedImage(item.screenshot_url)
      }
      const { error } = await supabase.from('tbi_items').delete().eq('id', id)
      if (error) throw error
    },

    handleIncoming({ event, payload }) {
      if (event === 'INSERT') {
        if (!this.items.find((i) => i.id === payload.new.id)) {
          this.items.unshift(payload.new)
        }
      }
      if (event === 'UPDATE') {
        const idx = this.items.findIndex((i) => i.id === payload.new.id)
        if (idx !== -1) {
          this.items[idx] = { ...this.items[idx], ...payload.new }
        }
      }
      if (event === 'DELETE') {
        this.items = this.items.filter((i) => i.id !== payload.old.id)
      }
    },
  },
})
