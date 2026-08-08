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
        :idea-id="ideaId"
        :bug-id="bugId"
        :tbi-id="tbiId"
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
  ideaId: { type: String, default: null },
  bugId: { type: String, default: null },
  tbiId: { type: String, default: null },
  // TBI thread spaja poruke izvorne ideje/buga s vlastitima pa smije nametnuti svoj
  // popis; ostali ga ne šalju i panel sam čita thread iz storea.
  messages: { type: Array, default: null },
})

defineEmits(['scrolled-to-bottom'])

const chatStore = useChatStore()
const { replyTarget, setReply, clearReply } = useReplyTarget()
const listRef = ref(null)

const threadIds = computed(() => ({
  projectId: props.projectId,
  channel: props.channel,
  ideaId: props.ideaId,
  bugId: props.bugId,
  tbiId: props.tbiId,
}))

const shownMessages = computed(() =>
  props.messages ? props.messages : chatStore.threadMessages(chatStore.threadKey(threadIds.value)),
)

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
