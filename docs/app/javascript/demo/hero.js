// The heading fixes itself once per page load: a fake mouse clicks "editor.", backspaces it and types
// "browser.", the word the page really says, and the source excerpt follows along. The overlay, the
// "try it" button or an alt key ends it at once, so Tensaku only ever edits the real text. Other
// clicks, taps and scrolling leave it playing.

const FIXED = "browser."
const WRONG = "editor."
const ARROW = '<svg class="hero-cursor__arrow" viewBox="0 0 24 24"><path d="M3 2 L3 19 L8 14.5 L11.5 22 L15 20.5 L11.5 13 L18 13 Z"/></svg>'
const BEAM = '<svg class="hero-cursor__beam" viewBox="0 0 24 24"><path d="M8 3 C10 3 12 4 12 6 L12 18 C12 20 10 21 8 21 M16 3 C14 3 12 4 12 6 M12 18 C12 20 14 21 16 21"/></svg>'

// The excerpt's text node holding the heading's words, once the excerpt has been highlighted.
function excerptWords(words) {
  const code = document.querySelector("[data-demo-source-code]")
  if (!code) return null
  const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT)
  while (walker.nextNode()) if (walker.currentNode.data === words) return walker.currentNode
  return null
}

export function playHero() {
  const root = document.documentElement
  const mark = document.querySelector(".hero__title .pen-mark")
  const text = mark?.firstChild
  const stopAnimating = () => root.classList.remove("hero-anim", "hero-anim--playing")
  const visible = mark && mark.getBoundingClientRect().top < innerHeight && mark.getBoundingClientRect().bottom > 0
  // A heading someone has already edited stays as it is.
  if (!root.classList.contains("hero-anim") || !visible || text?.nodeType !== Node.TEXT_NODE || !text.data.endsWith(FIXED)) return stopAnimating()

  const final = text.data
  const prefix = final.slice(0, -FIXED.length)
  const source = excerptWords(final)
  const sourceLine = source?.parentElement.closest(".demo-code__line")
  const setWords = (words) => {
    text.data = words
    if (source) source.data = words
  }
  const layer = Object.assign(document.createElement("div"), { className: "hero-layer" })
  layer.setAttribute("aria-hidden", "true")
  layer.setAttribute("data-tensaku-ui", "")
  const cursor = Object.assign(document.createElement("div"), { className: "hero-cursor", innerHTML: ARROW + BEAM })
  layer.append(cursor)
  document.body.append(layer)
  const caret = Object.assign(document.createElement("span"), { className: "hero-caret" })
  caret.setAttribute("aria-hidden", "true")

  let stopped = false
  const interrupts = (event) => event.altKey || event.target.closest?.("tensaku-overlay, [data-demo-try]")
  const stopOn = (event) => { if (interrupts(event)) stop() }
  const stop = () => {
    if (stopped) return
    stopped = true
    removeEventListener("pointerdown", stopOn, true)
    removeEventListener("keydown", stopOn, true)
    setWords(final)
    sourceLine?.classList.remove("demo-code__line--changed")
    caret.remove()
    layer.remove()
    mark.classList.remove("pen-mark--editing")
    stopAnimating()
  }
  addEventListener("pointerdown", stopOn, true)
  addEventListener("keydown", stopOn, true)

  const wait = (ms) => new Promise((resolve, reject) => setTimeout(() => (stopped ? reject() : resolve()), ms))
  // Kept inside the page's width: on a phone, a cursor past the right edge would widen the page.
  const moveTo = (x, y) => {
    const maxX = root.clientWidth - cursor.offsetWidth - 4
    cursor.style.transform = `translate(${Math.min(x, maxX)}px, ${y}px)`
  }
  const wordBox = () => {
    const range = document.createRange()
    range.setStart(text, prefix.length)
    range.setEnd(text, text.data.length)
    const box = range.getBoundingClientRect()
    return { left: box.left + scrollX, right: box.right + scrollX, top: box.top + scrollY, bottom: box.bottom + scrollY, middle: box.top + scrollY + box.height / 2 }
  }
  const keystroke = async (ms) => {
    caret.classList.add("hero-caret--typing")
    await wait(ms)
  }

  const play = async () => {
    setWords(prefix + WRONG)
    let first = wordBox()
    cursor.style.transition = "none"
    moveTo(first.right + 180, first.bottom + 160)
    cursor.getBoundingClientRect()
    cursor.style.transition = ""
    root.classList.add("hero-anim--playing")
    await wait(700)

    // To the end of the word, where the arrow turns into a text cursor. Measured again here, since
    // the heading has finished rising into place by now.
    first = wordBox()
    moveTo(first.right - 4, first.middle)
    await wait(600)
    cursor.classList.add("hero-cursor--text")
    await wait(350)

    // The click.
    cursor.classList.add("hero-cursor--down")
    const ripple = Object.assign(document.createElement("div"), { className: "hero-click" })
    Object.assign(ripple.style, { left: `${first.right - 4}px`, top: `${first.middle}px` })
    layer.append(ripple)
    await wait(110)
    cursor.classList.remove("hero-cursor--down")
    mark.classList.add("pen-mark--editing")
    sourceLine?.classList.add("demo-code__line--changed")
    text.after(caret)
    await wait(350)
    moveTo(first.right + 50, first.bottom + 40)
    await wait(750)

    for (let length = WRONG.length - 1; length >= 0; length--) {
      await keystroke(95)
      setWords(prefix + WRONG.slice(0, length))
    }
    await wait(350)
    for (let length = 1; length <= FIXED.length; length++) {
      await keystroke(70 + Math.random() * 80)
      setWords(prefix + FIXED.slice(0, length))
    }
    caret.classList.remove("hero-caret--typing")
    await wait(500)

    // Enter: the edit box closes and the underline draws.
    caret.remove()
    mark.classList.remove("pen-mark--editing")
    root.classList.remove("hero-anim")
    const last = wordBox()
    const saved = Object.assign(document.createElement("div"), { className: "hero-saved", textContent: "✓ saved" })
    Object.assign(saved.style, { left: `${last.right + mark.offsetHeight / 3}px`, top: `${last.top}px` })
    layer.append(saved)
    cursor.style.opacity = "0"
    moveTo(last.right + 120, last.bottom + 120)
    await wait(1900)
  }

  play().catch(() => {}).finally(stop)
}
