<template>
  <q-dialog v-model="open" persistent>
    <q-card style="min-width: 340px; width: 90vw; max-width: 500px">
      <q-card-section class="row items-center">
        <div class="text-h6">{{ dialogTitle }}</div>
        <q-space />
        <q-btn flat round dense icon="close" v-close-popup />
      </q-card-section>

      <q-separator />

      <q-card-section class="q-gutter-sm">
        <!-- Naslov -->
        <q-input
          v-model="form.title"
          :label="$t('common.title')"
          outlined
          dense
          autofocus
          :rules="[(v) => !!v || $t('common.required')]"
        />

        <!-- Opis -->
        <q-field :label="$t('common.description')" outlined stack-label style="min-height: 160px">
          <template #control>
            <textarea
              v-model="form.description"
              class="q-field__native full-width"
              style="
                min-height: 140px;
                resize: vertical;
                padding: 8px 0;
                line-height: 1.5;
                font-size: 14px;
                font-family: inherit;
                border: none;
                outline: none;
                background: transparent;
              "
              :placeholder="$t('common.description')"
            />
          </template>
        </q-field>

        <!-- Screenshot -->
        <ScreenshotUpload v-model="pendingImage" />

        <!-- Priority — bug i tbi -->
        <q-select
          v-if="type !== 'idea'"
          v-model="form.priority"
          :label="$t('common.priority')"
          outlined
          dense
          :options="priorityOptions"
          emit-value
          map-options
        />

        <!-- Status — samo edit mode. Bug status se mijenja inline na kartici. -->
        <q-select
          v-if="item?.id && type === 'tbi'"
          v-model="form.status"
          :label="$t('common.status')"
          outlined
          dense
          :options="statusOptions"
          emit-value
          map-options
        />
      </q-card-section>

      <q-card-actions align="right">
        <q-btn flat :label="$t('common.cancel')" v-close-popup />
        <q-btn
          :color="type === 'bug' ? 'negative' : 'primary'"
          :label="$t('common.save')"
          :loading="saving"
          @click="save"
        />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { useQuasar } from 'quasar'
import { useI18n } from 'vue-i18n'
import { useImageUpload } from 'src/composables/useImageUpload'
import { useIdeasStore } from 'src/stores/ideas'
import { useBugsStore } from 'src/stores/bugs'
import { useTbiStore } from 'src/stores/tbi'
import ScreenshotUpload from './ScreenshotUpload.vue'

const props = defineProps({
  modelValue: { type: Boolean, required: true },
  type: { type: String, required: true }, // 'idea' | 'bug' | 'tbi'
  item: { type: Object, default: null },
  projectId: { type: String, required: true },
})
const emit = defineEmits(['update:modelValue'])

const $q = useQuasar()
const { t } = useI18n()
const ideasStore = useIdeasStore()
const bugsStore = useBugsStore()
const tbiStore = useTbiStore()
const { uploadImage } = useImageUpload()

const saving = ref(false)
const pendingImage = ref(null)

const open = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v),
})

// Default form po tipu
const defaultForm = () => {
  if (props.type === 'idea') return { title: '', description: '' }
  if (props.type === 'bug') return { title: '', description: '', priority: 'med', status: 'open' }
  if (props.type === 'tbi') return { title: '', description: '', priority: 'med', status: 'tbi' }
  return { title: '', description: '' }
}

const form = ref(defaultForm())

// Reset forme pri otvaranju
watch(
  () => props.modelValue,
  (val) => {
    if (val) {
      // Uvijek, i pri uređivanju: inače bi slika odabrana u prošlom otvaranju
      // dijaloga ostala visjeti i bila uploadana na sljedeću stavku.
      pendingImage.value = null
      if (props.item) {
        form.value = {
          title: props.item.title ?? '',
          description: props.item.description ?? '',
          priority: props.item.priority ?? 'med',
          status: props.item.status ?? (props.type === 'bug' ? 'open' : 'tbi'),
        }
      } else {
        form.value = {
          title: '',
          description: '',
          priority: 'med',
          status: props.type === 'bug' ? 'open' : 'tbi',
        }
      }
    }
  },
)

// Dinamičan naslov
const dialogTitle = computed(() => {
  if (props.item?.id) return t('common.edit')
  if (props.type === 'idea') return t('ideas.new')
  if (props.type === 'bug') return t('bugs.new')
  if (props.type === 'tbi') return t('tbi.new')
  return t('common.edit')
})

// Priority opcije
const priorityOptions = computed(() => {
  const ns = props.type === 'bug' ? 'bugs' : 'tbi'
  return [
    { label: t(`${ns}.priority.low`), value: 'low' },
    { label: t(`${ns}.priority.med`), value: 'med' },
    { label: t(`${ns}.priority.high`), value: 'high' },
  ]
})

// Status opcije po tipu
const statusOptions = computed(() => {
  if (props.type === 'bug') {
    return [
      { label: t('bugs.status.open'), value: 'open' },
      { label: t('bugs.status.in_progress'), value: 'in_progress' },
      { label: t('bugs.status.testing'), value: 'testing' },
      { label: t('bugs.status.closed'), value: 'closed' },
    ]
  }
  if (props.type === 'tbi') {
    return [
      { label: t('tbi.status.tbi'), value: 'tbi' },
      { label: t('tbi.status.in_progress'), value: 'in_progress' },
      { label: t('tbi.status.done'), value: 'done' },
    ]
  }
  return []
})

// Upload screenshot ako postoji. Vraća isti podatak u dva oblika: `create` prati
// potpise create akcija (camelCase), `update` ide ravno u supabase .update() pa mora
// koristiti nazive stupaca. Ako slike nema, oba su prazna i postojeća se ne dira.
async function uploadScreenshot() {
  if (!pendingImage.value) return { create: {}, update: {} }
  const uploaded = await uploadImage(pendingImage.value, { maxWidth: 1280, quality: 0.6 })
  return {
    create: {
      screenshotUrl: uploaded.path,
      screenshotType: uploaded.type,
      screenshotName: uploaded.name,
    },
    update: {
      screenshot_url: uploaded.path,
      screenshot_type: uploaded.type,
      screenshot_name: uploaded.name,
    },
  }
}
async function save() {
  if (!form.value.title.trim()) return
  saving.value = true
  try {
    const screenshot = await uploadScreenshot()

    if (props.type === 'idea') {
      if (props.item?.id) {
        await ideasStore.updateIdea(props.item.id, {
          title: form.value.title,
          description: form.value.description,
          ...screenshot.update,
        })
      } else {
        await ideasStore.createIdea({
          projectId: props.projectId,
          title: form.value.title,
          description: form.value.description,
          ...screenshot.create,
        })
      }
    }

    if (props.type === 'bug') {
      if (props.item?.id) {
        await bugsStore.updateBug(props.item.id, {
          title: form.value.title,
          description: form.value.description,
          priority: form.value.priority,
          ...screenshot.update,
        })
      } else {
        await bugsStore.createBug({
          projectId: props.projectId,
          title: form.value.title,
          description: form.value.description,
          priority: form.value.priority,
          ...screenshot.create,
        })
      }
    }

    if (props.type === 'tbi') {
      if (props.item?.id) {
        await tbiStore.updateItem(props.item.id, {
          title: form.value.title,
          description: form.value.description,
          priority: form.value.priority,
          status: form.value.status,
          ...screenshot.update,
        })
      } else {
        await tbiStore.createItem({
          projectId: props.projectId,
          title: form.value.title,
          description: form.value.description,
          priority: form.value.priority,
          ...screenshot.create,
        })
      }
    }

    open.value = false
    $q.notify({ type: 'positive', message: t('settings.saved') })
  } catch (e) {
    $q.notify({ type: 'negative', message: e.message })
  } finally {
    saving.value = false
  }
}
</script>
