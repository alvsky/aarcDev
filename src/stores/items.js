import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from './auth'
import { isOnline } from 'src/composables/useNetwork'
import { removeCachedImage } from 'src/utils/imageCache'
import { discardReplacedScreenshot } from 'src/utils/screenshots'

// Jedan store za ideje, bugove i zadatke — vidi docs/item-model.md.
// Zamjenjuje ideas/bugs/tbi storove; oni se brišu u M6, kad se stranice prebace.
//
// Kartice su POGLEDI, ne ladice: ista stavka smije biti u dva pogleda (prihvaćeni
// bug je i u Bugovima i na TBI ploči). Brojanje je odvojeno od vidljivosti —
// badge ide samo tamo gdje stavka traži pažnju, po fazi.

// Aktivan rad — sve tri faze pripadaju TBI ploči.
const ACTIVE_STAGES = ['accepted', 'in_progress', 'testing']
const TERMINAL_STAGES = ['done', 'rejected']

export const useItemsStore = defineStore('items', {
  persist: ['items'],

  state: () => ({
    items: [],
  }),

  getters: {
    byProject: (state) => (projectId) => state.items.filter((i) => i.project_id === projectId),

    // Getteri vraćaju DOMENU kartice (što joj uopće pripada). Skrivanje
    // zatvorenih je stvar filtra u sučelju, ne domene — inače bi stavka s
    // nepročitanom porukom mogla postati nedohvatljiva.

    // Lijevak: ideje koje nisu otišle na ploču.
    ideas: (state) => (projectId) =>
      state.items.filter(
        (i) => i.project_id === projectId && i.kind === 'idea' && !ACTIVE_STAGES.includes(i.stage),
      ),

    // Registar: svi bugovi, sve faze — "je li ovo već prijavljeno?" je česta potreba.
    bugs: (state) => (projectId) =>
      state.items.filter((i) => i.project_id === projectId && i.kind === 'bug'),

    // Ploča: aktivan rad, plus ono što je kroz njega prošlo pa završilo.
    tbi: (state) => (projectId) =>
      state.items.filter(
        (i) =>
          i.project_id === projectId &&
          (ACTIVE_STAGES.includes(i.stage) || (TERMINAL_STAGES.includes(i.stage) && i.accepted_at)),
      ),

    watching: (state) => (projectId) =>
      state.items.filter((i) => i.project_id === projectId && i.watching),

    byId: (state) => (id) => state.items.find((i) => i.id === id) ?? null,
  },

  actions: {
    async fetchItems(projectId) {
      // Offline: zadrži keširano stanje
      if (!isOnline()) return
      const auth = useAuthStore()

      const { data, error } = await supabase
        .from('items')
        .select('*')
        .eq('project_id', projectId)
        .order('created_at', { ascending: false })
      if (error) throw error

      if (!data?.length) {
        // Makni samo ovaj projekt — stavke drugih projekata ostaju (invarijanta 6)
        this.items = this.items.filter((i) => i.project_id !== projectId)
        return
      }

      const ids = data.map((i) => i.id)
      const userIds = [
        ...new Set(
          [
            ...data.map((i) => i.created_by),
            ...data.map((i) => i.assignee_id),
            ...data.map((i) => i.accepted_by),
          ].filter(Boolean),
        ),
      ]

      // FK-ovi pokazuju na auth.users, ne na profiles — spajanje ide ručno
      // (invarijanta 1).
      const [{ data: profiles }, { data: counts }, { data: states }] = await Promise.all([
        userIds.length
          ? supabase.from('profiles').select('id, full_name, avatar_url').in('id', userIds)
          : Promise.resolve({ data: [] }),
        supabase.from('item_message_counts').select('item_id, message_count').in('item_id', ids),
        supabase
          .from('item_user_state')
          .select('item_id, read_at, watching_at')
          .eq('user_id', auth.user.id)
          .in('item_id', ids),
      ])

      const profileById = new Map((profiles ?? []).map((p) => [p.id, p]))
      const countById = new Map((counts ?? []).map((c) => [c.item_id, Number(c.message_count)]))
      const stateById = new Map((states ?? []).map((s) => [s.item_id, s]))

      const mapped = data.map((i) => {
        const st = stateById.get(i.id)
        return {
          ...i,
          profiles: profileById.get(i.created_by) ?? null,
          assignee: profileById.get(i.assignee_id) ?? null,
          accepted_profile: profileById.get(i.accepted_by) ?? null,
          message_count: countById.get(i.id) ?? 0,
          watching: !!st?.watching_at,
          is_new:
            !st?.read_at && i.created_by !== auth.user.id && !TERMINAL_STAGES.includes(i.stage),
        }
      })

      this.items = [...this.items.filter((i) => i.project_id !== projectId), ...mapped]
    },

    async createItem({
      projectId,
      kind,
      title,
      description = null,
      priority = 'med',
      // Zadatak se rađa već prihvaćen — nitko ga ne predlaže, unesen je kao posao.
      stage = kind === 'task' ? 'accepted' : 'new',
      screenshotUrl = null,
      screenshotType = null,
      screenshotName = null,
    }) {
      const auth = useAuthStore()
      const now = new Date().toISOString()

      const { error } = await supabase.from('items').insert({
        project_id: projectId,
        kind,
        stage,
        title,
        description,
        priority,
        created_by: auth.user.id,
        accepted_by: stage === 'accepted' ? auth.user.id : null,
        accepted_at: stage === 'accepted' ? now : null,
        screenshot_url: screenshotUrl,
        screenshot_type: screenshotType,
        screenshot_name: screenshotName,
      })
      if (error) throw error
      await this.fetchItems(projectId)
    },

    async updateItem(id, updates) {
      // Optimistično: promjena faze ili prioriteta mora izgledati trenutna,
      // realtime UPDATE stigne kasnije i samo potvrdi isto stanje.
      const idx = this.items.findIndex((i) => i.id === id)
      const previous = idx !== -1 ? { ...this.items[idx] } : null
      if (idx !== -1) this.items[idx] = { ...this.items[idx], ...updates }

      const { error } = await supabase.from('items').update(updates).eq('id', id)
      if (error) {
        if (previous) this.items[idx] = previous
        throw error
      }

      await discardReplacedScreenshot(previous?.screenshot_url, updates.screenshot_url)
    },

    async deleteItem(id) {
      const item = this.items.find((i) => i.id === id)
      const projectId = item?.project_id
      if (item?.screenshot_url) {
        await supabase.storage.from('chat-attachments').remove([item.screenshot_url])
        await removeCachedImage(item.screenshot_url)
      }
      const { error } = await supabase.from('items').delete().eq('id', id)
      if (error) throw error
      if (projectId) await this.fetchItems(projectId)
    },

    // --- Prijelazi faze -----------------------------------------------------
    // Zamjenjuju promoteToTbi / promoteToBug / demoteFromTbi. Ništa se ne kopira
    // ni ne briše — mijenja se jedno polje, pa thread i povijest ostaju netaknuti.

    async accept(id) {
      const auth = useAuthStore()
      await this.updateItem(id, {
        stage: 'accepted',
        accepted_by: auth.user.id,
        accepted_at: new Date().toISOString(),
      })
    },

    async reject(id) {
      const auth = useAuthStore()
      await this.updateItem(id, {
        stage: 'rejected',
        rejected_by: auth.user.id,
        rejected_at: new Date().toISOString(),
      })
    },

    // Vraćanje u razmatranje — nasljednik demotea, ali bez gubitka poruka.
    async reopen(id) {
      await this.updateItem(id, {
        stage: 'new',
        accepted_by: null,
        accepted_at: null,
        rejected_by: null,
        rejected_at: null,
        completed_by: null,
        completed_at: null,
      })
    },

    async markDone(id) {
      const auth = useAuthStore()
      await this.updateItem(id, {
        stage: 'done',
        completed_by: auth.user.id,
        completed_at: new Date().toISOString(),
      })
    },

    async markUndone(id) {
      const item = this.items.find((i) => i.id === id)
      await this.updateItem(id, {
        // Bug koji nikad nije bio prihvaćen vraća se u registar, ne na ploču.
        stage: item?.accepted_at ? 'accepted' : 'new',
        completed_by: null,
        completed_at: null,
      })
    },

    async assign(id, userId) {
      await this.updateItem(id, { assignee_id: userId })
    },

    // --- Stanje po korisniku ------------------------------------------------

    async markRead(id) {
      const auth = useAuthStore()
      const idx = this.items.findIndex((i) => i.id === id)
      if (idx !== -1) this.items[idx] = { ...this.items[idx], is_new: false }

      const { error } = await supabase.from('item_user_state').upsert(
        {
          user_id: auth.user.id,
          item_id: id,
          read_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,item_id' },
      )
      if (error) throw error

      const { useNotificationsStore } = await import('./notifications')
      await useNotificationsStore().fetchUnread()
    },

    // "Pratim" — osobna oznaka, vidi je samo vlasnik. Zasad čisto vizualna:
    // ističe stavku i omogućuje filtar, ne dira obavijesti.
    async toggleWatch(id) {
      const auth = useAuthStore()
      const idx = this.items.findIndex((i) => i.id === id)
      if (idx === -1) return

      const next = this.items[idx].watching ? null : new Date().toISOString()
      const previous = { ...this.items[idx] }
      this.items[idx] = { ...this.items[idx], watching: !!next }

      const { error } = await supabase.from('item_user_state').upsert(
        {
          user_id: auth.user.id,
          item_id: id,
          watching_at: next,
        },
        { onConflict: 'user_id,item_id' },
      )
      if (error) {
        this.items[idx] = previous
        throw error
      }
    },

    handleIncoming({ event, payload }) {
      // Realtime payload nema klijentski spojena polja (profiles, message_count,
      // is_new, watching) — spaja se sirovi red preko postojećeg.
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

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useItemsStore, import.meta.hot))
}
