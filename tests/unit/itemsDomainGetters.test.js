import { describe, expect, it, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

// items.js uvozi supabase klijent na vrhu datoteke, koji pri stvaranju čita
// window.localStorage — nema ga u node test okruženju. Ovi testovi gledaju
// samo čiste gettere (state.items.filter(...)), pa je klijent isprazniti
// jednostavnije nego uvoditi jsdom samo zbog ovoga.
vi.mock('src/boot/supabase', () => ({ supabase: {} }))

const { useItemsStore } = await import('src/stores/items.js')

// docs/item-model.md: kartice su POGLEDI nad jednoj tablici, ne odvojeni
// spremnici — ista stavka smije pripadati dvama pogledima istovremeno
// (npr. prihvaćen bug je i u Bugovima i na TBI-u). Ovi testovi provjeravaju
// baš tu domensku pripadnost (ideas/bugs/tbi getteri), ne prikaz/filtriranje
// u sučelju (to je zaseban sloj, vidi ItemListPanel).
function makeItem(overrides) {
  return { project_id: 'p1', kind: 'idea', stage: 'new', ...overrides }
}

describe('itemsStore domenski getteri (ideas/bugs/tbi)', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('ideja napušta Ideje čim postane aktivna (prihvaćena/u izradi/u testiranju)', () => {
    const store = useItemsStore()
    store.items = [
      makeItem({ id: '1', stage: 'new' }),
      makeItem({ id: '2', stage: 'confirmed' }),
      makeItem({ id: '3', stage: 'accepted' }),
      makeItem({ id: '4', stage: 'in_progress' }),
      makeItem({ id: '5', stage: 'testing' }),
    ]
    expect(store.ideas('p1').map((i) => i.id)).toEqual(['1', '2'])
  })

  it('gotova/odbijena ideja se vraća u Ideje (registar prijedloga, ne samo aktivnih)', () => {
    const store = useItemsStore()
    store.items = [
      makeItem({ id: '1', stage: 'done', accepted_at: '2026-01-01' }),
      makeItem({ id: '2', stage: 'rejected' }),
    ]
    expect(store.ideas('p1').map((i) => i.id)).toEqual(['1', '2'])
  })

  it('registar bugova prikazuje SVE faze, uključujući aktivne', () => {
    const store = useItemsStore()
    store.items = [
      makeItem({ id: '1', kind: 'bug', stage: 'new' }),
      makeItem({ id: '2', kind: 'bug', stage: 'accepted' }),
      makeItem({ id: '3', kind: 'bug', stage: 'done' }),
    ]
    expect(store.bugs('p1').map((i) => i.id)).toEqual(['1', '2', '3'])
  })

  it('TBI ploča: aktivna faza uvijek, terminalna faza samo ako je bila prihvaćena', () => {
    const store = useItemsStore()
    store.items = [
      makeItem({ id: 'active', kind: 'bug', stage: 'in_progress' }),
      makeItem({ id: 'done-accepted', kind: 'idea', stage: 'done', accepted_at: '2026-01-01' }),
      makeItem({ id: 'done-never-accepted', kind: 'idea', stage: 'done', accepted_at: null }),
      makeItem({ id: 'new', kind: 'bug', stage: 'new' }),
    ]
    expect(store.tbi('p1').map((i) => i.id).sort()).toEqual(['active', 'done-accepted'])
  })

  it('prihvaćen bug pripada i Bugovima i TBI-u istovremeno (isti redak, dva pogleda)', () => {
    const store = useItemsStore()
    store.items = [makeItem({ id: '1', kind: 'bug', stage: 'accepted' })]
    expect(store.bugs('p1').map((i) => i.id)).toEqual(['1'])
    expect(store.tbi('p1').map((i) => i.id)).toEqual(['1'])
  })

  it('domenski getteri ne miješaju projekte (invarijanta 6)', () => {
    const store = useItemsStore()
    store.items = [makeItem({ id: '1', project_id: 'p1' }), makeItem({ id: '2', project_id: 'p2' })]
    expect(store.ideas('p1').map((i) => i.id)).toEqual(['1'])
    expect(store.ideas('p2').map((i) => i.id)).toEqual(['2'])
  })
})
