"use client"

import { useEffect, useState } from "react"
import { Bell, Check, RotateCw } from "lucide-react"
import { apiFetch } from "@/lib/api"

type Notification = { id: string; kind: string; status: "read" | "unread"; message: string; created_at: string; resolved_at: string | null }
type Response = { data: Notification[]; unread_count: number }

export function NotificationPanel() {
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

  return <section className="mt-7 rounded-2xl border border-black/8 bg-[#fbfaf5] p-5">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="flex items-center gap-2 text-lg font-semibold"><Bell className="size-5 text-primary" />Thông báo của bạn{result && <span className="rounded-full bg-[#e1e5d3] px-2.5 py-0.5 text-xs text-[#274f3a]">{result.unread_count} chưa đọc</span>}</h2><p className="mt-1 text-sm text-muted-foreground">Chỉ hiện sự cố thuộc chi nhánh bạn còn được phân quyền.</p><p role="status" className={`mt-1 text-xs ${connected ? "text-muted-foreground" : "text-amber-800"}`}>{!connected ? "Không kết nối được máy chủ. Đang tự thử lại." : lastUpdated ? `Tự cập nhật mỗi 10 giây khi đang xem · Lần cuối ${new Intl.DateTimeFormat("vi-VN", { timeStyle: "medium", timeZone: "Asia/Ho_Chi_Minh" }).format(lastUpdated)}` : "Đang kết nối thông báo…"}</p></div><button type="button" onClick={() => setReload((value) => value + 1)} disabled={loading} className="inline-flex min-h-10 items-center gap-2 rounded-full border border-black/10 bg-white px-4 text-sm font-semibold disabled:opacity-50"><RotateCw className="size-4" />Làm mới</button></div>
    {loading && <p role="status" className="mt-5 text-sm text-muted-foreground">Đang tải thông báo…</p>}
    {error && <p role="alert" className="mt-5 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
    {!loading && !error && result?.data.length === 0 && <p className="mt-5 rounded-xl border border-dashed border-black/10 bg-white p-5 text-sm text-muted-foreground">Bạn chưa có thông báo cảnh báo kho.</p>}
    {!loading && result && result.data.length > 0 && <div className="mt-5 grid gap-3 lg:grid-cols-2">{result.data.map((item) => <article key={item.id} className={`rounded-xl border p-4 ${item.status === "unread" ? "border-amber-200 bg-amber-50/60" : "border-black/10 bg-white"}`}><div className="flex flex-wrap items-start justify-between gap-2"><span className="text-xs font-semibold uppercase tracking-wide text-primary">{item.kind === "low_stock" ? "Tồn dưới ngưỡng" : "Cận hạn / hết hạn"}</span><span className="text-xs text-muted-foreground">{new Intl.DateTimeFormat("vi-VN", { dateStyle: "short", timeStyle: "short", timeZone: "Asia/Ho_Chi_Minh" }).format(new Date(item.created_at))}</span></div><p className="mt-2 text-sm leading-6">{item.message}</p><div className="mt-3 flex flex-wrap items-center justify-between gap-2">{item.resolved_at ? <span className="text-xs text-green-800">Sự cố đã giải quyết</span> : <span className="text-xs text-amber-800">Đang cần theo dõi</span>}{item.status === "unread" ? <button type="button" disabled={pending === item.id} onClick={() => void markRead(item.id)} className="inline-flex min-h-9 items-center gap-1.5 rounded-full border border-black/10 bg-white px-3 text-xs font-semibold disabled:opacity-50"><Check className="size-3.5" />{pending === item.id ? "Đang lưu…" : "Đã đọc"}</button> : <span className="text-xs text-muted-foreground">Đã đọc</span>}</div></article>)}</div>}
  </section>
}
