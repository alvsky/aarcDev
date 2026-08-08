import { supabase } from 'src/boot/supabase'
import { removeCachedImage } from 'src/utils/imageCache'

// Kad se screenshot stavke zamijeni novim, stari objekt u storageu više nitko ne
// referencira (put je jedinstven po uploadu) pa bi inače ostao zauvijek. Zove se
// tek nakon uspješnog UPDATE-a; neuspjeh brisanja ne smije srušiti spremanje.
export async function discardReplacedScreenshot(oldPath, newPath) {
  if (!oldPath || !newPath || oldPath === newPath) return
  try {
    await supabase.storage.from('chat-attachments').remove([oldPath])
    await removeCachedImage(oldPath)
  } catch (e) {
    console.warn('screenshot cleanup error:', e)
  }
}
