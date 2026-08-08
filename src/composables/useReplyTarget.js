import { ref } from 'vue'

export function useReplyTarget() {
  const replyTarget = ref(null)

  function setReply(message) {
    replyTarget.value = message
  }

  function clearReply() {
    replyTarget.value = null
  }

  return { replyTarget, setReply, clearReply }
}
