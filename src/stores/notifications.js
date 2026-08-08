import { defineStore } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'
import { useBadge } from 'src/composables/useBadge'

export const useNotificationsStore = defineStore('notifications', {
  persist: ['unread'],

  state: () => ({
    unread: {},
  }),

  getters: {
    projectTotal: (state) => (projectId) => state.unread[projectId]?.total ?? 0,

    threadUnread:
      (state) =>
      ({ projectId, ideaId = null, bugId = null, tbiId = null, channel = 'main' }) => {
        const p = state.unread[projectId]
        if (!p) return 0
        if (ideaId) return p.ideas?.[ideaId] ?? 0
        if (bugId) return p.bugs?.[bugId] ?? 0
        if (tbiId) return p.tbi?.[tbiId] ?? 0
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
      // Offline: zadrži keširano stanje (upiti bi vratili prazno i pobrisali badge)
      if (!isOnline()) return

      const { data: enabledProjects } = await supabase
        .from('project_members')
        .select('project_id, notif_messages, notif_ideas, notif_bugs, notif_tbi')
        .eq('user_id', auth.user.id)
        .eq('badge_enabled', true)

      // Per-kategorija postavke: badge_enabled je glavni prekidač,
      // notif_* sužava koje kategorije se broje (null = uključeno, zbog starih redaka)
      const msgProjectIds = new Set(
        enabledProjects?.filter((p) => p.notif_messages !== false).map((p) => p.project_id) ?? [],
      )
      const ideaProjectIds = new Set(
        enabledProjects?.filter((p) => p.notif_ideas !== false).map((p) => p.project_id) ?? [],
      )
      const bugProjectIds = new Set(
        enabledProjects?.filter((p) => p.notif_bugs !== false).map((p) => p.project_id) ?? [],
      )
      const tbiProjectIds = new Set(
        enabledProjects?.filter((p) => p.notif_tbi !== false).map((p) => p.project_id) ?? [],
      )

      // Bez projekata s uključenim badgeom nema što računati —
      // ujedno izbjegava dohvat SVIH poruka iz baze (Supabase ionako reže na 1000 redaka)
      if (!enabledProjects?.length) {
        this.unread = {}
        await this.syncBadge()
        return
      }

      const emptyResult = Promise.resolve({ data: [] })

      const [
        { data: messages },
        { data: reads },
        { data: newIdeasData },
        { data: newBugsData },
        { data: newTbiData },
        { data: itemReads },
      ] = await Promise.all([
        msgProjectIds.size
          ? supabase
              .from('messages')
              .select('id, project_id, idea_id, bug_id, tbi_id, channel, author_id, created_at')
              .in('project_id', [...msgProjectIds])
              .neq('author_id', auth.user.id)
          : emptyResult,
        supabase.from('message_reads').select('*').eq('user_id', auth.user.id),
        ideaProjectIds.size
          ? supabase
              .from('ideas')
              .select('id, project_id, created_by')
              .in('project_id', [...ideaProjectIds])
              .neq('created_by', auth.user.id)
              .eq('promoted', false)
          : emptyResult,
        bugProjectIds.size
          ? supabase
              .from('bugs')
              .select('id, project_id, created_by')
              .in('project_id', [...bugProjectIds])
              .neq('created_by', auth.user.id)
              .neq('status', 'closed')
          : emptyResult,
        tbiProjectIds.size
          ? supabase
              .from('tbi_items')
              .select('id, project_id, created_by')
              .in('project_id', [...tbiProjectIds])
              .neq('created_by', auth.user.id)
              .neq('status', 'done')
          : emptyResult,
        supabase.from('item_reads').select('item_id, item_type').eq('user_id', auth.user.id),
      ])

      const readIdeaIds = new Set(
        itemReads?.filter((r) => r.item_type === 'idea').map((r) => r.item_id) ?? [],
      )
      const readBugIds = new Set(
        itemReads?.filter((r) => r.item_type === 'bug').map((r) => r.item_id) ?? [],
      )
      const readTbiIds = new Set(
        itemReads?.filter((r) => r.item_type === 'tbi').map((r) => r.item_id) ?? [],
      )

      const emptyProject = () => ({
        total: 0,
        channels: {},
        ideas: {},
        bugs: {},
        tbi: {},
        newIdeas: 0,
        newBugs: 0,
        newTbi: 0,
      })

      const result = {}

      // Poruke u threadovima i kanalima
      for (const msg of messages ?? []) {
        if (!msgProjectIds.has(msg.project_id)) continue
        const pid = msg.project_id
        if (!result[pid]) result[pid] = emptyProject()

        const read = reads?.find(
          (r) =>
            r.project_id === msg.project_id &&
            (r.idea_id ?? null) === (msg.idea_id ?? null) &&
            (r.bug_id ?? null) === (msg.bug_id ?? null) &&
            (r.tbi_id ?? null) === (msg.tbi_id ?? null) &&
            (r.channel ?? 'main') === (msg.channel ?? 'main'),
        )

        const isUnread = !read || new Date(msg.created_at) > new Date(read.last_read_at)
        if (!isUnread) continue

        result[pid].total++

        if (msg.idea_id) {
          result[pid].ideas[msg.idea_id] = (result[pid].ideas[msg.idea_id] ?? 0) + 1
        } else if (msg.bug_id) {
          result[pid].bugs[msg.bug_id] = (result[pid].bugs[msg.bug_id] ?? 0) + 1
        } else if (msg.tbi_id) {
          result[pid].tbi[msg.tbi_id] = (result[pid].tbi[msg.tbi_id] ?? 0) + 1
        } else {
          const ch = msg.channel ?? 'main'
          result[pid].channels[ch] = (result[pid].channels[ch] ?? 0) + 1
        }
      }

      // Nove ideje iz baze
      for (const idea of newIdeasData ?? []) {
        if (!ideaProjectIds.has(idea.project_id)) continue
        if (readIdeaIds.has(idea.id)) continue
        const pid = idea.project_id
        if (!result[pid]) result[pid] = emptyProject()
        result[pid].newIdeas++
        result[pid].total++
      }

      // Novi bugovi iz baze
      for (const bug of newBugsData ?? []) {
        if (!bugProjectIds.has(bug.project_id)) continue
        if (readBugIds.has(bug.id)) continue
        const pid = bug.project_id
        if (!result[pid]) result[pid] = emptyProject()
        result[pid].newBugs++
        result[pid].total++
      }

      // Novi tbi iz baze
      for (const item of newTbiData ?? []) {
        if (!tbiProjectIds.has(item.project_id)) continue
        if (readTbiIds.has(item.id)) continue
        const pid = item.project_id
        if (!result[pid]) result[pid] = emptyProject()
        result[pid].newTbi++
        result[pid].total++
      }

      // Propagiraj thread poruke u tab badge
      for (const pid of Object.keys(result)) {
        const p = result[pid]
        const ideaThreadUnread = Object.values(p.ideas).reduce((a, b) => a + b, 0)
        const bugThreadUnread = Object.values(p.bugs).reduce((a, b) => a + b, 0)
        const tbiThreadUnread = Object.values(p.tbi).reduce((a, b) => a + b, 0)
        p.newIdeas += ideaThreadUnread
        p.newBugs += bugThreadUnread
        p.newTbi += tbiThreadUnread
        // Ne dodavaj thread unread u total jer su već dodani kroz poruke petlju
      }

      this.unread = result
      await this.syncBadge()
    },

    async markRead({ projectId, ideaId = null, bugId = null, tbiId = null, channel = 'main' }) {
      const auth = useAuthStore()

      await supabase.rpc('upsert_message_read', {
        p_user_id: auth.user.id,
        p_project_id: projectId,
        p_idea_id: ideaId,
        p_bug_id: bugId,
        p_tbi_id: tbiId,
        p_channel: ideaId || bugId || tbiId ? null : channel,
      })

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

    async markItemRead(itemId, itemType) {
      const auth = useAuthStore()

      await supabase.from('item_reads').upsert(
        {
          user_id: auth.user.id,
          item_id: itemId,
          item_type: itemType,
          read_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,item_id,item_type' },
      )

      // Lokalno ažuriraj is_new
      await this.fetchUnread()
    },
  },
})
