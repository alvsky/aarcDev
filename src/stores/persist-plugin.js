import { loadState, saveState } from 'src/utils/persistence'

// Pinia plugin: storovi s `persist: ['polje', ...]` opcijom se nakon prijave pune
// spremljenim podacima iz IndexedDB-a i debounced-spremaju na svaku promjenu.
// Punjenje ide SAMO u prazna polja — svježi fetch koji je već stigao nikad se ne
// pregazi starim podacima s diska.

const registered = []
let currentUserId = null

async function hydrateStore(store, fields, userId) {
  const data = await loadState(userId, store.$id)
  // Ako se korisnik u međuvremenu promijenio, odbaci
  if (!data || currentUserId !== userId) return
  for (const field of fields) {
    const cur = store[field]
    const isEmpty = Array.isArray(cur)
      ? cur.length === 0
      : cur && typeof cur === 'object'
        ? Object.keys(cur).length === 0
        : !cur
    if (isEmpty && data[field] !== undefined) {
      store[field] = data[field]
    }
  }
}

export function piniaPersistPlugin({ store, options }) {
  // Auth store je izvor userId-a: na prijavu napuni sve storove iz pohrane, na odjavu prestani spremati
  if (store.$id === 'auth') {
    store.$subscribe(() => {
      const uid = store.user?.id ?? null
      if (uid && uid !== currentUserId) {
        currentUserId = uid
        for (const r of registered) hydrateStore(r.store, r.fields, uid)
      } else if (!uid) {
        currentUserId = null
      }
    })
    return
  }

  const fields = options.persist
  if (!fields?.length) return

  registered.push({ store, fields })
  if (currentUserId) hydrateStore(store, fields, currentUserId)

  store.$subscribe(() => {
    if (!currentUserId) return
    const data = {}
    for (const field of fields) data[field] = store[field]
    saveState(currentUserId, store.$id, data)
  })
}
