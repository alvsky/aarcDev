import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { cleanupOrg, createTestUser } from './helpers.js'

// B17: najvredniji test u projektu — korisnik A ne smije vidjeti NIŠTA iz
// organizacije korisnika B (ni čitanjem, ni pisanjem preko RLS-a mimo RPC-a).
// Dva potpuno odvojena korisnika/organizacije/projekta, pa iz kuta B-a
// provjeravamo baš svaku tablicu koju je B12/B9 zatvorio.
describe('RLS izolacija između organizacija', () => {
  let a // { client, userId, ... } — vlasnik org A, projekta i sadržaja
  let b // vlasnik posve odvojene org B
  let orgAId
  let orgBId
  let projectId
  let itemId
  let messageId

  beforeAll(async () => {
    a = await createTestUser('a')
    b = await createTestUser('b')

    const { data: orgA, error: orgAErr } = await a.client.rpc('create_organization', {
      p_name: `RLS Test Org A ${Date.now()}`,
    })
    if (orgAErr) throw orgAErr
    orgAId = orgA

    const { data: orgB, error: orgBErr } = await b.client.rpc('create_organization', {
      p_name: `RLS Test Org B ${Date.now()}`,
    })
    if (orgBErr) throw orgBErr
    orgBId = orgB

    const { data: newProjectId, error: projErr } = await a.client.rpc('create_project', {
      p_org: orgAId,
      p_name: 'RLS Test Project',
    })
    if (projErr) throw projErr
    projectId = newProjectId

    const { data: item, error: itemErr } = await a.client
      .from('items')
      .insert({
        project_id: projectId,
        kind: 'idea',
        stage: 'new',
        title: 'Tajna ideja organizacije A',
        created_by: a.userId,
      })
      .select()
      .single()
    if (itemErr) throw itemErr
    itemId = item.id

    const { data: message, error: msgErr } = await a.client
      .from('messages')
      .insert({
        project_id: projectId,
        author_id: a.userId,
        body: 'Tajna poruka organizacije A',
        channel: 'main',
      })
      .select()
      .single()
    if (msgErr) throw msgErr
    messageId = message.id
  })

  afterAll(async () => {
    await cleanupOrg(a?.client, orgAId)
    await cleanupOrg(b?.client, orgBId)
  })

  it('B ne vidi projekt A-a na listi', async () => {
    const { data, error } = await b.client.from('projects').select('id')
    expect(error).toBeNull()
    expect(data.map((p) => p.id)).not.toContain(projectId)
  })

  it('B ne može dohvatiti projekt A-a po id-u', async () => {
    const { data, error } = await b.client
      .from('projects')
      .select('*')
      .eq('id', projectId)
      .maybeSingle()
    expect(error).toBeNull()
    expect(data).toBeNull()
  })

  it('B ne vidi stavke (items) iz projekta A-a', async () => {
    const { data, error } = await b.client.from('items').select('id').eq('project_id', projectId)
    expect(error).toBeNull()
    expect(data).toEqual([])
  })

  it('B ne vidi poruke iz projekta A-a', async () => {
    const { data, error } = await b.client
      .from('messages')
      .select('id')
      .eq('project_id', projectId)
    expect(error).toBeNull()
    expect(data).toEqual([])
  })

  it('B ne može preimenovati projekt A-a (tiho odbijeno, 0 redaka)', async () => {
    const { data, error } = await b.client
      .from('projects')
      .update({ name: 'preoteto' })
      .eq('id', projectId)
      .select()
    expect(error).toBeNull()
    expect(data).toEqual([])
  })

  it('B ne može izbrisati stavku A-a', async () => {
    const { data, error } = await b.client.from('items').delete().eq('id', itemId).select()
    expect(error).toBeNull()
    expect(data).toEqual([])
  })

  it('B ne može ubaciti poruku u projekt A-a', async () => {
    const { error } = await b.client.from('messages').insert({
      project_id: projectId,
      author_id: b.userId,
      body: 'upad',
      channel: 'main',
    })
    expect(error).not.toBeNull()
  })

  it('B ne vidi profil korisnika A (nisu u istoj organizaciji)', async () => {
    const { data, error } = await b.client
      .from('profiles')
      .select('id')
      .eq('id', a.userId)
      .maybeSingle()
    expect(error).toBeNull()
    expect(data).toBeNull()
  })

  it('B ne vidi članstvo organizacije A', async () => {
    const { data, error } = await b.client.from('org_members').select('user_id').eq('org_id', orgAId)
    expect(error).toBeNull()
    expect(data).toEqual([])
  })

  it('B ne vidi pozivnice organizacije A', async () => {
    const { data, error } = await b.client
      .from('invitations')
      .select('id')
      .eq('org_id', orgAId)
    expect(error).toBeNull()
    expect(data).toEqual([])
  })

  it('B se ne može sam postaviti za člana organizacije A', async () => {
    const { data, error } = await b.client
      .from('org_members')
      .insert({ org_id: orgAId, user_id: b.userId, role: 'owner' })
      .select()
    expect(data === null || data.length === 0 || error !== null).toBe(true)
  })

  it('B ne može upravljati ulogama u projektu A-a preko RPC-a', async () => {
    const { error } = await b.client.rpc('set_project_member_role', {
      p_project: projectId,
      p_user: b.userId,
      p_role: 'owner',
    })
    expect(error).not.toBeNull()
  })

  it('B ne može ukloniti člana organizacije A preko RPC-a', async () => {
    const { error } = await b.client.rpc('remove_org_member', {
      p_org: orgAId,
      p_user: a.userId,
    })
    expect(error).not.toBeNull()
  })

  it('kontrola: A i dalje vidi vlastiti projekt/stavku/poruku', async () => {
    const [proj, item, msg] = await Promise.all([
      a.client.from('projects').select('id').eq('id', projectId).maybeSingle(),
      a.client.from('items').select('id').eq('id', itemId).maybeSingle(),
      a.client.from('messages').select('id').eq('id', messageId).maybeSingle(),
    ])
    expect(proj.data?.id).toBe(projectId)
    expect(item.data?.id).toBe(itemId)
    expect(msg.data?.id).toBe(messageId)
  })
})
