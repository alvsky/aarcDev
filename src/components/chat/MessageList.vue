<template>
  <div class="message-list-wrapper">
    <div ref="listEl" class="message-list q-pa-sm">
      <!-- I4: skeleton dok se prvi put puni keš za ovaj thread, ne na svaki refetch. -->
      <div v-if="loading && !messages.length" class="q-pa-sm">
        <div v-for="n in 3" :key="n" class="msg-row q-mb-sm" :class="{ 'msg-own': n === 2 }">
          <q-skeleton type="QAvatar" size="32px" v-if="n !== 2" class="msg-avatar flex-shrink-0" />
          <q-skeleton type="rect" height="36px" :width="n === 2 ? '140px' : '180px'" />
        </div>
      </div>

      <div v-else-if="!messages.length" class="text-center text-grey-5 q-mt-xl">
        {{ $t('chat.noMessages') }}
      </div>

      <template v-for="item in messagesWithSeparators" :key="item.id ?? item.separator">
        <!-- Date separator -->
        <div v-if="item.type === 'separator'" class="date-separator">
          <div class="date-separator-line" />
          <div class="date-separator-label">{{ item.label }}</div>
          <div class="date-separator-line" />
        </div>

        <!-- Poruka -->
        <div
          v-else
          :ref="(el) => setMsgRef(item.id, el)"
          class="msg-row q-mb-sm"
          :class="{ 'msg-own': isOwn(item), 'msg-highlight': highlightedId === item.id }"
        >
          <UserAvatar
            v-if="!isOwn(item)"
            :avatar-url="item.profiles?.avatar_url"
            :full-name="item.profiles?.full_name"
            :size="32"
            class="msg-avatar flex-shrink-0"
          />

          <div class="msg-bubble-wrap">
            <div class="msg-meta text-caption text-grey-6">
              {{ item.profiles?.full_name }}
              <span class="q-ml-xs">{{ formatDate.time(item.created_at) }}</span>
              <span
                v-if="item.edited_at"
                class="q-ml-xs"
                style="font-style: italic; font-size: 10px"
              >
                ({{ $t('chat.edited') }})
              </span>
              <q-icon
                v-if="item.destroy_after_read"
                name="local_fire_department"
                size="12px"
                class="q-ml-xs"
              >
                <q-tooltip>{{ $t('chat.destroyAfterRead') }}</q-tooltip>
              </q-icon>
              <q-icon v-if="item.pending" name="schedule" size="12px" class="q-ml-xs">
                <q-tooltip>{{ $t('chat.pendingSend') }}</q-tooltip>
              </q-icon>
              <q-icon
                v-else-if="item.failed"
                name="error_outline"
                color="negative"
                size="12px"
                class="q-ml-xs"
              >
                <q-tooltip>{{ $t('chat.sendFailed') }}</q-tooltip>
              </q-icon>
            </div>

            <div class="row items-end msg-bubble-row">
              <!-- Edit mode -->
              <div v-if="editingId === item.id" :key="'edit-' + item.id" class="col">
                <q-input
                  v-model="editBody"
                  outlined
                  dense
                  autogrow
                  @keydown.enter.exact.prevent="saveEdit(item.id)"
                  @keydown.escape="cancelEdit"
                />
                <div class="row q-gutter-xs q-mt-xs">
                  <q-btn
                    flat
                    dense
                    size="sm"
                    color="accent"
                    :label="$t('common.save')"
                    @click="saveEdit(item.id)"
                  />
                  <q-btn
                    flat
                    dense
                    size="sm"
                    color="grey-5"
                    :label="$t('common.cancel')"
                    @click="cancelEdit"
                  />
                </div>
              </div>

              <!-- Normal mode -->
              <div
                v-else
                :key="'view-' + item.id"
                class="msg-bubble"
                :class="{
                  'msg-bubble-own': isOwn(item),
                  'msg-pending': item.pending,
                  'msg-bubble-hidden': isHidden(item),
                }"
                @click="onBubbleClick(item)"
                @contextmenu.prevent="!isHidden(item) && openActions(item, $event)"
                @touchstart="startLongPress(item, $event)"
                @touchend="cancelLongPress"
                @touchmove="cancelLongPress"
              >
                <!-- Skrivena poruka: sadržaj se ne renderira dok je primatelj ne
                     otkrije i potvrdi u dijalogu. -->
                <div v-if="isHidden(item)" class="row items-center no-wrap msg-hidden-teaser">
                  <q-icon name="visibility_off" size="18px" class="q-mr-sm" />
                  <div>
                    <div class="msg-hidden-title">{{ $t('chat.hiddenMessage') }}</div>
                    <div class="msg-hidden-hint">{{ $t('chat.tapToReveal') }}</div>
                  </div>
                </div>

                <template v-else>
                  <div
                    v-if="item.reply_to_id"
                    class="reply-quote"
                    @click="scrollToMessage(item.reply_to_id)"
                  >
                    <template v-if="replySource(item)">
                      <div class="reply-quote-author">
                        {{ replySource(item).profiles?.full_name }}
                      </div>
                      <div class="reply-quote-body" :class="{ 'text-italic': isHiddenQuote(item) }">
                        {{
                          isHiddenQuote(item)
                            ? $t('chat.hiddenMessage')
                            : truncate(replySource(item).body) || $t('chat.imageAlt')
                        }}
                      </div>
                    </template>
                    <div v-else class="reply-quote-body text-italic">
                      {{ $t('chat.originalUnavailable') }}
                    </div>
                  </div>
                  <div v-if="item.body" class="msg-body">{{ item.body }}</div>
                  <ChatImage
                    v-if="item.attachment_url"
                    :path="item.attachment_url"
                    :alt="item.attachment_name || $t('chat.imageAlt')"
                    class="q-mt-xs"
                  />
                </template>
              </div>
            </div>
            <!-- Reakcije -->
            <div v-if="item.reactions?.length" class="row q-gutter-xs q-mt-xs">
              <q-chip
                v-for="(group, emoji) in groupedReactions(item.reactions)"
                :key="emoji"
                dense
                clickable
                :color="hasMyReaction(item.reactions, emoji) ? 'primary' : 'grey-3'"
                :text-color="hasMyReaction(item.reactions, emoji) ? 'white' : 'dark'"
                size="sm"
                @click="$emit('react', item.id, emoji)"
              >
                {{ emoji }} {{ group.length }}
                <q-tooltip>{{ group.map((r) => r.profiles?.full_name).join(', ') }}</q-tooltip>
              </q-chip>
            </div>
          </div>
        </div>
      </template>

      <div ref="bottomEl" style="height: 1px" />
    </div>

    <!-- Otkrivanje poruke koja nestaje nakon čitanja. Poruka je u trenutku
         otvaranja već uništena — dijalog je zadnji put da je korisnik vidi, pa
         je persistent (slučajan klik izvan ne smije je zatvoriti). -->
    <q-dialog v-model="revealDialog" persistent>
      <q-card style="min-width: 300px; max-width: 90vw">
        <q-card-section class="row items-center q-pb-sm">
          <q-icon name="local_fire_department" color="warning" size="20px" class="q-mr-sm" />
          <div class="text-subtitle2">{{ $t('chat.revealTitle') }}</div>
        </q-card-section>

        <q-card-section class="q-pt-none">
          <div class="text-caption text-grey-6 q-mb-xs">
            {{ revealMsg?.profiles?.full_name }}
          </div>
          <div v-if="revealMsg?.body" class="msg-body">{{ revealMsg.body }}</div>
          <ChatImage
            v-if="revealMsg?.attachment_url"
            :path="revealMsg.attachment_url"
            :alt="revealMsg.attachment_name || $t('chat.imageAlt')"
            class="q-mt-sm"
          />
        </q-card-section>

        <q-card-section class="q-pt-none text-caption text-grey-6">
          {{ $t('chat.revealHint') }}
        </q-card-section>

        <q-card-actions align="right">
          <q-btn unelevated color="primary" :label="$t('chat.revealConfirm')" @click="closeReveal" />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <!-- Emoji picker -->
    <q-dialog v-model="emojiDialog">
      <q-card style="min-width: 280px">
        <q-card-section class="text-subtitle2">Reakcija</q-card-section>
        <q-card-section>
          <div class="row q-gutter-sm">
            <q-btn
              v-for="emoji in commonEmojis"
              :key="emoji"
              flat
              round
              size="lg"
              @click="selectEmoji(emoji)"
            >
              {{ emoji }}
            </q-btn>
          </div>
        </q-card-section>
      </q-card>
    </q-dialog>
    <!-- Akcije popup — sidro je 0x0 i ne prima klikove, da klik "izvan" uvijek radi ispravno -->
    <span class="actions-menu-anchor">
      <q-menu ref="actionsMenuRef" v-model="actionsMenu" touch-position>
        <!-- Pending/failed (outbox) poruke: samo retry i brisanje iz queuea -->
        <q-list
          v-if="activeActionMsg && (activeActionMsg.pending || activeActionMsg.failed)"
          dense
          style="min-width: 160px"
        >
          <q-item
            v-if="activeActionMsg.failed"
            clickable
            @click="(chatStore.retryOutboxItem(activeActionMsg.id), closeActions())"
          >
            <q-item-section side><q-icon name="refresh" /></q-item-section>
            <q-item-section>{{ $t('chat.retry') }}</q-item-section>
          </q-item>
          <q-separator v-if="activeActionMsg.failed" />
          <q-item
            clickable
            @click="(chatStore.removeOutboxItem(activeActionMsg.id), closeActions())"
          >
            <q-item-section side><q-icon name="delete" color="negative" /></q-item-section>
            <q-item-section class="text-negative">{{ $t('common.delete') }}</q-item-section>
          </q-item>
        </q-list>

        <q-list v-else dense style="min-width: 160px">
          <q-item clickable @click="(openEmojiPicker(activeActionMsg), closeActions())">
            <q-item-section side><q-icon name="add_reaction" /></q-item-section>
            <q-item-section>Reakcija</q-item-section>
          </q-item>
          <q-separator />
          <q-item clickable @click="($emit('reply', activeActionMsg), closeActions())">
            <q-item-section side><q-icon name="reply" /></q-item-section>
            <q-item-section>{{ $t('chat.reply') }}</q-item-section>
          </q-item>
          <template v-if="activeActionMsg && isOwn(activeActionMsg)">
            <q-separator />
            <q-item clickable @click="(startEdit(activeActionMsg), closeActions())">
              <q-item-section side><q-icon name="edit" /></q-item-section>
              <q-item-section>{{ $t('common.edit') }}</q-item-section>
            </q-item>
            <q-separator />
            <q-item clickable @click="(confirmDelete(activeActionMsg.id), closeActions())">
              <q-item-section side><q-icon name="delete" color="negative" /></q-item-section>
              <q-item-section class="text-negative">{{ $t('common.delete') }}</q-item-section>
            </q-item>
          </template>
        </q-list>
      </q-menu>
    </span>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onMounted, onActivated } from 'vue'
import { useAuthStore } from 'src/stores/auth'
import { useFormatDate } from 'src/composables/useFormatDate'
import { useChatStore } from 'src/stores/chat'
import { useOfflineGuard } from 'src/composables/useOfflineGuard'
import { useConfirmDialog } from 'src/composables/useConfirmDialog'
import { useI18n } from 'vue-i18n'
import ChatImage from './ChatImage.vue'
import UserAvatar from 'src/components/shared/UserAvatar.vue'

const props = defineProps({
  messages: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
})
const emit = defineEmits(['delete', 'react', 'scrolled-to-bottom', 'reply'])

const { confirmDestructive } = useConfirmDialog()
const authStore = useAuthStore()
const formatDate = useFormatDate()
const chatStore = useChatStore()
const { blockedOffline } = useOfflineGuard()
const { locale, t } = useI18n()
const listEl = ref(null)
const bottomEl = ref(null)
const initialLoad = ref(true)
const emojiDialog = ref(false)
const revealDialog = ref(false)
const revealMsg = ref(null)
const pendingPurgeId = ref(null)
const activeMessage = ref(null)
const editingId = ref(null)
const editBody = ref('')

const commonEmojis = [
  '👍',
  '👎',
  '❤️',
  '😂',
  '😮',
  '🤔',
  '😢',
  '🥳',
  '😱',
  '🫣',
  '🤭',
  '🫠',
  '🍻',
  '👀',
  '🎉',
  '🔥',
  '✅',
  '❌',
]

const actionsMenuRef = ref(null)
const actionsMenu = ref(false)
const activeActionMsg = ref(null)
let longPressTimer = null
let longPressEvt = null

const msgRefs = {}
const highlightedId = ref(null)

const isOwn = (msg) => msg.author_id === authStore.user?.id

// Date separator logika
const messagesWithSeparators = computed(() => {
  const result = []
  let lastDate = null
  const today = new Date()
  const todayStr = today.toDateString()
  const yesterday = new Date(today)
  yesterday.setDate(today.getDate() - 1)
  const yesterdayStr = yesterday.toDateString()

  for (const msg of props.messages) {
    const msgDate = new Date(msg.created_at)
    const msgDateStr = msgDate.toDateString()

    if (msgDateStr !== lastDate) {
      let label = ''
      if (msgDateStr === todayStr) {
        label = locale.value === 'hr' ? 'Danas' : 'Today'
      } else if (msgDateStr === yesterdayStr) {
        label = locale.value === 'hr' ? 'Jučer' : 'Yesterday'
      } else {
        label = msgDate.toLocaleDateString(locale.value, {
          weekday: 'long',
          day: '2-digit',
          month: '2-digit',
          year: 'numeric',
        })
      }
      result.push({ type: 'separator', separator: msgDateStr, label })
      lastDate = msgDateStr
    }

    result.push({ ...msg, type: 'message' })
  }

  return result
})

const groupedReactions = (reactions) => {
  const groups = {}
  for (const r of reactions ?? []) {
    if (!groups[r.emoji]) groups[r.emoji] = []
    groups[r.emoji].push(r)
  }
  return groups
}

const hasMyReaction = (reactions, emoji) =>
  reactions?.some((r) => r.emoji === emoji && r.user_id === authStore.user?.id)

function replySource(item) {
  return props.messages.find((m) => m.id === item.reply_to_id) ?? null
}

function truncate(text, max = 80) {
  if (!text) return ''
  return text.length > max ? text.slice(0, max) + '…' : text
}

function setMsgRef(id, el) {
  if (el) msgRefs[id] = el
  else delete msgRefs[id]
}

function scrollToMessage(id) {
  const el = msgRefs[id]
  if (!el) return
  el.scrollIntoView({ behavior: 'smooth', block: 'center' })
  highlightedId.value = id
  setTimeout(() => {
    if (highlightedId.value === id) highlightedId.value = null
  }, 1200)
}

function openEmojiPicker(msg) {
  activeMessage.value = msg
  emojiDialog.value = true
}

function selectEmoji(emoji) {
  emojiDialog.value = false
  if (activeMessage.value) {
    emit('react', activeMessage.value.id, emoji)
    activeMessage.value = null
  }
}

function openActions(msg, evt) {
  if (editingId.value) return
  activeActionMsg.value = msg
  actionsMenuRef.value?.show(evt)
}

function closeActions() {
  actionsMenuRef.value?.hide()
}

// Skrivena je samo tuđa poruka koja je stvarno poslana — vlastita se autoru
// prikazuje normalno, a pending/failed još nema retka u bazi.
function isHidden(msg) {
  return !!msg?.destroy_after_read && !isOwn(msg) && !msg.pending && !msg.failed
}

// Citat odgovora ne smije otkriti sadržaj poruke koju korisnik još nije otvorio.
function isHiddenQuote(item) {
  return isHidden(replySource(item))
}

async function onBubbleClick(item) {
  if (!isHidden(item)) return
  // Uništavanje mora proći kroz server; offline bi se poruka vratila na
  // sljedeći fetch, nakon što smo korisniku već rekli da je nema.
  if (blockedOffline('chat.offlineNoDelete')) return

  // Otvaranje JEST čitanje — poruka se uništava odmah, prije prikaza, pa je
  // korisnik ne može zadržati zatvaranjem dijaloga ili gašenjem aplikacije.
  // Vlastita kopija (ne referenca na redak u storeu) preživi to uklanjanje i
  // ostane u dijalogu dok je ne zatvori.
  const snapshot = { ...item }
  const { ok, fullyRead } = await chatStore.markMessageAsRead(item.id, { purge: false })
  if (!ok) return

  revealMsg.value = snapshot
  pendingPurgeId.value = fullyRead ? item.id : null
  revealDialog.value = true
}

// Redak i prilog se brišu tek na zatvaranje dijaloga — dok je otvoren, potpisani
// URL priloga mora ostati valjan.
function closeReveal() {
  revealDialog.value = false
  revealMsg.value = null
  if (pendingPurgeId.value) {
    chatStore.purgeMessage(pendingPurgeId.value)
    pendingPurgeId.value = null
  }
}

function startLongPress(msg, evt) {
  if (editingId.value || isHidden(msg)) return
  longPressEvt = evt
  longPressTimer = setTimeout(() => {
    openActions(msg, longPressEvt)
  }, 500)
}

function cancelLongPress() {
  if (longPressTimer) {
    clearTimeout(longPressTimer)
    longPressTimer = null
  }
  longPressEvt = null
}

function startEdit(msg) {
  editingId.value = msg.id
  editBody.value = msg.body
}

function cancelEdit() {
  editingId.value = null
  editBody.value = ''
}

async function confirmDelete(id) {
  // Offline brisanje ne prolazi na serveru (poruka se vrati) — spriječi ga
  if (blockedOffline('chat.offlineNoDelete')) return
  const ok = await confirmDestructive({
    title: t('common.delete'),
    message: t('chat.deleteConfirm'),
  })
  if (!ok) return
  emit('delete', id)
}

async function saveEdit(id) {
  if (!editBody.value.trim()) return
  await chatStore.editMessage(id, editBody.value.trim())
  for (const key of Object.keys(chatStore.threads)) {
    const msg = chatStore.threads[key]?.find((m) => m.id === id)
    if (msg) {
      msg.body = editBody.value.trim()
      msg.edited_at = new Date().toISOString()
    }
  }
  cancelEdit()
}

const scrollToBottom = async (behavior = 'instant') => {
  await nextTick()
  if (bottomEl.value) {
    bottomEl.value.scrollIntoView({ behavior })
    emit('scrolled-to-bottom')
  }
}

defineExpose({ scrollToBottom })

watch(
  () => props.messages.length,
  async (newLen, oldLen) => {
    if (initialLoad.value && newLen > 0) {
      initialLoad.value = false
      await scrollToBottom('instant')
    } else if (!initialLoad.value && newLen > oldLen) {
      await scrollToBottom('smooth')
    }
  },
)

onMounted(() => {
  initialLoad.value = true
})

onActivated(async () => {
  initialLoad.value = true
  await nextTick()
  if (props.messages.length > 0) {
    initialLoad.value = false
    await scrollToBottom('instant')
  }
})
</script>

<style scoped>
.message-list-wrapper {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
}

.message-list {
  overflow-y: auto;
  overflow-x: hidden;
  flex: 1;
  min-height: 0;
  box-sizing: border-box;
}

.msg-row {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  margin-bottom: 8px;
}

.msg-own {
  flex-direction: row-reverse;
}

.msg-own .msg-meta {
  text-align: right;
}

/* min-width: 0 kroz cijeli lanac (wrap → mjehurić): zadani min-width flex itema je
   auto, tj. širina najužeg mogućeg sadržaja. Citat odgovora je nowrap, pa bi bez ovoga
   njegov tekst bio donja granica širine i pobijedio max-width — mjehurić se razvuče i
   lista se počne skrolati vodoravno. Uže kad je lista uža (thread), pa se tamo i vidjelo. */
.msg-bubble-wrap {
  max-width: 75%;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

/* .msg-own .msg-bubble-wrap {
  align-items: flex-end;
} */
.msg-own .msg-bubble-wrap {
  align-items: flex-end;
  flex: 1;
}
/* Vlastite poruke su poravnate desno, pa im višak širine bježi ulijevo i ne stvara
   scrollWidth — samo se odreže. Zato lanac mora imati min-width: 0 i ovdje. */
.msg-bubble-row {
  min-width: 0;
  max-width: 100%;
}

.msg-meta {
  margin-bottom: 2px;
}

.msg-bubble {
  display: inline-block;
  background: #f1f2f6;
  border-radius: 0 12px 12px 12px;
  padding: 8px 12px;
  max-width: 100%;
  min-width: 0;
  word-break: break-word;
}

.msg-bubble-own {
  background: #d4f6ff;
  color: #011c3a;
  border-radius: 12px 0 12px 12px;
}

.msg-bubble-hidden {
  cursor: pointer;
  background: #ece9f5;
  border: 1px dashed #9b8fc4;
  color: #4a3f6b;
}

.msg-hidden-teaser {
  min-width: 0;
}

.msg-hidden-title {
  font-size: 14px;
  font-weight: 600;
}

.msg-hidden-hint {
  font-size: 11px;
  opacity: 0.7;
}

.msg-body {
  white-space: pre-wrap;
  word-break: break-word;
  font-size: 14px;
}

.msg-actions {
  opacity: 0;
  transition: opacity 0.15s;
}

.msg-row:hover .msg-actions {
  opacity: 1;
}

.reply-quote {
  display: flex;
  flex-direction: column;
  min-width: 0;
  gap: 1px;
  padding: 4px 8px;
  margin-bottom: 4px;
  border-left: 3px solid var(--q-primary, #1976d2);
  background: rgba(0, 0, 0, 0.04);
  border-radius: 4px;
  cursor: pointer;
}

.reply-quote-author {
  font-size: 11px;
  font-weight: 600;
  color: var(--q-primary, #1976d2);
}

.reply-quote-body {
  font-size: 12px;
  color: #555;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
}

.msg-bubble-own .reply-quote {
  background: rgba(255, 255, 255, 0.35);
}

@keyframes msg-highlight-flash {
  0% {
    background-color: rgba(255, 213, 79, 0.6);
  }
  100% {
    background-color: transparent;
  }
}

.msg-highlight .msg-bubble {
  animation: msg-highlight-flash 1.2s ease;
}

.msg-pending {
  opacity: 0.55;
}

.actions-menu-anchor {
  position: fixed;
  top: 0;
  left: 0;
  width: 0;
  height: 0;
  pointer-events: none;
}
</style>
