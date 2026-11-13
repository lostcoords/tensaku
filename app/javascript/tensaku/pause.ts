// Pausing stops the page's CSS animations and transitions, Web Animations and playing media, so an
// element can be noted mid-animation. Timers and requestAnimationFrame loops keep running.

import { isUi } from "./dom"

let paused: { animations: Animation[]; media: HTMLMediaElement[]; style: HTMLStyleElement } | null = null

// Pauses the page, or resumes what was paused. Returns whether the page is paused now.
export function togglePause(): boolean {
  if (paused) {
    paused.style.remove()
    paused.animations.forEach((animation) => { try { animation.play() } catch { /* finished or removed meanwhile */ } })
    paused.media.forEach((media) => media.play().catch(() => {}))
    paused = null
    return false
  }
  const animations = document.getAnimations().filter((animation) => {
    const target = (animation.effect as KeyframeEffect | null)?.target
    return animation.playState === "running" && !(target && isUi(target))
  })
  animations.forEach((animation) => animation.pause())
  const media = Array.from(document.querySelectorAll<HTMLMediaElement>("video, audio")).filter((element) => !element.paused)
  media.forEach((element) => element.pause())
  const style = document.createElement("style")
  style.setAttribute("data-tensaku-pause", "")
  style.textContent = "*, *::before, *::after { animation-play-state: paused !important; transition: none !important; }"
  document.head.append(style)
  paused = { animations, media, style }
  return true
}
