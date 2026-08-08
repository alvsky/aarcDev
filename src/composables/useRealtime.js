import { supabase } from 'src/boot/supabase'

export function useRealtime(projectId, handlers = {}) {
  let channel = null

  function setup() {
    channel = supabase.channel(`project:${projectId}`)

    const tables = [
      { table: 'messages', handler: handlers.onMessage },
      { table: 'ideas', handler: handlers.onIdea },
      { table: 'bugs', handler: handlers.onBug },
      { table: 'tbi_items', handler: handlers.onTbi },
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
    channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        // console.log(`Realtime subscribed for project: ${projectId}`)
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
