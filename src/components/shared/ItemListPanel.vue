<template>
  <!-- Zajednički panel za sve tri kartice — Ideje, Bugovi i TBI razlikuju se samo
       ulaznim popisom i sitnim postavkama. Vidi docs/item-model.md. -->
  <q-page padding>
    <div class="row items-center q-mb-sm">
      <div class="text-h6">{{ title }}</div>
      <q-space />
      <q-btn color="primary" icon="add" :label="newLabel" @click="openDialog()" />
    </div>

    <div class="row items-center q-gutter-xs q-mb-md">
      <q-btn
        flat
        dense
        size="sm"
        :icon="onlyWatching ? 'visibility' : 'visibility_off'"
        :color="onlyWatching ? 'primary' : 'grey-6'"
        :label="$t('items.onlyWatching')"
        @click="onlyWatching = !onlyWatching"
      />
      <q-btn
        flat
        dense
        size="sm"
        icon="sort"
        color="grey-6"
        :label="sortBy === 'priority' ? $t('items.sortByPriority') : $t('items.sortByNewest')"
        @click="sortBy = sortBy === 'priority' ? 'newest' : 'priority'"
      />
      <q-btn
        flat
        dense
        size="sm"
        icon="inventory_2"
        :color="showClosed ? 'primary' : 'grey-6'"
        :label="$t('items.showClosed')"
        @click="showClosed = !showClosed"
      />
    </div>

    <div v-if="!visible.length" class="text-center text-grey-5 q-mt-xl">
      {{ emptyText }}
    </div>

    <q-list>
      <ItemCard
        v-for="item in visible"
        :key="item.id"
        :item="item"
        :project-id="projectId"
        :members="members"
        :show-kind="showKind"
        :group="group"
        @edit="openDialog(item)"
        @delete="confirmDelete(item)"
        @open-thread="openThread(item)"
      />
    </q-list>

    <ItemDialog v-model="dialog" :kind="kind" :item="activeItem" :project-id="projectId" />

    <ThreadDialog
      v-model="threadOpen"
      :title="threadItem?.title"
      :project-id="projectId"
      :item-id="threadItem?.id"
      @close="onThreadClosed"
    />
  </q-page>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useItemsStore } from 'src/stores/items'
import { useProjectsStore } from 'src/stores/projects'
import { useOrgsStore } from 'src/stores/orgs'
import { useChatStore } from 'src/stores/chat'
import { useNotificationsStore } from 'src/stores/notifications'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import ItemCard from './ItemCard.vue'
import ItemDialog from './ItemDialog.vue'
import ThreadDialog from 'src/components/chat/ThreadDialog.vue'

const props = defineProps({
  projectId: { type: String, required: true },
  items: { type: Array, default: () => [] },
  // Vrsta koja se stvara gumbom "novo" na ovoj kartici
  kind: { type: String, required: true },
  title: { type: String, default: '' },
  newLabel: { type: String, default: '' },
  emptyText: { type: String, default: '' },
  showKind: { type: Boolean, default: false },
  group: { type: String, default: 'items' },
})

const $q = useQuasar()
const { t } = useI18n()
const itemsStore = useItemsStore()
const projectsStore = useProjectsStore()
const orgsStore = useOrgsStore()
const chatStore = useChatStore()

const project = computed(() => projectsStore.getById(props.projectId))

// Kandidati za izvršitelja — TKO IMA PRISTUP, ne project_members (B25 ga je
// pretvorio u pretplatu; na projektu vidljivom organizaciji ondje bi ostao
// samo tvorac, a ostali s pristupom se ne bi mogli zadužiti). Gosti se
// isključuju: vidljivost 'org' im ionako ne daje pristup projektu.
//
// Na privatnom projektu je project_members i dalje pravi popis, jer ondje
// redak = dozvola (can_access_project to zahtijeva), ne samo pretplata.
const members = computed(() => {
  if (!project.value) return []
  if (project.value.visibility === 'org') {
    return orgsStore.members.filter((m) => m.role !== 'guest')
  }
  return project.value.project_members ?? []
})

watch(
  () => project.value?.org_id,
  (orgId) => {
    if (orgId && project.value?.visibility === 'org') orgsStore.fetchMembers(orgId)
  },
  { immediate: true },
)
const notifStore = useNotificationsStore()
const { blockedOffline } = useOfflineGuard()

const dialog = ref(false)
const activeItem = ref(null)
const threadOpen = ref(false)
const threadItem = ref(null)

const onlyWatching = ref(false)
const showClosed = ref(false)
const sortBy = ref('newest')

const PRIO_ORDER = { high: 0, med: 1, low: 2 }
const TERMINAL = ['done', 'rejected']

const visible = computed(() => {
  let list = props.items

  if (onlyWatching.value) list = list.filter((i) => i.watching)

  if (!showClosed.value) {
    // Zatvorene se skrivaju, ALI nikad one koje traže pažnju — inače bi nastao
    // badge koji se ne da otvoriti (uvjet iz notifications.js).
    list = list.filter(
      (i) =>
        !TERMINAL.includes(i.stage) ||
        i.watching ||
        notifStore.threadUnread({ projectId: props.projectId, itemId: i.id }) > 0,
    )
  }

  const sorted = [...list]
  if (sortBy.value === 'priority') {
    sorted.sort(
      (a, b) =>
        (PRIO_ORDER[a.priority] ?? 3) - (PRIO_ORDER[b.priority] ?? 3) ||
        new Date(b.created_at) - new Date(a.created_at),
    )
  } else {
    sorted.sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
  }
  return sorted
})

function openDialog(item = null) {
  activeItem.value = item ? { ...item } : null
  dialog.value = true
}

async function openThread(item) {
  threadItem.value = item
  threadOpen.value = true
  await chatStore.fetchMessages({ projectId: props.projectId, itemId: item.id })
  await notifStore.markRead({ projectId: props.projectId, itemId: item.id })
}

async function onThreadClosed() {
  threadItem.value = null
  await itemsStore.fetchItems(props.projectId)
}

function confirmDelete(item) {
  if (blockedOffline()) return
  $q.dialog({
    title: t('common.delete'),
    message: item.title,
    ok: { label: t('common.delete'), color: 'negative' },
    cancel: t('common.cancel'),
  }).onOk(async () => {
    await itemsStore.deleteItem(item.id)
  })
}
</script>
