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
          clearable
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

        <!-- Prioritet vrijedi za sve vrste, ne samo bugove (docs/item-model.md).
             Faza se ne mijenja ovdje nego inline na kartici, jer prijelazi moraju
             popuniti accepted_by/rejected_by stupce. -->
        <q-select
          v-model="form.priority"
          :label="$t('common.priority')"
          outlined
          dense
          :options="priorityOptions"
          emit-value
          map-options
        />

        <!-- N1: samo za bugove — unaprijed popunjeno stvarnom platformom -->
        <q-select
          v-if="kind === 'bug'"
          v-model="form.platform"
          :label="$t('bugs.platform')"
          outlined
          dense
          :options="platformOptions"
          emit-value
          map-options
        />
      </q-card-section>

      <q-card-actions align="right">
        <q-btn flat :label="$t('common.cancel')" v-close-popup />
        <q-btn
          :color="kind === 'bug' ? 'negative' : 'primary'"
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
import { Capacitor } from '@capacitor/core'
import { useImageUpload } from 'src/composables/useImageUpload'
import { useItemsStore } from 'src/stores/items'
import ScreenshotUpload from './ScreenshotUpload.vue'

const props = defineProps({
  modelValue: { type: Boolean, required: true },
  kind: { type: String, required: true }, // 'idea' | 'bug' | 'task'
  item: { type: Object, default: null },
  projectId: { type: String, required: true },
})
const emit = defineEmits(['update:modelValue'])

const $q = useQuasar()
const { t } = useI18n()
const itemsStore = useItemsStore()
const { uploadImage } = useImageUpload()

const saving = ref(false)
const pendingImage = ref(null)

const open = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v),
})

const form = ref({ title: '', description: '', priority: 'med', platform: null })

// Web vraća 'web' — poklapa se s CHECK vrijednostima na items.platform, pa
// nema posebnog slučaja za taj otvor.
const detectedPlatform = Capacitor.getPlatform()

// Reset forme pri otvaranju
watch(
  () => props.modelValue,
  (val) => {
    if (val) {
      // Uvijek, i pri uređivanju: inače bi slika odabrana u prošlom otvaranju
      // dijaloga ostala visjeti i bila uploadana na sljedeću stavku.
      pendingImage.value = null
      form.value = {
        title: props.item?.title ?? '',
        description: props.item?.description ?? '',
        priority: props.item?.priority ?? 'med',
        // Pri uređivanju zadrži postojeću vrijednost; pri stvaranju novog
        // buga unaprijed popuni stvarnom platformom (korisnik može promijeniti).
        platform: props.item?.id ? (props.item?.platform ?? null) : detectedPlatform,
      }
    }
  },
)

const dialogTitle = computed(() => {
  if (props.item?.id) return t('common.edit')
  return { idea: t('ideas.new'), bug: t('bugs.new'), task: t('tbi.new') }[props.kind]
})

const priorityOptions = computed(() =>
  ['low', 'med', 'high'].map((p) => ({ label: t(`bugs.priority.${p}`), value: p })),
)

const platformOptions = computed(() =>
  ['ios', 'android', 'web'].map((p) => ({ label: t(`bugs.platformName.${p}`), value: p })),
)

// Upload screenshot ako postoji. Vraća isti podatak u dva oblika: `create` prati
// potpise create akcija (camelCase), `update` ide ravno u supabase .update() pa mora
// koristiti nazive stupaca. Ako slike nema, oba su prazna i postojeća se ne dira.
async function uploadScreenshot() {
  if (!pendingImage.value) return { create: {}, update: {} }
  const uploaded = await uploadImage(pendingImage.value, {
    maxWidth: 1280,
    quality: 0.6,
    pathPrefix: props.projectId,
  })
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

    // platform vrijedi samo za bugove — ostale vrste ga jednostavno nemaju.
    const platform = props.kind === 'bug' ? form.value.platform : null

    // Jedna putanja za sve vrste — prije tri gotovo iste grane.
    if (props.item?.id) {
      await itemsStore.updateItem(props.item.id, {
        title: form.value.title,
        description: form.value.description,
        priority: form.value.priority,
        platform,
        ...screenshot.update,
      })
    } else {
      await itemsStore.createItem({
        projectId: props.projectId,
        kind: props.kind,
        title: form.value.title,
        description: form.value.description,
        priority: form.value.priority,
        platform,
        ...screenshot.create,
      })
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
