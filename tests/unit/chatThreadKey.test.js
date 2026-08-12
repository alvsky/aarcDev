import { describe, expect, it, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

// chat.js uvozi supabase klijent na vrhu datoteke (src/boot/supabase.js),
// koji pri stvaranju čita window.localStorage — u node test okruženju
// (bez DOM-a) window ne postoji. Ovaj test ne treba pravi klijent uopće
// (threadKey je čista funkcija), pa ga samo isprazni umjesto da uvodi jsdom
// samo zbog ovoga.
vi.mock('src/boot/supabase', () => ({ supabase: {} }))

const { useChatStore } = await import('src/stores/chat.js')

// threadKey je pravilo "jedna stavka — jedan thread" (docs/item-model.md) u
// kodu: item_id nadjačava channel (item ima svoj thread neovisno o tome iz
// koje je kartice otvoren), inače thread ide po (project, channel).
describe('chatStore.threadKey', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('stavka (itemId) uvijek daje isti ključ, bez obzira na kanal', () => {
    const chat = useChatStore()
    const withMain = chat.threadKey({ projectId: 'p1', itemId: 'i1', channel: 'main' })
    const withOfftopic = chat.threadKey({ projectId: 'p1', itemId: 'i1', channel: 'offtopic' })
    expect(withMain).toBe(withOfftopic)
    expect(withMain).toBe('p1:item:i1')
  })

  it('bez itemId ključ ide po (project, channel)', () => {
    const chat = useChatStore()
    expect(chat.threadKey({ projectId: 'p1', channel: 'main' })).toBe('p1:main')
    expect(chat.threadKey({ projectId: 'p1', channel: 'offtopic' })).toBe('p1:offtopic')
  })

  it('channel je zadano "main" kad nije naveden i nema itemId', () => {
    const chat = useChatStore()
    expect(chat.threadKey({ projectId: 'p1' })).toBe('p1:main')
  })

  it('različiti projekti nikad ne dijele ključ', () => {
    const chat = useChatStore()
    expect(chat.threadKey({ projectId: 'p1', channel: 'main' })).not.toBe(
      chat.threadKey({ projectId: 'p2', channel: 'main' }),
    )
  })
})
