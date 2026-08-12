<template>
  <q-dialog :model-value="modelValue" @update:model-value="$emit('update:modelValue', $event)">
    <q-card style="width: 480px; max-width: 95vw">
      <q-card-section class="q-pb-none">
        <div class="text-subtitle1 q-mb-sm">{{ $t('search.title') }}</div>
        <q-input
          ref="inputRef"
          v-model="query"
          dense
          outlined
          autofocus
          clearable
          :placeholder="$t('search.placeholder')"
        >
          <template #prepend><q-icon name="search" size="18px" /></template>
        </q-input>
        <q-checkbox
          v-model="includeMessages"
          dense
          size="sm"
          :label="$t('search.includeMessages')"
          class="q-mt-sm"
        />
      </q-card-section>

      <q-separator class="q-mt-md" />

      <q-card-section style="max-height: 60vh; overflow-y: auto" class="q-pa-none">
        <div v-if="!query.trim()" class="text-center text-grey-5 q-pa-lg">
          {{ $t('search.hint') }}
        </div>

        <template v-else>
          <div v-if="itemResults.length" class="text-caption text-grey-6 q-px-md q-pt-sm">
            {{ $t('search.items') }}
          </div>
          <q-list separator>
            <q-item v-for="item in itemResults" :key="item.id" clickable @click="openItem(item)">
              <q-item-section side>
                <q-icon :name="kindIcon(item.kind)" />
              </q-item-section>
              <q-item-section>
                <q-item-label>{{ item.title }}</q-item-label>
                <q-item-label caption class="ellipsis">
                  {{ item.description }}
                </q-item-label>
              </q-item-section>
              <q-item-section side v-if="TERMINAL.includes(item.stage)">
                <q-badge color="grey-6">{{ $t(`items.stage.${item.stage}`) }}</q-badge>
              </q-item-section>
            </q-item>
          </q-list>

          <div v-if="includeMessages" class="text-caption text-grey-6 q-px-md q-pt-md">
            {{ $t('search.messages') }}
          </div>
          <div v-if="includeMessages && searchingMessages" class="flex flex-center q-pa-md">
            <q-spinner size="20px" color="primary" />
          </div>
          <q-list v-else-if="includeMessages" separator>
            <q-item
              v-for="msg in messageResults"
              :key="msg.id"
              clickable
              @click="openMessage(msg)"
            >
              <q-item-section side>
                <UserAvatar
                  :avatar-url="msg.profiles?.avatar_url"
                  :full-name="msg.profiles?.full_name"
                  :size="28"
                />
              </q-item-section>
              <q-item-section>
                <q-item-label caption>{{ msg.profiles?.full_name }}</q-item-label>
                <q-item-label class="ellipsis">{{ msg.body }}</q-item-label>
              </q-item-section>
            </q-item>
          </q-list>

          <div
            v-if="
              !itemResults.length && (!includeMessages || (!searchingMessages && !messageResults.length))
            "
            class="text-center text-grey-5 q-pa-lg"
          >
            {{ $t('search.noResults') }}
          </div>
        </template>
      </q-card-section>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useItemsStore } from 'src/stores/items'
import { useChatStore } from 'src/stores/chat'
import { normalizeSearch } from 'src/utils/text'
import { tabForItem } from 'src/utils/itemTabs'
import UserAvatar from './UserAvatar.vue'

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  projectId: { type: String, required: true },
})
const emit = defineEmits(['update:modelValue'])

const router = useRouter()
const itemsStore = useItemsStore()
const chatStore = useChatStore()

const query = ref('')
const includeMessages = ref(false)
const messageResults = ref([])
const searchingMessages = ref(false)

const TERMINAL = ['done', 'rejected']

const KIND_ICON = { idea: 'lightbulb', bug: 'bug_report', task: 'checklist' }
function kindIcon(kind) {
  return KIND_ICON[kind] ?? 'lightbulb'
}

// Namjerno pretražuje SVE stavke projekta (itemsStore.byProject), svih
// faza — uključujući gotove/odbijene. To je i svrha: "je li ovo već bilo?"
// ne pita samo o aktivnom radu.
const itemResults = computed(() => {
  const q = normalizeSearch(query.value.trim())
  if (!q) return []
  return itemsStore
    .byProject(props.projectId)
    .filter(
      (i) => normalizeSearch(i.title).includes(q) || normalizeSearch(i.description).includes(q),
    )
})

let debounceTimer = null
watch([query, includeMessages], ([q, include]) => {
  clearTimeout(debounceTimer)
  if (!include || !q.trim()) {
    messageResults.value = []
    searchingMessages.value = false
    return
  }
  searchingMessages.value = true
  debounceTimer = setTimeout(async () => {
    try {
      messageResults.value = await chatStore.searchMessages(props.projectId, q)
    } finally {
      searchingMessages.value = false
    }
  }, 300)
})

function close() {
  emit('update:modelValue', false)
  query.value = ''
  includeMessages.value = false
  messageResults.value = []
}

function openItem(item) {
  router.push({ path: `/project/${props.projectId}/${tabForItem(item)}`, query: { item: item.id } })
  close()
}

function openMessage(msg) {
  if (msg.item_id) {
    const item = itemsStore.items.find((i) => i.id === msg.item_id)
    const tab = item ? tabForItem(item) : 'chat'
    const targetQuery = item ? { item: msg.item_id } : {}
    router.push({ path: `/project/${props.projectId}/${tab}`, query: targetQuery })
  } else {
    router.push({
      path: `/project/${props.projectId}/chat`,
      query: { channel: msg.channel ?? 'main' },
    })
  }
  close()
}
</script>
