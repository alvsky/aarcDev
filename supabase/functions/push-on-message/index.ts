import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Dohvati Firebase access token kroz Service Account
async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)

  function base64url(data: ArrayBuffer | string): string {
    let str = ''
    if (typeof data === 'string') {
      str = btoa(data)
    } else {
      str = btoa(String.fromCharCode(...new Uint8Array(data)))
    }
    return str.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
  }

  const headerObj  = { alg: 'RS256', typ: 'JWT' }
  const payloadObj = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }

  const header  = base64url(JSON.stringify(headerObj))
  const payload = base64url(JSON.stringify(payloadObj))
  const signingInput = `${header}.${payload}`

  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(signingInput)
  )

  const jwt = `${signingInput}.${base64url(signature)}`

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion:  jwt,
    }),
  })

  const tokenData = await tokenResponse.json()
  console.log('Token response:', JSON.stringify(tokenData))

  if (!tokenData.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(tokenData)}`)
  }

  return tokenData.access_token
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '')
  const binary = atob(base64)
  const buffer = new ArrayBuffer(binary.length)
  const view = new Uint8Array(buffer)
  for (let i = 0; i < binary.length; i++) {
    view[i] = binary.charCodeAt(i)
  }
  return buffer
}

// Zajednička logika slanja pusha svim članovima projekta (osim autora), poštujući
// badge_enabled + per-kategorija notif_* postavku. Koristi se za poruke, ideje, bugove i TBI.
async function sendPushToMembers(
  supabase: any,
  fcmProjectId: string,
  accessToken: string,
  {
    projectId,
    excludeUserId,
    notifField,
    title,
    body,
    data,
  }: {
    projectId: string
    excludeUserId: string
    notifField: 'notif_messages' | 'notif_ideas' | 'notif_bugs' | 'notif_tbi'
    title: string
    body: string
    data: Record<string, string>
  }
) {
  const { data: members } = await supabase
    .from('project_members')
    .select('user_id')
    .eq('project_id', projectId)
    .neq('user_id', excludeUserId)
    .eq('badge_enabled', true)
    .eq(notifField, true)

  console.log('Members found:', members?.length)
  if (!members?.length) return

  const userIds = members.map((m: any) => m.user_id)
  const { data: tokens } = await supabase
    .from('push_tokens')
    .select('user_id, token, platform')
    .in('user_id', userIds)

  console.log('Tokens found:', tokens?.length)
  if (!tokens?.length) return

  // Stvarni unread broj po primatelju (za APNs badge) — jedan RPC po korisniku
  const badgeCounts = new Map<string, number>()
  await Promise.all(
    userIds.map(async (uid: string) => {
      const { data: total, error } = await supabase.rpc('get_unread_total', { p_user_id: uid })
      if (error) {
        console.error('get_unread_total error for', uid, error)
        badgeCounts.set(uid, 1) // fallback: barem signaliziraj da nešto postoji
      } else {
        badgeCounts.set(uid, Number(total ?? 0))
      }
    })
  )

  for (const { user_id, token, platform } of tokens) {
    console.log('Sending to platform:', platform)

    const message: any = {
      token,
      notification: { title, body },
      data,
    }

    // iOS specifično — badge = stvarni unread broj tog korisnika
    if (platform === 'ios') {
      message.apns = {
        payload: {
          aps: {
            alert: { title, body },
            sound: 'default',
            badge: badgeCounts.get(user_id) ?? 1,
          },
        },
      }
    }

    // Android specifično
    if (platform === 'android') {
      message.android = {
        notification: { sound: 'default' },
      }
    }

    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${fcmProjectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message }),
      }
    )

    const fcmResult = await fcmResponse.json()
    console.log('FCM v1 result:', JSON.stringify(fcmResult))
  }
}

serve(async (req) => {
  try {
    const payload = await req.json()
    console.log('Webhook payload received, table:', payload.table)

    const record = payload.record
    if (!record) return new Response('no record', { status: 200 })

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: project } = await supabase
      .from('projects')
      .select('name')
      .eq('id', record.project_id)
      .single()
    const title = project?.name ?? 'aarcDev'

    // Dohvati Firebase Service Account
    const serviceAccountStr = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!
    const serviceAccount = JSON.parse(serviceAccountStr)
    const fcmProjectId = serviceAccount.project_id
    const accessToken = await getFirebaseAccessToken(serviceAccount)

    if (payload.table === 'messages') {
      const { data: author } = await supabase
        .from('profiles')
        .select('full_name')
        .eq('id', record.author_id)
        .single()

      await sendPushToMembers(supabase, fcmProjectId, accessToken, {
        projectId: record.project_id,
        excludeUserId: record.author_id,
        notifField: 'notif_messages',
        title,
        body: `${author?.full_name}: ${record.body?.slice(0, 80) || '📎 Screenshot'}`,
        data: { projectId: record.project_id, channel: record.channel ?? 'main' },
      })
    } else if (payload.table === 'items') {
      const { data: author } = await supabase
        .from('profiles')
        .select('full_name')
        .eq('id', record.created_by)
        .single()

      // Ista pravila kao tabForNewItem u src/stores/notifications.js: kartica se
      // bira po fazi, pa tek onda po vrsti. Zadatak se rađa prihvaćen, pa ide na
      // TBI ploču a ne u lijevak ideja.
      const ACTIVE_STAGES = ['accepted', 'in_progress', 'testing']
      let notifField: 'notif_ideas' | 'notif_bugs' | 'notif_tbi'
      let prefix: string

      if (ACTIVE_STAGES.includes(record.stage)) {
        notifField = 'notif_tbi'
        prefix = 'Nova TODO stavka'
      } else if (record.kind === 'bug') {
        notifField = 'notif_bugs'
        prefix = 'Novi bug'
      } else {
        notifField = 'notif_ideas'
        prefix = 'Nova ideja'
      }

      await sendPushToMembers(supabase, fcmProjectId, accessToken, {
        projectId: record.project_id,
        excludeUserId: record.created_by,
        notifField,
        title,
        body: `${author?.full_name}: ${prefix} — ${record.title}`,
        data: { projectId: record.project_id, itemId: record.id, kind: record.kind },
      })
    } else {
      return new Response('unhandled table', { status: 200 })
    }

    return new Response('ok', { status: 200 })

  } catch (err) {
    console.error('Error:', err)
    return new Response('error', { status: 500 })
  }
})
