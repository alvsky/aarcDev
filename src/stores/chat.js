import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'
import { removeCachedImage } from 'src/utils/imageCache'

// Mrežna greška (fetch pao — nema veze) vs. Postgres greška (RLS, constraint...):
// samo mrežne idu u outbox, ostale se bacaju kao i dosad
function isNetworkError(error) {
  const msg = String(error?.message ?? error ?? '')
  return msg.includes('Failed to fetch') || msg.includes('NetworkError') || msg.includes('fetch')
}

let flushing = false

export const useChatStore = defineStore('chat', {
  persist: ['threads', 'outbox'],

  state: () => ({
    threads: {},
    outbox: [],
    // I4: skeleton umjesto prazne liste, samo dok stvarno nema ničega u kešu.
    loadingThreads: {},
  }),

  getters: {
    threadMessages: (state) => (key) => state.threads[key] ?? [],
    threadCount: (state) => (key) => state.threads[key]?.length ?? 0,
    isLoadingThread: (state) => (key) => !!state.loadingThreads[key],
  },

  actions: {
    // Thread = jedna stavka (item_id) ili jedan kanal. Prije su bila tri odvojena
    // id-a, pa je promovirana ideja imala dva threada — vidi docs/item-model.md.
    threadKey({ projectId, itemId = null, channel = 'main' }) {
      if (itemId) return `${projectId}:item:${itemId}`
      return `${projectId}:${channel}`
    },

    async fetchMessages({ projectId, itemId = null, channel = 'main' }) {
      const key = this.threadKey({ projectId, itemId, channel })
      this.loadingThreads[key] = true
      try {
        let query = supabase
          .from('messages')
          .select('*')
          .eq('project_id', projectId)
          .order('created_at', { ascending: true })

        if (itemId) query = query.eq('item_id', itemId)
        else query = query.is('item_id', null).eq('channel', channel)

        const { data, error } = await query
        // Offline/mrežni pad: zadrži keširani thread umjesto bacanja greške
        if (error) {
          if (isNetworkError(error)) return
          throw error
        }

        // Optimistične (outbox) poruke ovog threada — fetch ih ne smije pobrisati iz prikaza
        const pendingMsgs = (this.threads[key] ?? []).filter((m) => m.pending || m.failed)

        if (!data?.length) {
          this.threads[key] = pendingMsgs
          return
        }

        const userIds = [...new Set(data.map((m) => m.author_id).filter(Boolean))]
        const { data: profiles } = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .in('id', userIds)

        // Na kraju fetchMessages, prije this.threads[key] = ...
        const messageIds = data.map((m) => m.id)
        const reactions = await this.fetchReactions(messageIds)

        this.threads[key] = [
          ...data.map((m) => ({
            ...m,
            profiles: profiles?.find((p) => p.id === m.author_id) ?? null,
            reactions: reactions[m.id] ?? [],
          })),
          ...pendingMsgs,
        ]
      } finally {
        this.loadingThreads[key] = false
      }
    },

    async sendMessage(payload) {
      const {
        projectId,
        body,
        itemId = null,
        channel = 'main',
        attachmentUrl = null,
        attachmentType = null,
        attachmentName = null,
        replyToId = null,
      } = payload
      const auth = useAuthStore()

      // Offline (samo tekstualne poruke — prilozi traže mrežu i UI ih već blokira)
      if (!isOnline() && !attachmentUrl) {
        this.queueMessage(payload)
        return
      }

      const { error } = await supabase.from('messages').insert({
        project_id: projectId,
        author_id: auth.user.id,
        body: body || '',
        item_id: itemId,
        channel: itemId ? null : channel,
        attachment_url: attachmentUrl,
        attachment_type: attachmentType,
        attachment_name: attachmentName,
        reply_to_id: replyToId,
      })
      if (error) {
        // Mrežni pad usred slanja → u outbox; Postgres greške se bacaju kao i dosad
        if (isNetworkError(error) && !attachmentUrl) {
          this.queueMessage(payload)
          return
        }
        throw error
      }
      // Ne pozivaj fetchMessages — realtime će dodati poruku
      if (this.outbox.length) this.flushOutbox()
    },

    queueMessage(payload) {
      const auth = useAuthStore()
      const tempId = `temp-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
      const { projectId, itemId = null, channel = 'main' } = payload

      this.outbox.push({
        tempId,
        ...payload,
        createdAt: new Date().toISOString(),
        attempts: 0,
        lastError: null,
        failed: false,
      })

      // Optimistična poruka u threadu (pending) — realtime echo je zamijeni nakon slanja
      const key = this.threadKey({ projectId, itemId, channel })
      if (!this.threads[key]) this.threads[key] = []
      this.threads[key].push({
        id: tempId,
        project_id: projectId,
        item_id: itemId,
        channel: itemId ? null : channel,
        author_id: auth.user.id,
        body: payload.body || '',
        reply_to_id: payload.replyToId ?? null,
        created_at: new Date().toISOString(),
        profiles: { id: auth.user.id, full_name: auth.fullName },
        reactions: [],
        pending: true,
      })
    },

    async flushOutbox() {
      if (flushing || !this.outbox.length || !isOnline()) return
      flushing = true
      const auth = useAuthStore()
      if (!auth.user) {
        flushing = false
        return
      }

      try {
        // FIFO; na mrežnu grešku stani (pokušat će opet na sljedeći trigger)
        while (this.outbox.length) {
          const item = this.outbox.find((i) => !i.failed)
          if (!item) break

          const { error } = await supabase.from('messages').insert({
            project_id: item.projectId,
            author_id: auth.user.id,
            body: item.body || '',
            item_id: item.itemId ?? null,
            channel: item.itemId ? null : (item.channel ?? 'main'),
            reply_to_id: item.replyToId ?? null,
          })

          if (error) {
            item.attempts++
            item.lastError = error.message
            if (isNetworkError(error)) {
              if (item.attempts >= 5) {
                item.failed = true
                this.markOptimistic(item.tempId, { pending: false, failed: true })
              }
              break
            }
            // Postgres greška — nema smisla ponavljati
            item.failed = true
            this.markOptimistic(item.tempId, { pending: false, failed: true })
            continue
          }

          // Uspjeh: makni iz outboxa i makni optimističnu poruku (realtime echo nosi pravu)
          this.outbox = this.outbox.filter((i) => i.tempId !== item.tempId)
          this.removeOptimistic(item.tempId)
        }
      } finally {
        flushing = false
      }
    },

    markOptimistic(tempId, patch) {
      for (const key of Object.keys(this.threads)) {
        const idx = this.threads[key]?.findIndex((m) => m.id === tempId)
        if (idx !== -1 && idx !== undefined) {
          this.threads[key][idx] = { ...this.threads[key][idx], ...patch }
          return
        }
      }
    },

    removeOptimistic(tempId) {
      for (const key of Object.keys(this.threads)) {
        if (this.threads[key]?.some((m) => m.id === tempId)) {
          this.threads[key] = this.threads[key].filter((m) => m.id !== tempId)
          return
        }
      }
    },

    retryOutboxItem(tempId) {
      const item = this.outbox.find((i) => i.tempId === tempId)
      if (!item) return
      item.failed = false
      item.attempts = 0
      item.lastError = null
      this.markOptimistic(tempId, { pending: true, failed: false })
      this.flushOutbox()
    },

    removeOutboxItem(tempId) {
      this.outbox = this.outbox.filter((i) => i.tempId !== tempId)
      this.removeOptimistic(tempId)
    },

    async deleteMessage(id, ctx) {
      // Dohvati poruku da vidimo ima li attachment
      const msg = Object.values(this.threads)
        .flat()
        .find((m) => m.id === id)

      // Obriši sliku iz Storagea i lokalnog keša ako postoji
      if (msg?.attachment_url) {
        await supabase.storage.from('chat-attachments').remove([msg.attachment_url])
        await removeCachedImage(msg.attachment_url)
      }

      await supabase.from('messages').delete().eq('id', id)

      const key = this.threadKey(ctx)
      if (this.threads[key]) {
        this.threads[key] = this.threads[key].filter((m) => m.id !== id)
      }
    },

    async handleIncoming({ event, payload }) {
      // console.log('handleIncoming:', event, payload.new?.id)
      // console.log('handleIncoming event:', event, 'payload.new:', payload.new?.id)
      const msg = payload.new
      if (!msg) return

      const key = this.threadKey({
        projectId: msg.project_id,
        itemId: msg.item_id,
        channel: msg.channel ?? 'main',
      })

      if (event === 'INSERT') {
        if (!this.threads[key]) this.threads[key] = []
        if (this.threads[key].find((m) => m.id === msg.id)) return

        const { data: profile } = await supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .eq('id', msg.author_id)
          .single()

        this.threads[key].push({ ...msg, profiles: profile, reactions: [] })
      }

      if (event === 'UPDATE') {
        // Ažuriraj editiranu poruku
        for (const k of Object.keys(this.threads)) {
          const idx = this.threads[k]?.findIndex((m) => m.id === msg.id)
          if (idx !== -1 && idx !== undefined) {
            this.threads[k][idx] = {
              ...this.threads[k][idx],
              body: msg.body,
              edited_at: msg.edited_at,
            }
            break
          }
        }
      }

      if (event === 'DELETE') {
        const old = payload.old
        for (const k of Object.keys(this.threads)) {
          if (this.threads[k]) {
            this.threads[k] = this.threads[k].filter((m) => m.id !== old.id)
          }
        }
      }
    },

    async fetchReactions(messageIds) {
      if (!messageIds?.length) return {}

      const validIds = messageIds.filter(Boolean)
      if (!validIds.length) return {}

      const { data, error } = await supabase
        .from('message_reactions')
        .select('id, message_id, user_id, emoji, created_at')
        .in('message_id', validIds)

      if (error) {
        console.error('fetchReactions error:', error)
        return {}
      }

      if (!data?.length) return {}

      // Dohvati profile odvojeno
      const userIds = [...new Set(data.map((r) => r.user_id))]
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, avatar_url')
        .in('id', userIds)

      const grouped = {}
      for (const r of data) {
        if (!grouped[r.message_id]) grouped[r.message_id] = []
        grouped[r.message_id].push({
          ...r,
          profiles: profiles?.find((p) => p.id === r.user_id) ?? null,
        })
      }
      return grouped
    },

    async toggleReaction(messageId, emoji) {
      const auth = useAuthStore()

      const { data: existing } = await supabase
        .from('message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('user_id', auth.user.id)
        .eq('emoji', emoji)
        .maybeSingle() // ← koristi maybeSingle umjesto single

      if (existing) {
        await supabase.from('message_reactions').delete().eq('id', existing.id)
      } else {
        await supabase.from('message_reactions').insert({
          message_id: messageId,
          user_id: auth.user.id,
          emoji,
        })
      }

      // Osvježi reakcije za tu poruku u svim threadovima
      for (const key of Object.keys(this.threads)) {
        const msg = this.threads[key]?.find((m) => m.id === messageId)
        if (msg) {
          const reactions = await this.fetchReactions([messageId])
          msg.reactions = reactions[messageId] ?? []
          break
        }
      }
    },

    async editMessage(id, body) {
      console.log('editMessage called:', id, body)
      const { data, error } = await supabase
        .from('messages')
        .update({ body, edited_at: new Date().toISOString() })
        .eq('id', id)
      console.log('edit result:', data, error)
      if (error) throw error
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useChatStore, import.meta.hot))
}
