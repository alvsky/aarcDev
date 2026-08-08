import { defineStore } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'
import { removeCachedImage } from 'src/utils/imageCache'
import { discardReplacedScreenshot } from 'src/utils/screenshots'

export const useIdeasStore = defineStore('ideas', {
  persist: ['ideas'],

  state: () => ({
    ideas: [],
  }),

  getters: {
    active: (state) => state.ideas.filter((i) => !i.promoted),
    promoted: (state) => state.ideas.filter((i) => i.promoted),
  },

  actions: {
    async fetchIdeas(projectId) {
      // Offline: zadrži keširano stanje
      if (!isOnline()) return
      const auth = useAuthStore()

      const { data, error } = await supabase
        .from('ideas')
        .select('*')
        .eq('project_id', projectId)
        .order('created_at', { ascending: false })
      if (error) throw error

      if (!data?.length) {
        this.ideas = []
        return
      }

      const userIds = [...new Set(data.map((i) => i.created_by).filter(Boolean))]
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, avatar_url')
        .in('id', userIds)

      const ideaIds = data.map((i) => i.id)

      const [{ data: counts }, { data: reads }] = await Promise.all([
        supabase
          .from('thread_message_counts')
          .select('item_id, message_count')
          .eq('item_type', 'idea')
          .in('item_id', ideaIds),
        supabase
          .from('item_reads')
          .select('item_id')
          .eq('user_id', auth.user.id)
          .eq('item_type', 'idea')
          .in('item_id', ideaIds),
      ])

      const readIds = new Set(reads?.map((r) => r.item_id) ?? [])

      const mapped = data.map((i) => ({
        ...i,
        profiles: profiles?.find((p) => p.id === i.created_by) ?? null,
        message_count: Number(counts?.find((c) => c.item_id === i.id)?.message_count ?? 0),
        is_new: !readIds.has(i.id) && i.created_by !== auth.user.id,
      }))

      this.ideas = [...this.ideas.filter((i) => i.project_id !== projectId), ...mapped]

      // console.log(
      //   'Ideas is_new:',
      //   this.ideas.map((i) => ({ title: i.title, is_new: i.is_new })),
      // )
    },

    async createIdea({
      projectId,
      title,
      description,
      screenshotUrl = null,
      screenshotType = null,
      screenshotName = null,
    }) {
      const auth = useAuthStore()
      const { error } = await supabase.from('ideas').insert({
        project_id: projectId,
        title,
        description,
        created_by: auth.user.id,
        screenshot_url: screenshotUrl,
        screenshot_type: screenshotType,
        screenshot_name: screenshotName,
      })
      if (error) throw error
      await this.fetchIdeas(projectId)
    },

    async updateIdea(id, updates) {
      const previousScreenshot = this.ideas.find((i) => i.id === id)?.screenshot_url
      const { error } = await supabase.from('ideas').update(updates).eq('id', id)
      if (error) throw error
      await discardReplacedScreenshot(previousScreenshot, updates.screenshot_url)
    },

    async deleteIdea(id) {
      const idea = this.ideas.find((i) => i.id === id)
      const projectId = idea?.project_id
      if (idea?.screenshot_url) {
        await supabase.storage.from('chat-attachments').remove([idea.screenshot_url])
        await removeCachedImage(idea.screenshot_url)
      }
      const { error } = await supabase.from('ideas').delete().eq('id', id)
      if (error) throw error
      if (projectId) await this.fetchIdeas(projectId)
    },

    async promoteToTbi(idea) {
      const { useTbiStore } = await import('./tbi')
      const tbiStore = useTbiStore()

      await tbiStore.createItem({
        projectId: idea.project_id,
        ideaId: idea.id,
        sourceType: 'idea',
        title: idea.title,
        description: idea.description,
      })

      await this.updateIdea(idea.id, { promoted: true })
    },

    async demoteFromTbi(tbiItem) {
      console.log('demoteFromTbi called with:', JSON.stringify(tbiItem))

      const { error } = await supabase.from('tbi_items').delete().eq('id', tbiItem.id)

      console.log('TBI delete error:', error)

      // Vrati ideju
      if (tbiItem.idea_id) {
        const { error: ideaError } = await supabase
          .from('ideas')
          .update({ promoted: false })
          .eq('id', tbiItem.idea_id)

        console.log('Idea update error:', ideaError)

        await this.fetchIdeas(tbiItem.project_id)
      }

      // Refreshaj TBI listu
      const { useTbiStore } = await import('./tbi')
      const tbiStore = useTbiStore()
      await tbiStore.fetchItems(tbiItem.project_id)
    },

    handleIncoming({ event, payload }) {
      if (event === 'INSERT') {
        if (!this.ideas.find((i) => i.id === payload.new.id)) {
          this.ideas.unshift(payload.new)
        }
      }
      if (event === 'UPDATE') {
        const idx = this.ideas.findIndex((i) => i.id === payload.new.id)
        if (idx !== -1) {
          this.ideas[idx] = { ...this.ideas[idx], ...payload.new }
        }
      }
      if (event === 'DELETE') {
        this.ideas = this.ideas.filter((i) => i.id !== payload.old.id)
      }
    },
  },
})
