<template>
  <q-page class="column no-wrap" style="height: 0">
    <!-- Ikona ide U red sa sadržajem, ne kroz `icon` prop: taj je slaže IZNAD
         sadržaja pa je tab dvostruko viši nego što ovdje treba biti. -->
    <q-tabs
      v-model="channel"
      dense
      align="left"
      class="q-px-md col-auto channel-tabs"
      indicator-color="primary"
      @update:model-value="switchChannel"
    >
      <q-tab name="main">
        <div class="row items-center q-gutter-xs no-wrap">
          <q-icon name="forum" size="16px" />
          <span>{{ $t('chat.channels.main') }}</span>
          <q-badge
            v-if="notifStore.threadUnread({ projectId, channel: 'main' }) > 0"
            color="negative"
            rounded
          >
            {{ notifStore.threadUnread({ projectId, channel: 'main' }) }}
          </q-badge>
        </div>
      </q-tab>

      <q-tab name="offtopic">
        <div class="row items-center q-gutter-xs no-wrap">
          <q-icon name="coffee" size="16px" />
          <span>{{ $t('chat.channels.offtopic') }}</span>
          <q-badge
            v-if="notifStore.threadUnread({ projectId, channel: 'offtopic' }) > 0"
            color="negative"
            rounded
          >
            {{ notifStore.threadUnread({ projectId, channel: 'offtopic' }) }}
          </q-badge>
        </div>
      </q-tab>
    </q-tabs>

    <q-separator />

    <ChatPanel
      ref="chatPanelRef"
      class="col"
      :project-id="projectId"
      :channel="channel"
      @scrolled-to-bottom="onMessagesRead"
    />
  </q-page>
</template>

<script setup>
import { ref, onMounted, onActivated, watch, nextTick } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useChatStore } from 'src/stores/chat'
import { useNotificationsStore } from 'src/stores/notifications'
import ChatPanel from 'src/components/chat/ChatPanel.vue'

const props = defineProps({ projectId: String })

const router = useRouter()
const route = useRoute()
const chatStore = useChatStore()
const notifStore = useNotificationsStore()
// I1/I2: ?channel=... u adresi (npr. iz push notifikacije) bira početni
// kanal umjesto uvijek 'main'; query se odmah čisti da se refresh/dijeljeni
// link ne otvara stalno na istom mjestu.
const channel = ref(route.query.channel === 'offtopic' ? 'offtopic' : 'main')
if (route.query.channel) router.replace({ query: {} })

const chatPanelRef = ref(null)

async function loadChannel(ch) {
  await chatStore.fetchMessages({ projectId: props.projectId, channel: ch })
  await notifStore.markRead({ projectId: props.projectId, channel: ch })
  await notifStore.fetchUnread()
  // Scroll nakon što su poruke učitane
  await nextTick()
  chatPanelRef.value?.scrollToBottom()
}

async function onMessagesRead() {
  await notifStore.markRead({ projectId: props.projectId, channel: channel.value })
  await notifStore.fetchUnread()
}

async function switchChannel(ch) {
  channel.value = ch
  await loadChannel(ch)
}

onMounted(async () => {
  await loadChannel(channel.value)
})

// keep-alive: ako je ChatPage već bila posjećena (mount se ne ponavlja),
// ?channel= iz nove navigacije (npr. rezultat pretrage) mora se pokupiti
// ovdje — jednokratno čitanje pri postavljanju komponente to ne bi vidjelo.
onActivated(async () => {
  const target = route.query.channel
  if (target && target !== channel.value) {
    channel.value = target === 'offtopic' ? 'offtopic' : 'main'
    router.replace({ query: {} })
  }
  await loadChannel(channel.value)
})

// Push notifikacija dok je app u pozadini (ne ugašen): ChatPage ostaje
// aktivna kartica cijelo vrijeme, pa se onActivated nikad ne okine —
// router.push samo promijeni query dok je komponenta već na ekranu. Bez
// ovog watchera se ništa ne bi dogodilo (isti simptom kao prije K3 fixa,
// samo za slučaj "app već otvorena na chatu" umjesto promjene taba).
watch(
  () => route.query.channel,
  async (target) => {
    if (!target) return
    channel.value = target === 'offtopic' ? 'offtopic' : 'main'
    router.replace({ query: {} })
    await loadChannel(channel.value)
  },
)
</script>

<style scoped>
/* Quasarova zadana visina taba (48px) je za tab-bar s ikonom iznad teksta —
   ovdje je sve u jednom redu, pa toliko visine samo jede prostor chatu. */
.channel-tabs :deep(.q-tab) {
  min-height: 36px;
}
</style>
