"use client"

import { createContext, useContext, useEffect, useState } from "react"
import { apiFetch } from "@/lib/api"

export type Notification = { id: string; kind: string; status: "read" | "unread"; message: string; created_at: string; resolved_at: string | null }
type Response = { data: Notification[]; unread_count: number }
type Feed = { result: Response | null; loading: boolean; error: string; pending: string; lastUpdated: Date | null; connected: boolean; refresh: () => void; markRead: (id: string) => Promise<void> }

const NotificationContext = createContext<Feed | null>(null)

export function useNotificationFeed() {
  const feed = useContext(NotificationContext)
  if (!feed) throw new Error("Thiếu nguồn thông báo quản trị")
  return feed
}

export function NotificationFeedProvider({ children }: { children: React.ReactNode }) {
  const [result, setResult] = useState<Response | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [pending, setPending] = useState("")
  const [reload, setReload] = useState(0)
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null)
  const [connected, setConnected] = useState(true)

  useEffect(() => {
    const controller = new AbortController()
    let timer: ReturnType<typeof setTimeout> | undefined
    let failures = 0
    let running = false

    function schedule(delay: number) {
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => void load(), delay)
    }

    async function load() {
      if (running || controller.signal.aborted || document.hidden || !navigator.onLine) return
      running = true
      setError("")
      try {
        const response = await apiFetch<Response>("/api/notifications", { signal: controller.signal })
        if (!controller.signal.aborted) {
          setResult(response)
          setLastUpdated(new Date())
          setConnected(true)
          failures = 0
        }
      } catch (caught) {
        if (!controller.signal.aborted) {
          setError(caught instanceof Error ? caught.message : "Không tải được thông báo.")
          setConnected(false)
          failures++
        }
      } finally {
        running = false
        if (!controller.signal.aborted) {
          setLoading(false)
          if (navigator.onLine && !document.hidden) schedule(failures ? Math.min(60000, 5000 * 2 ** (failures - 1)) : 10000)
        }
      }
    }

    function resume() {
      if (!navigator.onLine) {
        setConnected(false)
        if (timer) clearTimeout(timer)
        return
      }
      if (!document.hidden && !running) schedule(0)
    }

    void load()
    window.addEventListener("online", resume)
    window.addEventListener("offline", resume)
    document.addEventListener("visibilitychange", resume)
    return () => {
      controller.abort()
      if (timer) clearTimeout(timer)
      window.removeEventListener("online", resume)
      window.removeEventListener("offline", resume)
      document.removeEventListener("visibilitychange", resume)
    }
  }, [reload])

  async function markRead(id: string) {
    if (pending) return
    setPending(id)
    setError("")
    try {
      await apiFetch(`/api/notifications/${id}/read`, { method: "PATCH" })
      setReload((value) => value + 1)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Không đánh dấu đã đọc được.")
    } finally { setPending("") }
  }

  return <NotificationContext.Provider value={{ result, loading, error, pending, lastUpdated, connected, refresh: () => setReload((value) => value + 1), markRead }}>
    {children}
  </NotificationContext.Provider>
}
