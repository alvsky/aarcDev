import { ref } from 'vue'
import { supabase } from 'src/boot/supabase'
import { useAuthStore } from 'src/stores/auth'

async function compressImage(file, maxWidth = 1920, quality = 0.8) {
  return new Promise((resolve) => {
    const img = new Image()
    const url = URL.createObjectURL(file)

    img.onload = () => {
      let width = img.width
      let height = img.height

      if (width > maxWidth) {
        height = Math.round((height * maxWidth) / width)
        width = maxWidth
      }

      const canvas = document.createElement('canvas')
      canvas.width = width
      canvas.height = height

      const ctx = canvas.getContext('2d')
      ctx.drawImage(img, 0, 0, width, height)

      URL.revokeObjectURL(url)

      canvas.toBlob(
        (blob) => {
          const compressed = new File([blob], file.name.replace(/\.[^.]+$/, '.jpg'), {
            type: 'image/jpeg',
            lastModified: Date.now(),
          })
          console.log(
            `Kompresija: ${(file.size / 1024).toFixed(0)}KB → ${(compressed.size / 1024).toFixed(0)}KB`,
          )
          resolve(compressed)
        },
        'image/jpeg',
        quality,
      )
    }

    img.onerror = () => {
      URL.revokeObjectURL(url)
      resolve(file) // fallback — vrati original
    }

    img.src = url
  })
}

export function useImageUpload() {
  const uploading = ref(false)
  const error = ref(null)

  // bucket/pathPrefix: B16 — putanja mora nositi projectId da RLS na
  // storage.objects uopće može provjeriti can_access_project (stara putanja
  // ${userId}/${file} to nije dopuštala). Avatari nisu projektni pa nemaju
  // pathPrefix i žive u zasebnom 'avatars' bucketu (vidljivost prati
  // can_see_profile, ne can_access_project).
  async function uploadImage(
    file,
    { maxWidth = 1920, quality = 0.8, bucket = 'chat-attachments', pathPrefix = null } = {},
  ) {
    if (!file || !file.type.startsWith('image/')) {
      throw new Error('Nije slika')
    }

    const auth = useAuthStore()

    uploading.value = true
    error.value = null

    try {
      // Komprimiraj
      const compressed = await compressImage(file, maxWidth, quality)

      const folder = pathPrefix ? `${pathPrefix}/${auth.user.id}` : auth.user.id
      const path = `${folder}/${crypto.randomUUID()}.jpg`

      const { error: uploadError } = await supabase.storage.from(bucket).upload(path, compressed, {
        contentType: 'image/jpeg',
        upsert: false,
      })

      if (uploadError) throw uploadError

      return {
        path,
        type: 'image/jpeg',
        name: compressed.name,
      }
    } catch (e) {
      error.value = e.message
      throw e
    } finally {
      uploading.value = false
    }
  }

  async function getSignedUrl(path, bucket = 'chat-attachments') {
    const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, 3600)
    if (error) {
      console.error('getSignedUrl error:', error)
      return null
    }
    return data.signedUrl
  }

  return { uploading, error, uploadImage, getSignedUrl }
}
