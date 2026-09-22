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

    <!-- Preview slika prije slanja — svaka postaje svoja poruka pri slanju -->
    <div v-if="pendingImages.length" class="row items-center q-gutter-sm q-pa-xs q-mb-xs">
      <div v-for="(file, i) in pendingImages" :key="i" class="preview-item">
        <img :src="previews[i]" class="preview-thumb" :alt="$t('chat.imageAlt')" />
        <q-btn
          flat
          round
          dense
          size="xs"
          icon="close"
          class="preview-remove"
          @click="removePending(i)"
        />
      </div>
    </div>

    <!-- Drop zona -->
    <div
      v-if="isDragging"
      class="drop-zone flex flex-center"
      @dragover.prevent
      @dragleave="stopDragging"
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

      <input
        ref="fileInput"
        type="file"
        accept="image/*"
        multiple
        class="hidden"
        @change="onFileSelected"
      />

      <!-- Tekstualni input -->
      <q-input
        v-model="body"
        type="textarea"
        :placeholder="pendingImages.length ? $t('chat.imageAlt') : $t('chat.placeholder')"
        outlined
        dense
        autogrow
        class="col"
        @keydown.enter.exact="onEnter"
        @paste="onPaste"
        @dragenter.prevent="startDragging"
      />

      <!-- Ugašena vatra = obična poruka; upaljena = nestaje nakon čitanja. Skriveno
           iza feature flaga (vidi useFeatureFlagsStore) umjesto zakomentiranog koda —
           prekidač se sad uključuje/isključuje iz OrgPage.vue bez novog builda. -->
      <q-btn
        v-if="disappearingMessagesEnabled"
        flat
        round
        dense
        icon="local_fire_department"
        :color="destroyAfterRead ? 'deep-orange' : 'grey-5'"
        :aria-pressed="destroyAfterRead"
        @click="toggleDestroyAfterRead"
      >
        <q-tooltip>{{ $t('chat.destroyAfterRead') }}</q-tooltip>
      </q-btn>

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

    <div v-if="!isNative" class="text-caption text-grey-5 q-mt-xs q-ml-sm">
      {{ $t('chat.pasteHint') }}
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onUnmounted } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { dbErrorMessage } from 'src/utils/dbErrorMessage'
import { Capacitor } from '@capacitor/core'
import { useChatStore } from 'src/stores/chat'
import { useProjectsStore } from 'src/stores/projects'
import { useFeatureFlagsStore } from 'src/stores/featureFlags'
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
const featureFlagsStore = useFeatureFlagsStore()
const { uploading, uploadImage } = useImageUpload()
const { online } = useNetwork()

const disappearingMessagesEnabled = computed(() =>
  featureFlagsStore.isEnabled('disappearing_messages'),
)

const MAX_PENDING_IMAGES = 10

const body = ref('')
const sending = ref(false)
const isDragging = ref(false)
const pendingImages = ref([]) // File[] — svaka postaje svoja poruka pri slanju
const previews = ref([]) // objectURL po indeksu, isti obrazac kao ScreenshotUpload.vue
const fileInput = ref(null)
const destroyAfterRead = ref(false)

watch(pendingImages, (files) => {
  for (const url of previews.value) URL.revokeObjectURL(url)
  previews.value = files.map((f) => URL.createObjectURL(f))
})

// Sve tri idu kroz funkciju, ne kroz pridruživanje u predlošku (@click="x = !x"):
// tako je pisan i prekidač za vatru, pa se zastavica nije mijenjala i poruke su
// odlazile kao obične. Drop zona je bila na istom obrascu.
function toggleDestroyAfterRead() {
  destroyAfterRead.value = !destroyAfterRead.value
}

function startDragging() {
  isDragging.value = true
}

function stopDragging() {
  isDragging.value = false
}

const canSend = computed(() => !!body.value.trim() || pendingImages.value.length > 0)
const isNative = Capacitor.isNativePlatform()

// Na mobitelu nema Shift za novi red, pa Enter na tipkovnici mora ostati
// običan prijelaz u novi red — poruka ide isključivo preko send gumba.
// Na desktopu (fizička tipkovnica) Enter šalje, Shift+Enter pravi novi red.
function onEnter(e) {
  if (isNative) return
  e.preventDefault()
  send()
}

// Clipboard zna nositi više slika odjednom (npr. kopiran raspon iz file
// managera) — uzmi ih sve, ne samo prvu.
async function onPaste(e) {
  const items = Array.from(e.clipboardData?.items ?? [])
  const imageFiles = items.filter((i) => i.type.startsWith('image/')).map((i) => i.getAsFile())
  if (!imageFiles.length) return // ako nema slike, pusti normalni paste teksta
  e.preventDefault()
  if (!online.value) return // prilozi traže mrežu
  addPending(imageFiles)
}
function onDrop(e) {
  isDragging.value = false
  if (!online.value) return // prilozi traže mrežu
  const files = Array.from(e.dataTransfer?.files ?? []).filter((f) => f.type.startsWith('image/'))
  addPending(files)
}

function triggerFilePicker() {
  fileInput.value?.click()
}

function onFileSelected(e) {
  addPending(Array.from(e.target.files ?? []))
  if (fileInput.value) fileInput.value.value = ''
}

function addPending(files) {
  const room = MAX_PENDING_IMAGES - pendingImages.value.length
  if (room <= 0) return
  const images = files.filter((f) => f?.type?.startsWith('image/')).slice(0, room)
  if (!images.length) return
  pendingImages.value = [...pendingImages.value, ...images]
}

function removePending(index) {
  pendingImages.value = pendingImages.value.filter((_, i) => i !== index)
}

// Napuštanje chata s pripremljenim slikama (promjena kanala, zatvaranje threada)
// inače ostavi objectURL-ove neopozvane — watch(pendingImages) revoke-a stare
// tek pri SLJEDEĆOJ promjeni, ne pri unmountu.
onUnmounted(() => {
  for (const url of previews.value) URL.revokeObjectURL(url)
})

async function send() {
  if (!canSend.value || sending.value) return
  sending.value = true

  // Prije slanja: poruka aktivira DB okidač auto_follow_on_message koji upiše
  // pretplatu ako je nema. Provjera mora ići PRIJE slanja da uhvati prijelaz
  // (nakon slanja bi redak već postojao i izgledalo bi kao da je oduvijek).
  const wasFollowing = projectsStore.isFollowing(props.projectId)

  const initialImageCount = pendingImages.value.length
  let uploadedCount = 0
  // Flag isključen mid-session ne smije poslati stariju true vrijednost koju
  // korisnik više ni ne vidi na ekranu.
  const flag = disappearingMessagesEnabled.value && destroyAfterRead.value

  try {
    if (initialImageCount > 0) {
      // Jedan attachment po retku u messages (invarijanta #4) — svaka slika
      // ide kao zasebna poruka. Uvijek se uzima pendingImages[0] i briše tek
      // NAKON uspješnog slanja: ako nešto usred niza padne, queue pamti točno
      // što je ostalo za retry umjesto da se već poslano ponovi.
      let isFirst = true
      while (pendingImages.value.length > 0) {
        const file = pendingImages.value[0]
        const uploaded = await uploadImage(file, {
          maxWidth: 1440,
          quality: 0.65,
          pathPrefix: props.projectId,
        })
        uploadedCount++
        await chatStore.sendMessage({
          projectId: props.projectId,
          itemId: props.itemId,
          channel: props.channel,
          body: isFirst ? body.value.trim() : '',
          attachmentUrl: uploaded.path,
          attachmentType: uploaded.type,
          attachmentName: uploaded.name,
          replyToId: isFirst ? (props.replyTo?.id ?? null) : null,
          destroyAfterRead: flag,
        })
        if (isFirst) {
          // Titl/reply su potrošeni uz prvu — retry poslije eventualnog pada
          // na drugoj slici ih ne smije ponoviti.
          body.value = ''
          if (props.replyTo) emit('cancel-reply')
          isFirst = false
        }
        removePending(0)
      }
    } else {
      await chatStore.sendMessage({
        projectId: props.projectId,
        itemId: props.itemId,
        channel: props.channel,
        body: body.value.trim(),
        attachmentUrl: null,
        attachmentType: null,
        attachmentName: null,
        replyToId: props.replyTo?.id ?? null,
        destroyAfterRead: flag,
      })
      body.value = ''
      if (props.replyTo) emit('cancel-reply')
    }

    destroyAfterRead.value = false

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
                $q.notify({ type: 'negative', message: dbErrorMessage(e, t) })
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
      initialImageCount > 0 && uploadedCount < initialImageCount
        ? t('chat.attachmentFail')
        : (dbErrorMessage(err, t) || t('chat.sendFailed'))
    $q.notify({ type: 'negative', message })
  } finally {
    sending.value = false
  }
}
</script>

<style scoped>
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

/* Drop zona je dosad bila bez ijednog pravila: div se srušio na nultu visinu,
   pa se pri povlačenju slike nije imalo što vidjeti ni na što ispustiti. */
.drop-zone {
  min-height: 96px;
  margin-bottom: 8px;
  border: 2px dashed var(--q-primary, #1976d2);
  border-radius: 8px;
  background: rgba(25, 118, 210, 0.06);
}

.preview-item {
  position: relative;
  flex-shrink: 0;
}

.preview-thumb {
  max-width: 64px;
  max-height: 64px;
  width: auto;
  height: auto;
  object-fit: contain;
  border-radius: 6px;
  border: 1px solid rgba(0, 0, 0, 0.08);
  display: block;
}

.preview-remove {
  position: absolute;
  top: -8px;
  right: -8px;
  background: rgba(0, 0, 0, 0.6);
  color: white;
}
</style>
