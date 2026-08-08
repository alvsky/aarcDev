<template>
  <!-- Jedini chat u aplikaciji: kanali (ChatPage) i threadovi (ThreadDialog) koriste
       ovaj panel. Lista raste, input je zalijepljen za dno. -->
  <div class="column no-wrap chat-panel">
    <MessageList
      ref="listRef"
      :messages="shownMessages"
      class="col"
      @delete="onDelete"
      @react="(msgId, emoji) => chatStore.toggleReaction(msgId, emoji)"
      @reply="setReply"
      @scrolled-to-bottom="$emit('scrolled-to-bottom')"
    />

    <q-separator />

    <div class="col-auto q-pa-sm">
      <MessageInput
        :project-id="projectId"
        :channel="channel"
        :item-id="itemId"
        :reply-to="replyTarget"
        @cancel-reply="clearReply"
      />
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useChatStore } from 'src/stores/chat'
import { useReplyTarget } from 'src/composables/useReplyTarget'
import MessageList from './MessageList.vue'
import MessageInput from './MessageInput.vue'

const props = defineProps({
  projectId: { type: String, required: true },
  channel: { type: String, default: 'main' },
  itemId: { type: String, default: null },
})

defineEmits(['scrolled-to-bottom'])

const chatStore = useChatStore()
const { replyTarget, setReply, clearReply } = useReplyTarget()
const listRef = ref(null)

const threadIds = computed(() => ({
  projectId: props.projectId,
  channel: props.channel,
  itemId: props.itemId,
}))

// Nema više spajanja dvaju threadova: stavka ima jedan thread, pa panel uvijek
// čita iz storea (prije je TBI morao nametati vlastiti spojeni popis).
const shownMessages = computed(() => chatStore.threadMessages(chatStore.threadKey(threadIds.value)))

function onDelete(id) {
  chatStore.deleteMessage(id, threadIds.value)
}

defineExpose({
  scrollToBottom: (behavior) => listRef.value?.scrollToBottom(behavior),
  clearReply,
})
</script>

<style scoped>
.chat-panel {
  min-height: 0;
  min-width: 0;
}
</style>
