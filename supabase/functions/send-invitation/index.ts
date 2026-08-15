import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const ROLE_LABEL: Record<string, string> = {
  admin: 'administrator',
  member: 'član',
  guest: 'gost',
}

serve(async (req) => {
  try {
    const payload = await req.json()
    const record = payload.record
    if (!record) return new Response('no record', { status: 200 })

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const [{ data: org }, { data: inviter }] = await Promise.all([
      supabase.from('organizations').select('name').eq('id', record.org_id).single(),
      supabase.from('profiles').select('full_name').eq('id', record.invited_by).single(),
    ])

    const inviteUrl = `https://vitkadesign.com/aarc-invite/${record.token}`
    const orgName = org?.name ?? 'aarc'
    const inviterName = inviter?.full_name ?? 'Netko'
    const roleLabel = ROLE_LABEL[record.role] ?? record.role

    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'aarc <aarc@vitkadesign.com>',
        to: [record.email],
        subject: `${inviterName} te pozvao/la u "${orgName}" na aarc`,
        html: `
          <div style="font-family: -apple-system, sans-serif; max-width: 480px; margin: 0 auto;">
            <h2 style="color: #1a1a1a;">Pozvan/a si u "${orgName}"</h2>
            <p style="color: #444; line-height: 1.5;">
              ${inviterName} te pozvao/la da se pridružiš organizaciji <strong>${orgName}</strong>
              na aarc-u, kao <strong>${roleLabel}</strong>.
            </p>
            <p style="margin: 24px 0;">
              <a href="${inviteUrl}"
                 style="background: #007bff; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; display: inline-block;">
                Prihvati pozivnicu
              </a>
            </p>
            <p style="color: #888; font-size: 13px; line-height: 1.5;">
              Ako gumb ne radi, otvori ovaj link: <br />
              <a href="${inviteUrl}" style="color: #007bff;">${inviteUrl}</a>
            </p>
            <p style="color: #aaa; font-size: 12px; margin-top: 24px;">
              Pozivnica vrijedi 14 dana. Ako je nisi tražio/la, slobodno ignoriraj ovaj mail.
            </p>
          </div>
        `,
      }),
    })

    const resendResult = await resendResponse.json()
    console.log('Resend result:', JSON.stringify(resendResult))

    if (!resendResponse.ok) {
      return new Response('resend error', { status: 500 })
    }

    return new Response('ok', { status: 200 })
  } catch (err) {
    console.error('Error:', err)
    return new Response('error', { status: 500 })
  }
})
