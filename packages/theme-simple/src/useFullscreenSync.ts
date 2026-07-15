import { useSyncExternalStore } from 'react'

function subscribeFullscreen(callback: () => void) {
  document.addEventListener('fullscreenchange', callback)
  return () => document.removeEventListener('fullscreenchange', callback)
}

function getFullscreenSnapshot() {
  return !!document.fullscreenElement
}

export function useFullscreenSync(): boolean {
  return useSyncExternalStore(subscribeFullscreen, getFullscreenSnapshot)
}
