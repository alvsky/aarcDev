<template>
  <!-- Zajednički panel za sve tri kartice — Ideje, Bugovi i TBI razlikuju se samo
       ulaznim popisom i sitnim postavkama. Vidi docs/item-model.md. -->
  <!-- Isti obrazac kao ChatPage: panel je flex stupac s vlastitim unutarnjim
       skrolom, pa alatna traka ostaje na mjestu dok se popis skrola. Sticky
       s top:0 ovdje ne bi radio jer stranica skrola u prozoru, a zaglavlje
       je fixed — traka bi završila iza njega. Naslov je maknut: kartica u
       zaglavlju već kaže gdje si (Bugovi/Ideje/TBI). -->
  <q-page class="column no-wrap" style="height: 0">
    <div class="col-auto q-px-md q-pt-md q-pb-sm">
      <div class="row items-center q-gutter-xs">
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
        <q-space />
        <q-btn dense color="primary" icon="add" :label="newLabel" @click="openDialog()" />
      </div>
    </div>

    <q-separator />

    <!-- Velik razmak na dnu namjerno: bez njega zadnja stavka završi tik uz
         rub, pa njezina razdjelna crta izgleda kao početak sljedeće i djeluje
         kao da popis ide dalje. -->
    <div class="col scroll q-px-md list-scroll">
      <!-- I4: skeleton dok se prvi put puni keš za ovaj projekt, ne na svaki refetch. -->
      <q-list v-if="itemsStore.isLoading(projectId) && !items.length">
        <q-item v-for="n in 3" :key="n">
          <q-item-section>
            <q-skeleton type="text" width="60%" />
            <q-skeleton type="text" width="35%" />
          </q-item-section>
        </q-item>
      </q-list>

      <div v-else-if="!visible.length" class="text-center text-grey-5 q-mt-xl">
        {{ emptyText }}
      </div>

      <q-list v-else>
        <ItemCard
          v-for="item in visible"
          :key="item.id"
          :item="item"
          :project-id="projectId"
          :members="members"
          :show-kind="showKind"
          :group="group"
          :expanded="item.id === highlightItemId"
          @edit="openDialog(item)"
          @delete="confirmDelete(item)"
          @open-thread="openThread(item)"
        />
      </q-list>
    </div>

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
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useItemsStore } from 'src/stores/items'
import { useProjectsStore } from 'src/stores/projects'
import { useOrgsStore } from 'src/stores/orgs'
import { useChatStore } from 'src/stores/chat'
import { useNotificationsStore } from 'src/stores/notifications'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import { useConfirmDialog } from 'src/composables/useConfirmDialog'
import ItemCard from './ItemCard.vue'
import ItemDialog from './ItemDialog.vue'
import ThreadDialog from 'src/components/chat/ThreadDialog.vue'

const props = defineProps({
  projectId: { type: String, required: true },
  items: { type: Array, default: () => [] },
  // Vrsta koja se stvara gumbom "novo" na ovoj kartici
  kind: { type: String, required: true },
  newLabel: { type: String, default: '' },
  emptyText: { type: String, default: '' },
  showKind: { type: Boolean, default: false },
  group: { type: String, default: 'items' },
})

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
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
const { confirmDestructive } = useConfirmDialog()

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

  if (onlyWatching.value) list = list.filter((i) => i.watching || i.id === highlightItemId.value)

  if (!showClosed.value) {
    // Zatvorene se skrivaju, ALI nikad one koje traže pažnju (uvjet iz
    // notifications.js) ili su upravo cilj deep-linka — inače bi rezultat
    // pretrage odveo na karticu i ostavio stavku nevidljivom.
    list = list.filter(
      (i) =>
        !TERMINAL.includes(i.stage) ||
        i.watching ||
        i.id === highlightItemId.value ||
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

// I1/I2/K3: deep-link na stavku (?item=<id> u adresi, npr. iz push
// notifikacije ili pretrage). Namjerno se ne provjerava kojoj kartici link
// cilja — dovoljno je da je stavka stvarno u OVOM (već po vrsti
// filtriranom) popisu; ostale kartice je jednostavno neće imati pa im
// watcher ništa neće napraviti.
//
// highlightItemId (ne izravno router.replace + otvaranje) da izbjegnemo
// utrku: querty se briše odmah, ali cilj mora preživjeti to brisanje da
// template zna koju karticu prisilno prikazati (mimo showClosed filtra) i
// automatski otvoriti — inače bi npr. pretraga našla gotovu ideju, odvela
// na njezinu karticu, a stavka ostala nevidljiva jer je zatvorena.
const highlightItemId = ref(null)

watch(
  () => [route.query.item, props.items],
  () => {
    const itemId = route.query.item
    if (!itemId) return
    const item = props.items.find((i) => i.id === itemId)
    if (!item) return
    highlightItemId.value = itemId
    router.replace({ query: {} })
  },
  { immediate: true },
)

async function confirmDelete(item) {
  if (blockedOffline()) return
  if (!(await confirmDestructive({ title: t('common.delete'), message: item.title }))) return
  await itemsStore.deleteItem(item.id)
}
</script>

<style scoped>
.list-scroll {
  /* 48px je vizualni razmak; safe-bottom je Android nav traka / iOS home
     indicator, inače zadnja stavka završi ispod sistemske trake. */
  padding-bottom: calc(48px + var(--aarc-safe-bottom));
}
</style>
