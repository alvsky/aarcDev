import localforage from 'localforage'

// Sloj perzistencije za offline-first (docs/offline-first.md).
// Sav keš je po korisniku (ključ sadrži userId) i briše se pri odjavi.

export const SCHEMA_VERSION = 1

const storage = localforage.createInstance({
  name: 'aarc',
  storeName: 'state',
})

const DEBOUNCE_MS = 500
const timers = {}

function persistKey(userId, slice) {
  return `aarc:${userId}:${slice}`
}

export function saveState(userId, slice, data) {
  const key = persistKey(userId, slice)
  if (timers[key]) clearTimeout(timers[key])
  timers[key] = setTimeout(async () => {
    delete timers[key]
    try {
      // JSON round-trip: skida Vue reactive proxije i sve što nije serijalizabilno
      const plain = JSON.parse(JSON.stringify(data))
      await storage.setItem(key, { v: SCHEMA_VERSION, data: plain })
    } catch (e) {
      console.warn('persistence save error:', slice, e)
    }
  }, DEBOUNCE_MS)
}

export async function loadState(userId, slice) {
  try {
    const rec = await storage.getItem(persistKey(userId, slice))
    if (!rec || rec.v !== SCHEMA_VERSION) return null
    return rec.data
  } catch (e) {
    console.warn('persistence load error:', slice, e)
    return null
  }
}

export async function clearAll(userId) {
  try {
    const prefix = `aarc:${userId}:`
    const keys = await storage.keys()
    await Promise.all(keys.filter((k) => k.startsWith(prefix)).map((k) => storage.removeItem(k)))
  } catch (e) {
    console.warn('persistence clear error:', e)
  }
}
