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

// The maps above are keyed by node, and Turbo's Back/Forward shows a cloned snapshot of the page, whose
// nodes are new and already stripped. So each element also carries its keys in an attribute, which
// cloning copies, and restore() reads them back into the maps.
// TEXT_KEYS: JSON [[index among the element's text nodes, locale, key], ...]
// ATTRIBUTE_KEYS: JSON [[attribute name, locale, key], ...]
const TEXT_KEYS = "data-tensaku-t"
const ATTRIBUTE_KEYS = "data-tensaku-a"

const textNodesOf = (element: Element) => Array.from(element.childNodes).filter((node): node is Text => node.nodeType === Node.TEXT_NODE)

function recordText(node: Text) {
  const parent = node.parentElement
  if (!parent) return
  const entries: [number, string, string][] = []
  textNodesOf(parent).forEach((text, index) => nodeKeys.get(text)?.forEach((key) => entries.push([index, key.locale, key.key])))
  writeRecord(parent, TEXT_KEYS, entries)
}

function recordAttributes(element: Element) {
  const entries: [string, string, string][] = Array.from(attributeKeys.get(element) ?? []).map(([name, key]) => [name, key.locale, key.key])
  writeRecord(element, ATTRIBUTE_KEYS, entries)
}

function writeRecord(element: Element, name: string, entries: unknown[]) {
  const value = JSON.stringify(entries)
  if (entries.length && element.getAttribute(name) !== value) element.setAttribute(name, value)
}

function readRecord<T>(element: Element, name: string): T[] {
  try {
    const value = JSON.parse(element.getAttribute(name) ?? "[]")
    return Array.isArray(value) ? value : []
  } catch {
    return []
  }
}

// Fills the maps for nodes that have a record but no entry, after Turbo renders a cached snapshot.
export function restore(root: ParentNode = document) {
  root.querySelectorAll(`[${TEXT_KEYS}]`).forEach((element) => {
    const texts = textNodesOf(element)
    for (const [index, locale, key] of readRecord<[number, string, string]>(element, TEXT_KEYS)) {
      const node = texts[index]
      if (!node || nodeKeys.get(node)?.some((k) => k.key === key && k.locale === locale)) continue
      nodeKeys.set(node, [...(nodeKeys.get(node) ?? []), { locale, key }])
    }
  })
  root.querySelectorAll(`[${ATTRIBUTE_KEYS}]`).forEach((element) => {
    const map = attributeKeys.get(element) ?? new Map<string, TranslationKey>()
    for (const [name, locale, key] of readRecord<[string, string, string]>(element, ATTRIBUTE_KEYS)) {
      if (!map.has(name)) map.set(name, { locale, key })
    }
    if (map.size) attributeKeys.set(element, map)
  })
}

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
  if (keys.length) {
    const known = nodeKeys.get(node) ?? []
    nodeKeys.set(node, [...known, ...keys.filter((key) => !known.some((k) => k.key === key.key && k.locale === key.locale))])
    recordText(node)
  }
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
      recordAttributes(element)
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
  document.addEventListener("turbo:render", () => restore())
  document.addEventListener("turbo:frame-render", () => restore())
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
    const owner = node.parentElement?.closest("[data-herb-source], [data-md-source]")
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
