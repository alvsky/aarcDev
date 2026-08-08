<template>
  <q-page padding>
    <div class="row items-center q-mb-md">
      <div class="text-h6">{{ $t('bugs.title') }}</div>
      <q-space />
      <q-btn color="negative" icon="add" :label="$t('bugs.new')" @click="openDialog()" />
    </div>

    <!-- Filter po statusu -->
    <q-select
      v-model="filter"
      :options="filterOptions"
      :label="$t('common.status')"
      outlined
      dense
      emit-value
      map-options
      class="q-mb-md"
      style="min-width: 160px"
    />
    <div v-if="!filtered.length" class="text-center text-grey-5 q-mt-xl">
      {{ $t('bugs.noBugs') }}
    </div>

    <q-list>
      <BugCard
        v-for="bug in filtered"
        :key="bug.id"
        :bug="bug"
        :project-id="projectId"
        @edit="openDialog(bug)"
        @delete="confirmDelete(bug)"
        @open-thread="openThread(bug)"
        @status-change="(status) => changeField(bug.id, { status })"
        @priority-change="(priority) => changeField(bug.id, { priority })"
      />
    </q-list>

    <ItemDialog v-model="dialog" type="bug" :item="activeBug" :project-id="projectId" />

    <!-- Thread chat -->
    <ThreadDialog
      v-model="threadOpen"
      :title="threadBug?.title"
      :project-id="projectId"
      :bug-id="threadBug?.id"
      @close="onThreadClosed"
    />
  </q-page>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useBugsStore } from 'src/stores/bugs'
import { useChatStore } from 'src/stores/chat'
import { useNotificationsStore } from 'src/stores/notifications'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import BugCard from 'src/components/bugs/BugCard.vue'
import ThreadDialog from 'src/components/chat/ThreadDialog.vue'
import ItemDialog from 'src/components/shared/ItemDialog.vue'

const props = defineProps({ projectId: String })

const $q = useQuasar()
const { t } = useI18n()
const bugsStore = useBugsStore()
const chatStore = useChatStore()
const notifStore = useNotificationsStore()
const { blockedOffline } = useOfflineGuard()

const dialog = ref(false)
const activeBug = ref(null)
const threadOpen = ref(false)
const threadBug = ref(null)
const filter = ref('all')

const filterOptions = computed(() => [
  { label: t('common.all'), value: 'all' },
  { label: t('bugs.status.open'), value: 'open' },
  { label: t('bugs.status.in_progress'), value: 'in_progress' },
  { label: t('bugs.status.testing'), value: 'testing' },
  { label: t('bugs.status.closed'), value: 'closed' },
])

const filtered = computed(() => {
  let items = bugsStore.bugs.filter((b) => b.project_id === props.projectId)
  if (filter.value !== 'all') {
    items = items.filter((b) => b.status === filter.value)
  }
  // Zatvoreni na kraj
  return [
    ...items.filter((b) => b.status !== 'closed'),
    ...items.filter((b) => b.status === 'closed'),
  ]
})

function openDialog(bug = null) {
  activeBug.value = bug ? { ...bug } : null
  dialog.value = true
}

async function openThread(bug) {
  threadBug.value = bug
  threadOpen.value = true
  await chatStore.fetchMessages({
    projectId: props.projectId,
    bugId: bug.id,
  })
  await notifStore.markRead({
    projectId: props.projectId,
    bugId: bug.id,
  })
}

// Poruke mijenjaju broj nepročitanih i zadnju aktivnost, pa se lista osvježi
// tek kad se thread zatvori.
async function onThreadClosed() {
  threadBug.value = null
  await bugsStore.fetchBugs(props.projectId)
}
async function changeField(bugId, updates) {
  if (blockedOffline('common.offlineNoAction')) return
  try {
    await bugsStore.updateBug(bugId, updates)
  } catch (e) {
    $q.notify({ type: 'negative', message: e.message })
  }
}

function confirmDelete(bug) {
  if (blockedOffline()) return
  $q.dialog({
    title: t('common.delete'),
    message: bug.title,
    ok: { label: t('common.delete'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    try {
      await bugsStore.deleteBug(bug.id)
    } catch (e) {
      console.error('Delete bug error:', e)
      $q.notify({ type: 'negative', message: e.message })
    }
  })
}
// function confirmPromote(bug) {
//   $q.dialog({
//     title: t('bugs.promote'),
//     message: t('bugs.confirmPromote'),
//     ok: { label: t('common.confirm'), color: 'negative' },
//     cancel: t('common.cancel'),
//   }).onOk(async () => {
//     await bugsStore.promoteToBug(bug)
//     $q.notify({ type: 'positive', message: t('bugs.promote') })
//   })
// }

onMounted(async () => {
  await bugsStore.fetchBugs(props.projectId)
})
</script>
