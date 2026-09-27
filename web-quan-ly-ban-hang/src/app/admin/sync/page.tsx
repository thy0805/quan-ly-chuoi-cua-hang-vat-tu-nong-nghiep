"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { AlertCircle, RefreshCw, RotateCw } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { useAdminProfile } from "@/components/admin/admin-shell"
import { ApiError, apiFetch } from "@/lib/api"

type Event = {
  id: string; aggregate_type: string; aggregate_id: string; event_type: string
  status: string; attempt_count: number; next_attempt_at: string | null
  last_error: string | null; created_at: string; published_at: string | null
}
const statusLabels: Record<string, string> = { failed: "Lỗi cần xử lý", retry: "Chờ thử lại", pending: "Đang chờ", processing: "Đang xử lý", published: "Đã đồng bộ" }

export default function SyncPage() {
  const router = useRouter()
  const profile = useAdminProfile()
  const [status, setStatus] = useState("failed")
  const [events, setEvents] = useState<Event[]>([])
  const [loading, setLoading] = useState(true)
  const [retrying, setRetrying] = useState("")
  const [reload, setReload] = useState(0)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")

  useEffect(() => {
    if (!profile.user.can_manage_sync) return
    const controller = new AbortController()
    async function load() {
      setLoading(true)
      setError("")
      try {
        const result = await apiFetch<{ data: Event[] }>(`/api/outbox?status=${status}`, { signal: controller.signal })
        if (!controller.signal.aborted) setEvents(result.data)
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setEvents([])
        setError(caught instanceof Error ? caught.message : "Không tải được hàng đợi đồng bộ.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }
    load()
    return () => controller.abort()
  }, [profile.user.can_manage_sync, reload, router, status])

  async function retry(id: string) {
    if (retrying) return
    setRetrying(id)
    setError("")
    setSuccess("")
    try {
      await apiFetch(`/api/outbox/${id}/retry`, { method: "POST" })
      setSuccess(`Sự kiện #${id} đã được đưa về hàng đợi. Worker sẽ xử lý khi đang chạy.`)
      setReload((value) => value + 1)
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Không thể chạy lại sự kiện.") }
    finally { setRetrying("") }
  }

  if (!profile.user.can_manage_sync) return <main className="p-8" role="alert">Chỉ Chủ chuỗi được xem hàng đợi đồng bộ của chuỗi mình.</main>

  return <main className="p-5 lg:p-8"><div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">PostgreSQL → MongoDB</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Đồng bộ dữ liệu</h1><p className="mt-2 text-sm text-muted-foreground">Sự kiện được giữ trong PostgreSQL cho đến khi MongoDB ghi thành công. Mỗi sự kiện có thể gửi lại mà không tạo nhật ký trùng.</p></div><button type="button" onClick={() => setReload((value) => value + 1)} disabled={loading} className="inline-flex min-h-11 items-center gap-2 rounded-full border border-black/10 px-4 text-sm font-semibold disabled:opacity-50"><RotateCw className="size-4" />Tải lại</button></div>
    {success && <p role="status" className="mt-6 rounded-xl bg-green-50 px-4 py-3 text-sm text-green-900">{success}</p>}
    {error && <p role="alert" className="mt-6 rounded-xl bg-red-50 px-4 py-3 text-sm text-red-900">{error}</p>}
    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="text-lg">Hàng đợi trong chuỗi của bạn</CardTitle></CardHeader><CardContent><label className="block max-w-sm text-sm font-medium">Trạng thái<select value={status} onChange={(event) => setStatus(event.target.value)} className="mt-1 h-11 w-full rounded-xl border border-black/10 bg-white px-3 outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"><option value="failed">Lỗi cần xử lý</option><option value="retry">Chờ thử lại</option><option value="pending">Đang chờ</option><option value="processing">Đang xử lý</option><option value="published">Đã đồng bộ</option></select></label><div className="mt-5 overflow-x-auto"><table className="w-full min-w-[740px] text-left text-sm"><thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3">Sự kiện</th><th>Đối tượng</th><th>Trạng thái</th><th>Số lần thử</th><th>Lỗi / mốc thời gian</th><th className="text-right">Thao tác</th></tr></thead><tbody>{events.map((event) => <tr key={event.id} className="border-b border-black/6 last:border-0"><td className="py-4"><span className="font-semibold">#{event.id} · {event.event_type}</span><span className="block text-xs text-muted-foreground">{new Intl.DateTimeFormat("vi-VN", { dateStyle: "short", timeStyle: "short" }).format(new Date(event.created_at))}</span></td><td>{event.aggregate_type} #{event.aggregate_id}</td><td>{statusLabels[event.status] ?? event.status}</td><td className="tabular-nums">{event.attempt_count}</td><td className="max-w-xs break-words text-xs text-muted-foreground">{event.last_error ?? (event.published_at ? `Đồng bộ ${new Intl.DateTimeFormat("vi-VN", { dateStyle: "short", timeStyle: "short" }).format(new Date(event.published_at))}` : event.next_attempt_at ? `Thử lúc ${new Intl.DateTimeFormat("vi-VN", { dateStyle: "short", timeStyle: "short" }).format(new Date(event.next_attempt_at))}` : "—")}</td><td className="text-right">{event.status === "failed" && <button type="button" onClick={() => retry(event.id)} disabled={Boolean(retrying)} className="inline-flex min-h-10 items-center gap-1 rounded-lg px-3 font-semibold text-[#274f3a] hover:bg-[#e9eadf] disabled:opacity-40"><RefreshCw className="size-4" />{retrying === event.id ? "Đang đưa vào hàng đợi…" : "Chạy lại"}</button>}</td></tr>)}</tbody></table>{loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải hàng đợi</span>{[1, 2, 3].map((item) => <Skeleton key={item} className="h-12 w-full" />)}</div>}{!loading && !error && events.length === 0 && <div className="py-14 text-center"><AlertCircle className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Không có sự kiện ở trạng thái này</p><p className="mt-1 text-sm text-muted-foreground">Danh sách hiển thị tối đa 50 sự kiện gần nhất trong phạm vi chuỗi.</p></div>}</div></CardContent></Card>
  </main>
}
