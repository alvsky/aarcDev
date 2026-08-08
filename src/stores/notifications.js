import { defineStore } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'
import { useBadge } from 'src/composables/useBadge'

// Jedna stavka — jedan badge (docs/item-model.md).
//
// Stavka smije biti vidljiva u dvije kartice (prihvaćeni bug je i u registru
// bugova i na TBI ploči), ali se broji točno u JEDNOJ — onoj gdje traži pažnju.
// Vidljivost i brojanje su namjerno odvojeni.
// Aktivan rad — sve tri faze pripadaju TBI ploči.
const ACTIVE_STAGES = ['accepted', 'in_progress', 'testing']
const TERMINAL_STAGES = ['done', 'rejected']

function tabForNewItem(item) {
  if (!item) return null
  if (ACTIVE_STAGES.includes(item.stage)) return 'newTbi'
  if (TERMINAL_STAGES.includes(item.stage)) return null
  if (item.kind === 'bug') return 'newBugs'
  if (item.kind === 'idea') return 'newIdeas'
  return null // zadatak izvan aktivnog rada nema svoju karticu
}

// Za NEPROČITANE PORUKE vrijedi drukčije pravilo nego za nove stavke: poruka je
// stvaran signal i kad je stavka zatvorena, pa se pripisuje kartici u kojoj se
// stavka može PRONAĆI. Inače bi nastao badge koji se ne da otvoriti — točno ona
// greška zbog koje je cijeli ovaj model i nastao.
//
// ⚠️ Uvjet za sučelje: zadani filtar kartice mora prikazati stavku koja ima
// nepročitanih poruka, čak i ako je u fazi done/rejected.
function tabForThread(item) {
  if (!item) return null
  if (ACTIVE_STAGES.includes(item.stage)) return 'newTbi'
  if (item.kind === 'bug') return 'newBugs'
  if (item.kind === 'idea') return 'newIdeas'
  return 'newTbi'
}

const PREF_BY_TAB = {
  newIdeas: 'notif_ideas',
  newBugs: 'notif_bugs',
  newTbi: 'notif_tbi',
}

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
      // Offline: zadrži keširano stanje (upiti bi vratili prazno i pobrisali badge)
      if (!isOnline()) return

      const { data: enabledProjects } = await supabase
        .from('project_members')
        .select('project_id, notif_messages, notif_ideas, notif_bugs, notif_tbi')
        .eq('user_id', auth.user.id)
        .eq('badge_enabled', true)

      // Bez projekata s uključenim badgeom nema što računati —
      // ujedno izbjegava dohvat SVIH poruka iz baze
      if (!enabledProjects?.length) {
        this.unread = {}
        await this.syncBadge()
        return
      }

      const projectIds = enabledProjects.map((p) => p.project_id)
      const prefs = new Map(enabledProjects.map((p) => [p.project_id, p]))
      // badge_enabled je glavni prekidač, notif_* sužava kategorije
      // (null = uključeno, zbog starih redaka)
      const msgProjectIds = enabledProjects
        .filter((p) => p.notif_messages !== false)
        .map((p) => p.project_id)

      const allowed = (projectId, tab) => prefs.get(projectId)?.[PREF_BY_TAB[tab]] !== false

      const [{ data: messages }, { data: reads }, { data: items }, { data: states }] =
        await Promise.all([
          msgProjectIds.length
            ? supabase
                .from('messages')
                .select('id, project_id, item_id, channel, author_id, created_at')
                .in('project_id', msgProjectIds)
                .neq('author_id', auth.user.id)
            : Promise.resolve({ data: [] }),
          supabase.from('message_reads').select('*').eq('user_id', auth.user.id),
          // Sve stavke, ne samo nepročitane — trebaju i pročitane da bi se
          // nepročitane poruke znale pripisati pravoj kartici.
          supabase
            .from('items')
            .select('id, project_id, kind, stage, created_by')
            .in('project_id', projectIds),
          supabase.from('item_user_state').select('item_id, read_at').eq('user_id', auth.user.id),
        ])

      const readItemIds = new Set((states ?? []).filter((s) => s.read_at).map((s) => s.item_id))
      const itemById = new Map((items ?? []).map((i) => [i.id, i]))

      const result = {}
      const ensure = (pid) => {
        if (!result[pid]) result[pid] = emptyProject()
        return result[pid]
      }

      // 1) Nove stavke koje korisnik nije otvorio
      for (const item of items ?? []) {
        if (item.created_by === auth.user.id) continue
        if (readItemIds.has(item.id)) continue
        const tab = tabForNewItem(item)
        if (!tab || !allowed(item.project_id, tab)) continue
        const p = ensure(item.project_id)
        p[tab]++
        p.total++
      }

      // 2) Nepročitane poruke u threadovima i kanalima
      for (const msg of messages ?? []) {
        const read = reads?.find(
          (r) =>
            r.project_id === msg.project_id &&
            (r.item_id ?? null) === (msg.item_id ?? null) &&
            (r.channel ?? 'main') === (msg.channel ?? 'main'),
        )

        const isUnread = !read || new Date(msg.created_at) > new Date(read.last_read_at)
        if (!isUnread) continue

        const p = ensure(msg.project_id)
        p.total++

        if (msg.item_id) {
          p.items[msg.item_id] = (p.items[msg.item_id] ?? 0) + 1
        } else {
          const ch = msg.channel ?? 'main'
          p.channels[ch] = (p.channels[ch] ?? 0) + 1
        }
      }

      // 3) Poruke threadova propagiraj u badge kartice — po fazi stavke.
      // Total se NE povećava, već je zbrojen u koraku 2.
      for (const pid of Object.keys(result)) {
        const p = result[pid]
        for (const [itemId, count] of Object.entries(p.items)) {
          const tab = tabForThread(itemById.get(itemId))
          if (!tab || !allowed(pid, tab)) continue
          p[tab] += count
        }
      }

      this.unread = result
      await this.syncBadge()
    },

    // Vodenokaz threada. Otkad message_reads ima obični unique indeks
    // (NULLS NOT DISTINCT), upsert ide izravno — RPC više ne postoji, a s njim
    // je otpala i rupa u kojoj se p_user_id slao iz poziva bez provjere.
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
