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

        <!-- Koraci za reprodukciju — samo za bugove. Placeholder nagovješta
             format umjesto da ga nameće trima zasebnim poljima (dijalog bi
             bio znatno viši, a prazna polja se ionako preskaču). -->
        <q-field
          v-if="kind === 'bug'"
          :label="$t('bugs.steps')"
          outlined
          stack-label
          style="min-height: 130px"
        >
          <template #control>
            <textarea
              v-model="form.steps"
              class="q-field__native full-width"
              style="
                min-height: 110px;
                resize: vertical;
                padding: 8px 0;
                line-height: 1.5;
                font-size: 14px;
                font-family: inherit;
                border: none;
                outline: none;
                background: transparent;
              "
              :placeholder="$t('bugs.stepsPlaceholder')"
            />
          </template>
        </q-field>

        <!-- Screenshotovi -->
        <ScreenshotUpload
          v-model="pendingImages"
          :existing="existingScreenshots"
          @remove-existing="removeExisting"
        />

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
import { dbErrorMessage } from 'src/utils/dbErrorMessage'
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
const pendingImages = ref([])
// Kopija — uklanjanje ide odmah kroz store (izravno brisanje, ne čeka Spremi),
// pa se popis ovdje mora sam ažurirati da nestali screenshot odmah nestane
// iz dijaloga bez čekanja na sljedeći fetchItems.
const existingScreenshots = ref([])

const open = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v),
})

const form = ref({ title: '', description: '', priority: 'med', platform: null, steps: '' })

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
      pendingImages.value = []
      existingScreenshots.value = props.item?.screenshots ? [...props.item.screenshots] : []
      form.value = {
        title: props.item?.title ?? '',
        description: props.item?.description ?? '',
        priority: props.item?.priority ?? 'med',
        // Pri uređivanju zadrži postojeću vrijednost; pri stvaranju novog
        // buga unaprijed popuni stvarnom platformom (korisnik može promijeniti).
        platform: props.item?.id ? (props.item?.platform ?? null) : detectedPlatform,
        steps: props.item?.steps ?? '',
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

// Uklanjanje postojećeg screenshota ide odmah, ne čeka Spremi — isti obrazac
// kao revokeInvite/removeMember (izravna akcija, ne dio forme).
async function removeExisting(shot) {
  try {
    await itemsStore.removeItemScreenshot(shot)
    existingScreenshots.value = existingScreenshots.value.filter((s) => s.id !== shot.id)
  } catch (e) {
    $q.notify({ type: 'negative', message: dbErrorMessage(e, t) })
  }
}

// Uploada sve tek odabrane slike (nema ih na editu dok se ne dodaju) i vraća
// podatke za addItemScreenshots — poziva se TEK kad stavka ima id (nova
// stavka ga dobije iz createItem, postojeća ga već ima).
async function uploadPendingScreenshots() {
  const uploads = []
  for (const file of pendingImages.value) {
    uploads.push(await uploadImage(file, { maxWidth: 1280, quality: 0.6, pathPrefix: props.projectId }))
  }
  return uploads
}

async function save() {
  if (!form.value.title.trim()) return
  saving.value = true
  try {
    // platform vrijedi samo za bugove — ostale vrste ga jednostavno nemaju.
    const platform = props.kind === 'bug' ? form.value.platform : null
    // Prazan textarea daje '' — u bazu ide null, da "nije upisano" i
    // "upisano pa obrisano" ne budu dvije različite stvari za prikaz.
    const steps = props.kind === 'bug' ? (form.value.steps?.trim() || null) : null

    // Jedna putanja za sve vrste — prije tri gotovo iste grane.
    let itemId = props.item?.id
    if (itemId) {
      await itemsStore.updateItem(itemId, {
        title: form.value.title,
        description: form.value.description,
        priority: form.value.priority,
        platform,
        steps,
      })
    } else {
      itemId = await itemsStore.createItem({
        projectId: props.projectId,
        kind: props.kind,
        title: form.value.title,
        description: form.value.description,
        priority: form.value.priority,
        platform,
        steps,
      })
    }

    const uploaded = await uploadPendingScreenshots()
    await itemsStore.addItemScreenshots(itemId, uploaded)

    open.value = false
    $q.notify({ type: 'positive', message: t('settings.saved') })
  } catch (e) {
    $q.notify({ type: 'negative', message: dbErrorMessage(e, t) })
  } finally {
    saving.value = false
  }
}
</script>
