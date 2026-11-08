// Talks to Tensaku's endpoints. The token and the request method come from the meta tag the
// middleware writes into every HTML page, read fresh each time because Turbo swaps the head.

interface PageMeta {
  token: string
  root: string
  method: string
  shortcut: string
}

export function meta(): PageMeta {
  const tag = document.querySelector<HTMLMetaElement>('meta[name="tensaku"]')
  return {
    token: tag?.dataset.tensakuToken ?? "",
    root: tag?.dataset.tensakuRoot ?? "/__tensaku",
    method: tag?.dataset.tensakuRequest ?? "GET",
    shortcut: tag?.dataset.tensakuShortcut ?? "alt+shift+KeyT",
  }
}

export class ApiError extends Error {
  constructor(message: string, readonly status: number, readonly stale: boolean) {
    super(message)
  }
}

export async function api<T = any>(method: string, path: string, body?: unknown): Promise<T> {
  const { token, root } = meta()
  const response = await fetch(root + path, {
    method,
    headers: { "Content-Type": "application/json", "X-Tensaku-Token": token, Accept: "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
  })
  const type = response.headers.get("content-type") ?? ""
  const data = type.includes("json") ? await response.json() : await response.text()
  if (!response.ok) {
    const message = typeof data === "object" && data?.error ? data.error : `Tensaku request failed (${response.status})`
    throw new ApiError(message, response.status, Boolean(data?.stale))
  }
  return data as T
}

export const query = (params: Record<string, string | undefined>) =>
  "?" + new URLSearchParams(Object.entries(params).filter((entry): entry is [string, string] => entry[1] !== undefined)).toString()

export const isApple = /mac|iphone|ipad|ipod/i.test(navigator.platform || navigator.userAgent)
