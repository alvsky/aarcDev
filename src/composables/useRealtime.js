import { supabase } from 'src/boot/supabase'

export function useRealtime(projectId, handlers = {}) {
  let channel = null

  function setup() {
    channel = supabase.channel(`project:${projectId}`)

    const tables = [
      { table: 'messages', handler: handlers.onMessage },
      { table: 'items', handler: handlers.onItem },
    ]

    for (const { table, handler } of tables) {
      if (!handler) continue
      for (const event of ['INSERT', 'UPDATE', 'DELETE']) {
        channel.on(
          'postgres_changes',
          { event, schema: 'public', table, filter: `project_id=eq.${projectId}` },
          (payload) => handler({ event, payload }),
        )
      }
    }

    // subscribe() mora biti zadnji
    //
    // Greške se MORAJU vidjeti. Sve pretplate dijele jedan kanal, pa jedna
    // tablica koja nije u supabase_realtime publikaciji ruši i sve ostale —
    // aplikacija tada radi, samo tiho prestane primati poruke uživo. Točno to
    // se dogodilo kad je `items` dodan u pretplatu prije nego u publikaciju.
    channel.subscribe((status, err) => {
      if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
        console.error(
          `[realtime] pretplata za projekt ${projectId}: ${status}`,
          err ?? '(bez detalja — provjeri je li svaka tablica u supabase_realtime publikaciji)',
        )
      }
    })
  }

  function teardown() {
    if (channel) {
      supabase.removeChannel(channel)
      channel = null
    }
  }

  return { setup, teardown }
}
