import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'
import { useBadge } from 'src/composables/useBadge'

// Brojanje živi u bazi (get_unread RPC), ne ovdje. Klijent je prije dohvaćao SVE
// poruke svih svojih projekata da bi ih prebrojao; sada dobiva nekoliko desetaka
// gotovih redaka i samo ih posloži.
//
// Pravilo "jedna stavka, jedan badge" je time također u SQL-u
// (item_tab_new / item_tab_thread) — na jednom mjestu umjesto dva.

const TAB_KEY = { ideas: 'newIdeas', bugs: 'newBugs', tbi: 'newTbi' }

const emptyProject = () => ({
  total: 0,
  channels: {},
  items: {},
  newIdeas: 0,
  newBugs: 0,
  newTbi: 0,
})

export const useNotificationsStore = defineStore('notifications', {
  persist: ['unread'],

  state: () => ({
    unread: {},
  }),

  getters: {
    projectTotal: (state) => (projectId) => state.unread[projectId]?.total ?? 0,

    threadUnread:
      (state) =>
      ({ projectId, itemId = null, channel = 'main' }) => {
        const p = state.unread[projectId]
        if (!p) return 0
        if (itemId) return p.items?.[itemId] ?? 0
        return p.channels?.[channel] ?? 0
      },

    newIdeas: (state) => (projectId) => state.unread[projectId]?.newIdeas ?? 0,
    newBugs: (state) => (projectId) => state.unread[projectId]?.newBugs ?? 0,
    newTbi: (state) => (projectId) => state.unread[projectId]?.newTbi ?? 0,

    anyUnread: (state) => Object.values(state.unread).some((p) => p.total > 0),
  },

  actions: {
    async fetchUnread() {
      const auth = useAuthStore()
      if (!auth.user) return
      // Offline: zadrži keširano stanje (prazan odgovor bi pobrisao badge)
      if (!isOnline()) return

      const { data, error } = await supabase.rpc('get_unread')
      if (error) {
        console.error('[unread] get_unread:', error)
        return
      }

      const result = {}
      const ensure = (pid) => {
        if (!result[pid]) result[pid] = emptyProject()
        return result[pid]
      }

      for (const row of data ?? []) {
        const p = ensure(row.project_id)

        // Svaki redak ulazi u ukupan zbroj točno jednom.
        p.total += row.n

        if (row.scope === 'channel') {
          p.channels[row.ref] = (p.channels[row.ref] ?? 0) + row.n
        } else if (row.scope === 'thread') {
          p.items[row.ref] = (p.items[row.ref] ?? 0) + row.n
        }

        // Kartica: nove stavke i poruke threadova zbrajaju se u istu.
        const tabKey = TAB_KEY[row.tab]
        if (tabKey) p[tabKey] += row.n
      }

      this.unread = result
      await this.syncBadge()
    },

    // Vodenokaz threada. message_reads ima obični unique indeks
    // (NULLS NOT DISTINCT), pa upsert ide izravno — bez RPC-a.
    async markRead({ projectId, itemId = null, channel = 'main' }) {
      const auth = useAuthStore()

      const { error } = await supabase.from('message_reads').upsert(
        {
          user_id: auth.user.id,
          project_id: projectId,
          item_id: itemId,
          channel: itemId ? null : channel,
          last_read_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,project_id,item_id,channel' },
      )
      if (error) throw error

      await this.fetchUnread()
    },

    async registerPushToken(token, platform) {
      const auth = useAuthStore()
      if (!auth.user) return
      await supabase.from('push_tokens').upsert(
        {
          user_id: auth.user.id,
          token,
          platform,
        },
        { onConflict: 'user_id,token' },
      )
    },

    async syncBadge() {
      const { setBadge, clearBadge } = useBadge()
      const total = Object.values(this.unread).reduce((sum, p) => sum + (p.total ?? 0), 0)
      if (total > 0) {
        await setBadge(total)
      } else {
        await clearBadge()
      }
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useNotificationsStore, import.meta.hot))
}
