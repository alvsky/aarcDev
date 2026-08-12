import { describe, expect, it } from 'vitest'
import { tabForItem } from 'src/utils/itemTabs.js'

describe('tabForItem', () => {
  it('task uvijek ide na tbi, bez obzira na fazu', () => {
    expect(tabForItem({ kind: 'task', stage: 'accepted' })).toBe('tbi')
    expect(tabForItem({ kind: 'task', stage: 'done' })).toBe('tbi')
  })

  it('aktivna faza (bilo koje vrste) ide na tbi', () => {
    for (const stage of ['accepted', 'in_progress', 'testing']) {
      expect(tabForItem({ kind: 'idea', stage })).toBe('tbi')
      expect(tabForItem({ kind: 'bug', stage })).toBe('tbi')
    }
  })

  it('bug u ne-aktivnoj fazi ide u registar bugova, uključujući gotove/odbijene', () => {
    for (const stage of ['new', 'confirmed', 'done', 'rejected']) {
      expect(tabForItem({ kind: 'bug', stage })).toBe('bugs')
    }
  })

  it('ideja u ne-aktivnoj fazi ide u Ideje, uključujući gotove/odbijene', () => {
    for (const stage of ['new', 'confirmed', 'done', 'rejected']) {
      expect(tabForItem({ kind: 'idea', stage })).toBe('ideas')
    }
  })

  it('gotova ideja koja je nekad bila prihvaćena i dalje ide u Ideje, ne na tbi', () => {
    // Ovo je točno regresija koju je popravio K3 (2026-08-12) — ranija verzija
    // je gledala accepted_at umjesto stage, pa je znala odabrati tbi ovdje.
    expect(tabForItem({ kind: 'idea', stage: 'done', accepted_at: '2026-01-01' })).toBe('ideas')
  })
})
