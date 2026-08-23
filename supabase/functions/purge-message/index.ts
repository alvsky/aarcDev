// Briše poruku koja nestaje nakon čitanja — redak u messages i prilog u
// Storageu — kad su je pročitali svi članovi projekta u kojem je objavljena.
//
// Zašto edge funkcija, a ne obično brisanje iz klijenta: politika
// chat_attachments_delete dopušta brisanje samo iz vlastite mape
// (${projectId}/${userId}/...), pa primatelj ne može maknuti autorov
// screenshot — pokušaj tiho ne uspije i objekt ostane siroče.
//
// Poziva je klijent kad mu mark_message_read vrati fully_read: true. Uvjet se
// ovdje ponovno provjerava kroz is_message_fully_read, pa poziv s tuđim ili
// izmišljenim id-em ne može obrisati ništa što ionako nije spremno za brisanje.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { messageId } = await req.json()
    if (!messageId) return json({ purged: false, reason: 'no messageId' }, 400)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: fullyRead, error: checkError } = await supabase.rpc('is_message_fully_read', {
      p_message_id: messageId,
    })
    if (checkError) return json({ purged: false, reason: checkError.message }, 500)
    if (!fullyRead) return json({ purged: false, reason: 'not fully read' })

    const { data: message } = await supabase
      .from('messages')
      .select('attachment_url')
      .eq('id', messageId)
      .maybeSingle()

    // Prilog prvi: ako brisanje objekta padne, redak ostaje i pokušat ćemo
    // opet na sljedeće čitanje. Obrnutim redoslijedom bismo izgubili putanju.
    if (message?.attachment_url) {
      const { error: storageError } = await supabase.storage
        .from('chat-attachments')
        .remove([message.attachment_url])
      if (storageError) return json({ purged: false, reason: storageError.message }, 500)
    }

    // Redak namjerno preživi kao prazan nadgrobni zapis — bez njega nema na
    // čemu prikazati "Otvoreno" u chatu (WhatsApp-style trag). Sadržaj se
    // briše, ostaju samo autor, vrijeme i mjesto u threadu.
    const { error: wipeError } = await supabase
      .from('messages')
      .update({
        body: '',
        attachment_url: null,
        attachment_name: null,
        attachment_type: null,
        deleted_at: new Date().toISOString(),
      })
      .eq('id', messageId)
    if (wipeError) return json({ purged: false, reason: wipeError.message }, 500)

    return json({ purged: true })
  } catch (error) {
    return json({ purged: false, reason: String(error) }, 500)
  }
})
