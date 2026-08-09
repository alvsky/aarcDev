<template>
  <!-- Jedna kartica za ideje, bugove i zadatke — zamjenjuje IdeaCard/BugCard/TbiCard,
       koje su bile gotovo iste. Vidi docs/item-model.md. -->
  <q-expansion-item
    :group="group"
    expand-separator
    :class="{ 'opacity-5': isTerminal }"
    :header-class="isTerminal ? 'text-grey-5' : ''"
    @update:model-value="(val) => val && onOpen()"
  >
    <template #header>
      <!-- Stanje i praćenje uvijek na istom mjestu, neovisno o duljini naslova.
           Oko je ujedno prekidač — bez otvaranja kartice. -->
      <q-item-section avatar class="item-lead">
        <div class="row items-center no-wrap">
          <q-icon :name="stageIcon" :color="stageColor" size="22px" />
          <div
            class="watch-dot"
            :class="{ 'watch-dot--on': item.watching }"
            @click.stop="itemsStore.toggleWatch(item.id)"
          >
            <q-icon name="visibility" size="16px" />
            <q-tooltip>
              {{ item.watching ? $t('items.unwatch') : $t('items.watchHint') }}
            </q-tooltip>
          </div>
        </div>
      </q-item-section>

      <q-item-section>
        <q-item-label :class="{ 'text-strike': isTerminal }">
          {{ item.title }}
          <q-badge
            v-if="item.is_new"
            color="accent"
            class="q-ml-xs"
            style="font-size: 9px; padding: 2px 5px"
          >
            NEW
          </q-badge>
        </q-item-label>
        <q-item-label caption>
          <!-- Vrsta se prikazuje samo ondje gdje se miješaju (TBI ploča) -->
          <q-badge v-if="showKind" color="grey-7" outline class="q-mr-xs">
            {{ $t(`items.kind.${item.kind}`) }}
          </q-badge>
          <q-badge :color="prioColor" outline class="q-mr-xs">
            {{ $t(`bugs.priority.${item.priority}`) }}
          </q-badge>
          <q-badge :color="stageColor" outline>
            {{ $t(`items.stage.${item.stage}`) }}
          </q-badge>
        </q-item-label>
      </q-item-section>

      <q-item-section side>
        <div class="row items-center q-gutter-xs">
          <q-btn
            flat
            round
            dense
            icon="forum"
            size="sm"
            color="grey-6"
            @click.stop="$emit('open-thread')"
          >
            <q-badge v-if="unread > 0" color="negative" floating rounded>
              {{ unread }}
            </q-badge>
          </q-btn>
          <div
            v-if="item.message_count > 0"
            class="text-caption"
            style="color: var(--aarc-muted); font-size: 10px"
          >
            {{ item.message_count }}
          </div>
        </div>
      </q-item-section>
    </template>

    <q-card flat class="q-mx-md q-mb-sm">
      <q-card-section class="q-pa-sm">
        <div v-if="item.description" class="text-body2 q-mb-sm">
          {{ item.description }}
        </div>

        <ChatImage
          v-if="item.screenshot_url"
          :path="item.screenshot_url"
          :alt="item.title"
          class="q-mb-sm"
        />

        <!-- Faza, prioritet, izvršitelj -->
        <div class="row q-col-gutter-sm q-mb-sm">
          <div class="col-6">
            <q-select
              :model-value="item.stage"
              :label="$t('common.status')"
              :options="stageOptions"
              outlined
              dense
              emit-value
              map-options
              @update:model-value="onStage"
            />
          </div>
          <div class="col-6">
            <q-select
              :model-value="item.priority"
              :label="$t('common.priority')"
              :options="priorityOptions"
              outlined
              dense
              emit-value
              map-options
              @update:model-value="(v) => itemsStore.updateItem(item.id, { priority: v })"
            />
          </div>
          <div v-if="members.length" class="col-12">
            <q-select
              :model-value="item.assignee_id"
              :options="memberOptions"
              :label="$t('tbi.assignee')"
              outlined
              dense
              clearable
              emit-value
              map-options
              @update:model-value="(v) => itemsStore.assign(item.id, v)"
            />
          </div>
        </div>

        <!-- Tko, kad -->
        <div class="row items-center q-gutter-sm text-caption text-grey-5 q-mb-sm">
          <q-icon name="person" size="12px" />
          <span>{{ item.profiles?.full_name }}</span>
          <q-icon name="schedule" size="12px" />
          <span>{{ formatDate.relative(item.created_at) }}</span>
          <template v-if="item.assignee">
            <q-icon name="assignment_ind" size="12px" />
            <span>{{ item.assignee?.full_name }}</span>
          </template>
          <!-- Autorstvo prijelaza: tko je predložio ostaje odvojeno od toga tko je prihvatio -->
          <template v-if="item.accepted_profile && item.accepted_by !== item.created_by">
            <q-icon name="task_alt" size="12px" />
            <span>{{ $t('items.acceptedBy') }}: {{ item.accepted_profile?.full_name }}</span>
          </template>
          <template v-if="item.completed_at">
            <q-icon name="check_circle" size="12px" color="positive" />
            <span>{{ formatDate.smart(item.completed_at) }}</span>
          </template>
        </div>

        <div class="row q-gutter-xs">
          <q-btn
            v-if="canAccept"
            flat
            dense
            icon="task_alt"
            size="sm"
            color="purple"
            :label="$t('items.accept')"
            @click="itemsStore.accept(item.id)"
          />
          <q-btn
            v-if="!isTerminal"
            flat
            dense
            icon="block"
            size="sm"
            color="warning"
            :label="$t('items.reject')"
            @click="itemsStore.reject(item.id)"
          />
          <q-btn
            v-if="isTerminal"
            flat
            dense
            icon="undo"
            size="sm"
            color="warning"
            :label="$t('items.reopen')"
            @click="itemsStore.reopen(item.id)"
          />
          <q-btn
            flat
            dense
            icon="edit"
            size="sm"
            :label="$t('common.edit')"
            @click="$emit('edit')"
          />
          <q-btn
            flat
            dense
            icon="delete"
            size="sm"
            color="negative"
            :label="$t('common.delete')"
            @click="$emit('delete')"
          />
        </div>
      </q-card-section>
    </q-card>
  </q-expansion-item>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useItemsStore } from 'src/stores/items'
import { useNotificationsStore } from 'src/stores/notifications'
import { useFormatDate } from 'src/composables/useFormatDate'
import ChatImage from 'src/components/chat/ChatImage.vue'

const props = defineProps({
  item: { type: Object, required: true },
  projectId: { type: String, required: true },
  members: { type: Array, default: () => [] },
  // Odvojena q-expansion-item grupa po kartici, da otvaranje na jednoj ne zatvara drugu
  group: { type: String, default: 'items' },
  showKind: { type: Boolean, default: false },
})

defineEmits(['edit', 'delete', 'open-thread'])

const { t } = useI18n()
const itemsStore = useItemsStore()
const notifStore = useNotificationsStore()
const formatDate = useFormatDate()

const ACTIVE = ['accepted', 'in_progress', 'testing']
const isTerminal = computed(() => ['done', 'rejected'].includes(props.item.stage))
const canAccept = computed(() => ['new', 'confirmed'].includes(props.item.stage))

const unread = computed(() =>
  notifStore.threadUnread({ projectId: props.projectId, itemId: props.item.id }),
)

const stageOptions = computed(() =>
  ['new', 'confirmed', 'accepted', 'in_progress', 'testing', 'done', 'rejected'].map((s) => ({
    label: t(`items.stage.${s}`),
    value: s,
  })),
)

const priorityOptions = computed(() =>
  ['low', 'med', 'high'].map((p) => ({ label: t(`bugs.priority.${p}`), value: p })),
)

const memberOptions = computed(() =>
  props.members.map((m) => ({
    label: m.profiles?.full_name ?? m.profiles?.email,
    value: m.user_id,
  })),
)

const stageIcon = computed(
  () =>
    ({
      new: 'radio_button_unchecked',
      confirmed: 'check_circle_outline',
      accepted: 'task_alt',
      in_progress: 'pending',
      testing: 'science',
      done: 'check_circle',
      rejected: 'block',
    })[props.item.stage] ?? 'radio_button_unchecked',
)

const stageColor = computed(
  () =>
    ({
      new: 'grey',
      confirmed: 'info',
      accepted: 'purple',
      in_progress: 'warning',
      testing: 'info',
      done: 'positive',
      rejected: 'negative',
    })[props.item.stage] ?? 'grey',
)

const prioColor = computed(
  () => ({ high: 'negative', med: 'warning', low: 'positive' })[props.item.priority] ?? 'grey',
)

// Prijelazi kroz store da by/at stupci ostanu ispravni — običan update ih ne bi popunio.
function onStage(next) {
  if (next === props.item.stage) return
  if (next === 'done') return itemsStore.markDone(props.item.id)
  if (next === 'rejected') return itemsStore.reject(props.item.id)
  if (next === 'accepted' && !ACTIVE.includes(props.item.stage))
    return itemsStore.accept(props.item.id)
  return itemsStore.updateItem(props.item.id, { stage: next })
}

async function onOpen() {
  if (!props.item.is_new) return
  await itemsStore.markRead(props.item.id)
}
</script>

<style scoped>
/* Lijevi stupac drži dvije ikone, pa mu treba nešto više od Quasarove zadane širine. */
.item-lead {
  min-width: 62px;
  padding-right: 8px;
}

/* Ugašeno stanje je namjerno prigušeno, ali zauzima prostor — tako ikona stanja
   ostaje poravnata u svim redovima, a oko je uvijek na istom mjestu. */
.watch-dot {
  width: 26px;
  height: 26px;
  margin-left: 2px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  color: var(--aarc-muted);
  opacity: 0.28;
  cursor: pointer;
  transition:
    opacity 0.15s,
    background 0.15s,
    color 0.15s;
}

.watch-dot:hover {
  opacity: 0.7;
}

.watch-dot--on {
  background: var(--aarc-accent);
  color: #fff;
  opacity: 1;
}
</style>
