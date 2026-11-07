// Translation markers: Tensaku's I18n backend appends an invisible marker with the locale and key to
// every translated string in development. Here they're stripped as soon as they reach the DOM, and
// remembered: which text node and which attribute came from which key.
//
// Format: U+2063, then "locale:key" as UTF-8 bytes in base 4 written with four zero-width characters,
// then U+2063. See lib/tensaku/i18n.rb.

export interface TranslationKey {
  locale: string
  key: string
}

const FENCE = "⁣"
const DIGITS = ["​", "‌", "‍", "⁠"]
const PATTERN = /⁣[​‌‍⁠]+⁣/g

const nodeKeys = new WeakMap<Text, TranslationKey[]>()
const attributeKeys = new WeakMap<Element, Map<string, TranslationKey>>()

function decode(marker: string): TranslationKey | null {
  const digits = [...marker.slice(1, -1)].map((char) => DIGITS.indexOf(char))
  if (digits.length % 4 !== 0 || digits.includes(-1)) return null
  const bytes = new Uint8Array(digits.length / 4)
  for (let i = 0; i < bytes.length; i++) {
    const [a, b, c, d] = digits.slice(i * 4, i * 4 + 4)
    bytes[i] = (a << 6) | (b << 4) | (c << 2) | d
  }
  const text = new TextDecoder().decode(bytes)
  const colon = text.indexOf(":")
  return colon > 0 ? { locale: text.slice(0, colon), key: text.slice(colon + 1) } : null
}

function extract(text: string): { text: string; keys: TranslationKey[] } {
  const keys: TranslationKey[] = []
  const stripped = text.replace(PATTERN, (marker) => {
    const key = decode(marker)
    if (key) keys.push(key)
    return ""
  })
  return { text: stripped, keys }
}

function stripText(node: Text) {
  if (!node.data.includes(FENCE)) return
  const { text, keys } = extract(node.data)
  node.data = text
  if (keys.length) nodeKeys.set(node, [...(nodeKeys.get(node) ?? []), ...keys])
}

function stripAttributes(element: Element) {
  for (const attribute of Array.from(element.attributes)) {
    if (!attribute.value.includes(FENCE)) continue
    const { text, keys } = extract(attribute.value)
    element.setAttribute(attribute.name, text)
    if (keys.length) {
      const map = attributeKeys.get(element) ?? new Map()
      map.set(attribute.name, keys[keys.length - 1])
      attributeKeys.set(element, map)
    }
  }
  if (element instanceof HTMLTextAreaElement && element.value.includes(FENCE)) element.value = extract(element.value).text
}

export function strip(root: Node) {
  if (root.nodeType === Node.TEXT_NODE) return stripText(root as Text)
  if (!(root instanceof Element || root instanceof Document || root instanceof DocumentFragment)) return
  if (root instanceof Element) stripAttributes(root)
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.nodeType === Node.TEXT_NODE) stripText(node as Text)
    else stripAttributes(node as Element)
  }
}

export function watch() {
  strip(document.documentElement)
  if (document.title.includes(FENCE)) document.title = extract(document.title).text
  new MutationObserver((records) => {
    for (const record of records) {
      if (record.type === "characterData") stripText(record.target as Text)
      else if (record.type === "attributes") stripAttributes(record.target as Element)
      else record.addedNodes.forEach((node) => strip(node))
    }
  }).observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true })
}

// Keys whose text sits directly inside this element (not inside a child element with its own stamp).
export function textKeys(element: Element): { node: Text; key: TranslationKey }[] {
  const found: { node: Text; key: TranslationKey }[] = []
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT)
  for (let node = walker.nextNode() as Text | null; node; node = walker.nextNode() as Text | null) {
    const keys = nodeKeys.get(node)
    if (!keys) continue
    const owner = node.parentElement?.closest("[data-herb-source], [data-tensaku-md]")
    if (owner && owner !== element && element.contains(owner)) continue
    keys.forEach((key) => found.push({ node, key }))
  }
  return found
}

export function attributeKey(element: Element, name: string): TranslationKey | undefined {
  return attributeKeys.get(element)?.get(name)
}

export function attributeKeyNames(element: Element): string[] {
  return Array.from(attributeKeys.get(element)?.keys() ?? [])
}

// Every text node on the page that came from this key, for updating the page right after a save.
export function nodesForKey(key: TranslationKey): Text[] {
  const nodes: Text[] = []
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
  for (let node = walker.nextNode() as Text | null; node; node = walker.nextNode() as Text | null) {
    if (nodeKeys.get(node)?.some((k) => k.key === key.key && k.locale === key.locale)) nodes.push(node)
  }
  return nodes
}

export function elementsWithAttributeKey(key: TranslationKey): { element: Element; name: string }[] {
  const found: { element: Element; name: string }[] = []
  document.querySelectorAll("*").forEach((element) => {
    attributeKeys.get(element)?.forEach((k, name) => {
      if (k.key === key.key && k.locale === key.locale) found.push({ element, name })
    })
  })
  return found
}
