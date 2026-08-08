<template>
  <!-- Registar: svi bugovi, sve faze. Prihvaćeni su usporedno i na TBI ploči —
       ista stavka, dva pogleda (docs/item-model.md). -->
  <ItemListPanel
    :project-id="projectId"
    :items="itemsStore.bugs(projectId)"
    kind="bug"
    group="bugs"
    :title="$t('bugs.title')"
    :new-label="$t('bugs.new')"
    :empty-text="$t('bugs.noBugs')"
  />
</template>

<script setup>
import { onMounted } from 'vue'
import { useItemsStore } from 'src/stores/items'
import ItemListPanel from 'src/components/shared/ItemListPanel.vue'

const props = defineProps({ projectId: String })
const itemsStore = useItemsStore()

onMounted(async () => {
  await itemsStore.fetchItems(props.projectId)
})
</script>
