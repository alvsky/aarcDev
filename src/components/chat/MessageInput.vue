<template>
  <div class="message-input-wrap">
    <!-- Reply preview -->
    <div v-if="replyTo" class="reply-preview row items-center no-wrap q-pa-xs q-mb-xs">
      <q-icon name="reply" size="18px" color="primary" class="q-mr-xs" />
      <div class="col ellipsis reply-preview-text">
        <div class="text-caption text-primary text-weight-medium ellipsis">
          {{ replyTo.profiles?.full_name }}
        </div>
        <div class="text-caption text-grey-7 ellipsis">
          {{ replyTo.body || $t('chat.imageAlt') }}
        </div>
      </div>
      <q-btn flat round dense icon="close" size="sm" @click="$emit('cancel-reply')" />
    </div>

    <!-- Preview slike prije slanja -->
    <div v-if="pendingImage" class="row items-center q-pa-xs q-gutter-sm q-mb-xs">
      <img :src="pendingPreview" class="preview-thumb" :alt="$t('chat.imageAlt')" />
      <div class="col text-caption text-grey-6 ellipsis">
        {{ pendingImage.name }}
      </div>
      <q-btn flat round dense icon="close" size="sm" @click="clearPending" />
    </div>

    <!-- Drop zona -->
    <div
      v-if="isDragging"
      class="drop-zone flex flex-center"
      @dragover.prevent
      @dragleave="isDragging = false"
      @drop.prevent="onDrop"
    >
      <div class="text-body2 text-grey-5 text-center">
        <q-icon name="image" size="32px" /><br />
        {{ $t('chat.pasteOrDrop') }}
      </div>
    </div>

    <div class="row items-end q-gutter-xs">
      <!-- File picker gumb -->
      <q-btn
        flat
        round
        dense
        icon="attach_file"
        color="grey-6"
        :loading="uploading"
        :disable="!online"
        @click="triggerFilePicker"
      >
        <q-tooltip>{{ $t('chat.pasteOrDrop') }}</q-tooltip>
      </q-btn>

      <input ref="fileInput" type="file" accept="image/*" class="hidden" @change="onFileSelected" />

      <!-- Tekstualni input -->
      <q-input
        v-model="body"
        type="textarea"
        :placeholder="pendingImage ? $t('chat.imageAlt') : $t('chat.placeholder')"
        outlined
        dense
        autogrow
        class="col"
        @keydown.enter.exact="onEnter"
        @paste="onPaste"
        @dragenter.prevent="isDragging = true"
      />

      <!-- Send gumb -->
      <q-btn
        round
        dense
        icon="send"
        color="primary"
        :disable="!canSend"
        :loading="sending"
        @click="send"
      />
    </div>

    <div class="text-caption text-grey-5 q-mt-xs q-ml-sm">
      {{ $t('chat.pasteHint') }}
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { Capacitor } from '@capacitor/core'
import { useChatStore } from 'src/stores/chat'
import { useProjectsStore } from 'src/stores/projects'
import { useImageUpload } from 'src/composables/useImageUpload'
import { useNetwork } from 'src/composables/useNetwork'

const props = defineProps({
  projectId: { type: String, required: true },
  itemId: { type: String, default: null },
  channel: { type: String, default: 'main' },
  replyTo: { type: Object, default: null },
})

const emit = defineEmits(['cancel-reply'])

const $q = useQuasar()
const { t } = useI18n()
const chatStore = useChatStore()
const projectsStore = useProjectsStore()
const { uploading, uploadImage } = useImageUpload()
const { online } = useNetwork()

const body = ref('')
const sending = ref(false)
const isDragging = ref(false)
const pendingImage = ref(null)
const pendingPreview = ref(null)
const fileInput = ref(null)

const canSend = computed(() => !!body.value.trim() || !!pendingImage.value)

// Na mobitelu nema Shift za novi red, pa Enter na tipkovnici mora ostati
// običan prijelaz u novi red — poruka ide isključivo preko send gumba.
// Na desktopu (fizička tipkovnica) Enter šalje, Shift+Enter pravi novi red.
function onEnter(e) {
  if (Capacitor.isNativePlatform()) return
  e.preventDefault()
  send()
}

async function onPaste(e) {
  const items = Array.from(e.clipboardData?.items ?? [])
  const imageItem = items.find((i) => i.type.startsWith('image/'))
  if (!imageItem) return // ako nema slike, pusti normalni paste teksta
  e.preventDefault()
  if (!online.value) return // prilozi traže mrežu
  setPending(imageItem.getAsFile())
}
function onDrop(e) {
  isDragging.value = false
  if (!online.value) return // prilozi traže mrežu
  const file = e.dataTransfer?.files?.[0]
  if (file?.type.startsWith('image/')) setPending(file)
}

function triggerFilePicker() {
  fileInput.value?.click()
}

function onFileSelected(e) {
  setPending(e.target.files[0])
}

function setPending(file) {
  if (!file) return
  pendingImage.value = file
  pendingPreview.value = URL.createObjectURL(file)
}

function clearPending() {
  if (pendingPreview.value) URL.revokeObjectURL(pendingPreview.value)
  pendingImage.value = null
  pendingPreview.value = null
  if (fileInput.value) fileInput.value.value = ''
}

async function send() {
  if (!canSend.value || sending.value) return
  sending.value = true

  // Prije slanja: poruka aktivira DB okidač auto_follow_on_message koji upiše
  // pretplatu ako je nema. Provjera mora ići PRIJE slanja da uhvati prijelaz
  // (nakon slanja bi redak već postojao i izgledalo bi kao da je oduvijek).
  const wasFollowing = projectsStore.isFollowing(props.projectId)

  const hadImage = !!pendingImage.value
  let attachmentUploaded = false

  try {
    let attachmentUrl = null
    let attachmentType = null
    let attachmentName = null

    if (pendingImage.value) {
      const uploaded = await uploadImage(pendingImage.value, {
        maxWidth: 1440,
        quality: 0.65,
        pathPrefix: props.projectId,
      })
      attachmentUrl = uploaded.path
      attachmentType = uploaded.type
      attachmentName = uploaded.name
      attachmentUploaded = true
    }

    await chatStore.sendMessage({
      projectId: props.projectId,
      itemId: props.itemId,
      channel: props.channel,
      body: body.value.trim(),
      attachmentUrl,
      attachmentType,
      attachmentName,
      replyToId: props.replyTo?.id ?? null,
    })

    body.value = ''
    clearPending()
    if (props.replyTo) emit('cancel-reply')

    if (!wasFollowing) {
      projectsStore.markFollowingLocally(props.projectId)
      const name = projectsStore.getById(props.projectId)?.name ?? ''
      $q.notify({
        message: t('projects.nowFollowing', { name }),
        color: 'primary',
        icon: 'visibility',
        timeout: 6000,
        actions: [
          {
            label: t('projects.unfollow'),
            color: 'white',
            handler: async () => {
              try {
                await projectsStore.unfollowProject(props.projectId)
                $q.notify({ type: 'positive', message: t('projects.unfollowed') })
              } catch (e) {
                $q.notify({ type: 'negative', message: e.message })
              }
            },
          },
        ],
      })
    }
  } catch (err) {
    // Prije je svaka greška (i pad chatStore.sendMessage, ne samo uploada)
    // krivila sliku — zavaravalo je dijagnozu čim je razlog bio bilo što
    // drugo (RLS, mreža...). Sad kriva samo ono što je stvarno palo.
    console.error('[chat] slanje poruke nije uspjelo:', err)
    const message =
      hadImage && !attachmentUploaded
        ? t('chat.attachmentFail')
        : (err?.message ?? t('chat.sendFailed'))
    $q.notify({ type: 'negative', message })
  } finally {
    sending.value = false
  }
}
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

.msg-bubble-wrap {
  max-width: 75%;
  display: flex;
  flex-direction: column;
}

.msg-own .msg-bubble-wrap {
  align-items: flex-end;
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
  word-break: break-word;
}

.msg-bubble-own {
  background: #d4f6ff;
  color: #011c3a;
  border-radius: 12px 0 12px 12px;
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

.message-input-wrap {
  min-width: 0;
  max-width: 100%;
}

.reply-preview {
  background: #f1f2f6;
  border-left: 3px solid var(--q-primary, #1976d2);
  border-radius: 4px;
  min-width: 0;
}

/* Bez ovoga citirani tekst ne može ispod svoje pune širine (min-width flex itema
   je auto), pa razvuče cijeli thread dijalog umjesto da se skrati s "…". */
.reply-preview-text {
  min-width: 0;
}

.preview-thumb {
  max-width: 64px;
  max-height: 64px;
  width: auto;
  height: auto;
  object-fit: contain;
  border-radius: 6px;
  border: 1px solid rgba(0, 0, 0, 0.08);
  flex-shrink: 0;
}
</style>
