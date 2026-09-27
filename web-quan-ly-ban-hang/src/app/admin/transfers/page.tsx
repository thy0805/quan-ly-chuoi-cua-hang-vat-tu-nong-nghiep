"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { ArrowLeftRight, Plus, RotateCw, Trash2 } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { ApiError, apiFetch } from "@/lib/api"
import { formatQuantity, formatQuantityDifference } from "@/lib/quantity"

type Warehouse = { id: string; name: string; branch_id: string; branch_name: string; chain_id: string }
type Lot = { warehouse_id: string; lot_id: string; quantity: string; lot_no: string; product_code: string; product_name: string; unit_name: string }
type Options = { sources: Warehouse[]; destinations: Warehouse[]; lots: Lot[] }
type Transfer = { id: string; transfer_no: string; status: string; requested_at: string; requested_by: string; requester_name: string; from_warehouse_name: string; from_branch_name: string; to_warehouse_name: string; to_branch_name: string; reconciliation_reason?: string | null; can_approve?: boolean; can_reject?: boolean; can_dispatch?: boolean; can_receive?: boolean; can_reconcile?: boolean }
type TransferList = { data: Transfer[]; pagination: { current_page: number; last_page: number; total: number } }
type TransferDetail = { data: Transfer; items: (Lot & { id: string; requested_quantity: string; dispatched_quantity: string; received_quantity: string; supplemental_received_quantity: string; returned_quantity: string; lost_quantity: string })[] }
type DraftLine = { lot_id: string; requested_quantity: string }
type Reconciliation = { supplemental_received_quantity: string; returned_quantity: string; lost_quantity: string }

const dateTime = new Intl.DateTimeFormat("vi-VN", { dateStyle: "short", timeStyle: "short", timeZone: "Asia/Ho_Chi_Minh" })
const statusLabel: Record<string, string> = { requested: "Chờ duyệt", approved: "Đã duyệt", rejected: "Đã từ chối", dispatched: "Đã xuất kho", received: "Đã nhận lượng xuất", discrepancy: "Chênh lệch", reconciled: "Đã đối soát" }

function ReconciliationPanel({ items, values, onChange, reason, onReasonChange }: {
  items: TransferDetail["items"]
  values: Record<string, Reconciliation>
  onChange: (value: Record<string, Reconciliation>) => void
  reason: string
  onReasonChange: (value: string) => void
}) {
  const fields = [
    { key: "supplemental_received_quantity", label: "Nhận bổ sung vào kho đích" },
    { key: "returned_quantity", label: "Hoàn về kho nguồn" },
    { key: "lost_quantity", label: "Xác nhận hao hụt" },
  ] as const
  return <div className="space-y-4 rounded-xl border border-amber-200 bg-amber-50/60 p-4">
    <div><p className="font-semibold">Đối soát phần thiếu</p><p className="mt-1 text-muted-foreground">Với mỗi lô, tổng ba hướng xử lý phải đúng bằng lượng đã xuất trừ lượng đã nhận.</p></div>
    {items.map((item) => <div key={item.id} className="rounded-xl border border-black/10 bg-white p-3">
      <p className="font-semibold">{item.product_name} · lô {item.lot_no}</p>
      <p className="mt-1 text-muted-foreground">Còn thiếu {formatQuantityDifference(item.dispatched_quantity, item.received_quantity)} {item.unit_name}</p>
      <div className="mt-3 grid gap-3">{fields.map((field) => <label key={field.key} className="text-xs font-medium">{field.label}<input type="number" min="0" step="0.001" value={values[item.lot_id]?.[field.key] ?? "0"} onChange={(event) => onChange({ ...values, [item.lot_id]: { ...values[item.lot_id], [field.key]: event.target.value } })} className="mt-2 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm" /></label>)}</div>
    </div>)}
    <label className="block font-medium">Lý do và căn cứ đối soát<textarea required minLength={3} maxLength={1000} value={reason} onChange={(event) => onReasonChange(event.target.value)} placeholder="Ghi kết quả kiểm đếm, biên bản giao nhận..." className="mt-2 min-h-24 w-full rounded-xl border border-black/10 bg-white p-3" /></label>
  </div>
}

export default function TransfersPage() {
  const router = useRouter()
  const [list, setList] = useState<TransferList | null>(null)
  const [options, setOptions] = useState<Options | null>(null)
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState("")
  const [reload, setReload] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [open, setOpen] = useState(false)
  const [detail, setDetail] = useState<TransferDetail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [fromId, setFromId] = useState("")
  const [toId, setToId] = useState("")
  const [lines, setLines] = useState<DraftLine[]>([{ lot_id: "", requested_quantity: "1" }])
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState("")
  const [actionError, setActionError] = useState("")
  const [actionBusy, setActionBusy] = useState(false)
  const [rejectReason, setRejectReason] = useState("")
  const [actual, setActual] = useState<Record<string, string>>({})
  const [reconciliation, setReconciliation] = useState<Record<string, Reconciliation>>({})
  const [reconciliationReason, setReconciliationReason] = useState("")

  useEffect(() => {
    const controller = new AbortController()
    async function load() {
      setLoading(true)
      setError("")
      try {
        const params = new URLSearchParams({ page: String(page), per_page: "20" })
        if (status) params.set("status", status)
        const [transfers, choices] = await Promise.all([
          apiFetch<TransferList>(`/api/stock-transfers?${params}`, { signal: controller.signal }),
          apiFetch<Options>("/api/stock-transfers/options", { signal: controller.signal }),
        ])
        if (!controller.signal.aborted) { setList(transfers); setOptions(choices) }
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setList(null)
        setError(caught instanceof Error ? caught.message : "Không tải được phiếu điều chuyển.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }
    load()
    return () => controller.abort()
  }, [page, reload, router, status])

  const source = options?.sources.find((warehouse) => warehouse.id === fromId)
  const destinations = options?.destinations.filter((warehouse) => warehouse.chain_id === source?.chain_id && warehouse.id !== fromId) ?? []
  const lots = options?.lots.filter((lot) => lot.warehouse_id === fromId) ?? []

  async function createTransfer(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saving) return
    setSaving(true)
    setFormError("")
    try {
      await apiFetch("/api/stock-transfers", { method: "POST", body: JSON.stringify({ from_warehouse_id: fromId, to_warehouse_id: toId, items: lines }) })
      setSuccess("Đã lập yêu cầu điều chuyển. Tồn kho chưa thay đổi; người có quyền cần duyệt trước khi xuất.")
      setOpen(false)
      setFromId("")
      setToId("")
      setLines([{ lot_id: "", requested_quantity: "1" }])
      setPage(1)
      setReload((value) => value + 1)
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
      setFormError(caught instanceof Error ? caught.message : "Không tạo được phiếu điều chuyển.")
    } finally { setSaving(false) }
  }

  async function viewTransfer(id: string) {
    setDetailLoading(true)
    setDetail(null)
    setActionError("")
    try {
      const data = await apiFetch<TransferDetail>(`/api/stock-transfers/${id}`)
      setDetail(data)
      setActual(Object.fromEntries(data.items.map((item) => [item.lot_id, data.data.status === "dispatched" ? item.dispatched_quantity : item.requested_quantity])))
      setReconciliation(Object.fromEntries(data.items.map((item) => [item.lot_id, {
        supplemental_received_quantity: item.supplemental_received_quantity ?? "0",
        returned_quantity: item.returned_quantity ?? "0",
        lost_quantity: item.lost_quantity ?? "0",
      }])))
      setReconciliationReason(data.data.reconciliation_reason ?? "")
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Không tải được chi tiết điều chuyển.")
    } finally { setDetailLoading(false) }
  }

  async function performAction(action: "approve" | "reject" | "dispatch" | "receive" | "reconcile") {
    if (!detail || actionBusy) return
    setActionBusy(true)
    setActionError("")
    try {
      const body = action === "reject" ? { reason: rejectReason } : action === "reconcile"
        ? { reason: reconciliationReason, items: detail.items.map((item) => ({ lot_id: item.lot_id, ...reconciliation[item.lot_id] })) }
        : action === "dispatch" || action === "receive"
        ? { items: detail.items.map((item) => ({ lot_id: item.lot_id, [action === "dispatch" ? "dispatched_quantity" : "received_quantity"]: actual[item.lot_id] ?? "0" })) }
        : {}
      const response = await apiFetch<{ status: string }>(`/api/stock-transfers/${detail.data.id}/${action}`, { method: "POST", body: JSON.stringify(body) })
      setSuccess(action === "approve" ? "Đã duyệt phiếu; tồn kho chưa thay đổi." : action === "reject" ? "Đã từ chối phiếu; tồn kho không thay đổi." : action === "dispatch" ? "Đã ghi xuất kho nguồn và lưu hàng đang chuyển." : action === "reconcile" ? "Đã đối soát phần thiếu và ghi đúng lượng nhận thêm, hoàn nguồn, hao hụt." : response.status === "discrepancy" ? "Đã cộng số thực nhận vào kho đích; phần thiếu được giữ để đối soát." : "Đã nhận đủ lượng xuất và cộng tồn kho đích.")
      setReload((value) => value + 1)
      await viewTransfer(detail.data.id)
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
      setActionError(caught instanceof Error ? caught.message : "Không thực hiện được thao tác.")
    } finally { setActionBusy(false) }
  }

  return <main className="p-5 lg:p-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Vận hành kho</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Điều chuyển giữa kho</h1><p className="mt-2 text-sm text-muted-foreground">Lập yêu cầu từ kho nguồn trong phạm vi được phân công. Yêu cầu chưa làm thay đổi tồn kho.</p></div><button type="button" disabled={loading || !options?.sources.length} onClick={() => { setFormError(""); setOpen(true) }} className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-[#274f3a] px-4 text-sm font-semibold text-white hover:bg-[#203d2e] disabled:opacity-50"><Plus className="size-4" />Lập yêu cầu</button></div>
    {success && <div role="status" className="mt-6 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">{success}</div>}
    {error && <div role="alert" className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-2 rounded-lg border border-red-300 px-3 font-semibold hover:bg-red-100"><RotateCw className="size-4" />Thử lại</button></div>}
    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader className="gap-4 sm:flex-row sm:items-center sm:justify-between"><div><CardTitle className="text-lg">Yêu cầu điều chuyển</CardTitle><p className="mt-1 text-sm text-muted-foreground">Phiếu liên quan đến kho nguồn hoặc kho đích bạn được phép xem.</p></div><select aria-label="Lọc trạng thái" value={status} onChange={(event) => { setStatus(event.target.value); setPage(1) }} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm"><option value="">Mọi trạng thái</option>{Object.entries(statusLabel).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full min-w-[740px] text-left text-sm"><thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3 pr-5 font-medium">Phiếu</th><th className="py-3 pr-5 font-medium">Kho nguồn</th><th className="py-3 pr-5 font-medium">Kho đích</th><th className="py-3 pr-5 font-medium">Người lập</th><th className="py-3 font-medium">Trạng thái</th></tr></thead><tbody>{!loading && list?.data.map((row) => <tr key={row.id} className="border-b border-black/6 last:border-0"><td className="py-4 pr-5"><button type="button" onClick={() => viewTransfer(row.id)} className="font-semibold text-primary hover:underline">{row.transfer_no}</button><p className="mt-1 text-xs text-muted-foreground">{dateTime.format(new Date(row.requested_at))}</p></td><td className="py-4 pr-5">{row.from_branch_name}<br /><span className="text-muted-foreground">{row.from_warehouse_name}</span></td><td className="py-4 pr-5">{row.to_branch_name}<br /><span className="text-muted-foreground">{row.to_warehouse_name}</span></td><td className="py-4 pr-5">{row.requester_name}</td><td className="py-4 font-medium">{statusLabel[row.status] ?? row.status}</td></tr>)}</tbody></table>{loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải điều chuyển</span>{[1, 2, 3].map((row) => <Skeleton className="h-12 w-full" key={row} />)}</div>}{!loading && !error && list?.data.length === 0 && <div className="py-12 text-center"><ArrowLeftRight className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Chưa có yêu cầu điều chuyển</p><p className="mt-1 text-sm text-muted-foreground">Nhân viên hoặc Quản lý được phân công kho nguồn có thể lập yêu cầu khi cần chuyển hàng.</p></div>}</div>{list && list.pagination.last_page > 1 && <div className="mt-5 flex items-center justify-end gap-3 text-sm"><button type="button" disabled={page <= 1 || loading} onClick={() => setPage(page - 1)} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trang trước</button><span>{list.pagination.current_page} / {list.pagination.last_page}</span><button type="button" disabled={page >= list.pagination.last_page || loading} onClick={() => setPage(page + 1)} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trang sau</button></div>}</CardContent></Card>
    <Sheet open={open} onOpenChange={setOpen}><SheetContent className="w-full overflow-y-auto bg-[#fbfaf5] p-6 data-[side=right]:sm:max-w-xl"><SheetTitle>Lập yêu cầu điều chuyển</SheetTitle><SheetDescription>Chọn kho cùng chuỗi và các lô đang có tồn tại kho nguồn. Khi lập phiếu, tồn kho chưa bị trừ.</SheetDescription><form onSubmit={createTransfer} className="mt-6 space-y-5"><label className="block text-sm font-medium">Kho nguồn<select required value={fromId} onChange={(event) => { setFromId(event.target.value); setToId(""); setLines([{ lot_id: "", requested_quantity: "1" }]) }} className="mt-2 h-11 w-full rounded-xl border border-black/10 bg-white px-3"><option value="">Chọn kho nguồn</option>{options?.sources.map((warehouse) => <option value={warehouse.id} key={warehouse.id}>{warehouse.branch_name} · {warehouse.name}</option>)}</select></label><label className="block text-sm font-medium">Kho đích<select required value={toId} disabled={!fromId} onChange={(event) => setToId(event.target.value)} className="mt-2 h-11 w-full rounded-xl border border-black/10 bg-white px-3 disabled:opacity-50"><option value="">Chọn kho đích</option>{destinations.map((warehouse) => <option value={warehouse.id} key={warehouse.id}>{warehouse.branch_name} · {warehouse.name}</option>)}</select></label><div><div className="flex items-center justify-between"><p className="text-sm font-medium">Lô cần chuyển</p><button type="button" disabled={!fromId || lines.length >= 50} onClick={() => setLines([...lines, { lot_id: "", requested_quantity: "1" }])} className="text-sm font-semibold text-primary disabled:opacity-40">+ Thêm lô</button></div>{lines.map((line, index) => <div key={index} className="mt-3 grid grid-cols-[minmax(0,1fr)_6rem_2.5rem] gap-2"><select aria-label={`Lô dòng ${index + 1}`} required value={line.lot_id} disabled={!fromId} onChange={(event) => setLines(lines.map((item, itemIndex) => itemIndex === index ? { ...item, lot_id: event.target.value } : item))} className="h-11 min-w-0 rounded-xl border border-black/10 bg-white px-2 text-sm disabled:opacity-50"><option value="">Chọn lô</option>{lots.filter((lot) => lot.lot_id === line.lot_id || !lines.some((item, itemIndex) => itemIndex !== index && item.lot_id === lot.lot_id)).map((lot) => <option value={lot.lot_id} key={lot.lot_id}>{lot.product_name} · {lot.lot_no} · tồn {formatQuantity(lot.quantity)} {lot.unit_name}</option>)}</select><input aria-label={`Số lượng dòng ${index + 1}`} required type="number" min="0.001" step="0.001" value={line.requested_quantity} onChange={(event) => setLines(lines.map((item, itemIndex) => itemIndex === index ? { ...item, requested_quantity: event.target.value } : item))} className="h-11 min-w-0 rounded-xl border border-black/10 bg-white px-2 text-sm" /><button type="button" aria-label={`Xóa dòng ${index + 1}`} disabled={lines.length === 1} onClick={() => setLines(lines.filter((_, itemIndex) => itemIndex !== index))} className="grid size-11 place-items-center rounded-xl border border-black/10 disabled:opacity-40"><Trash2 className="size-4" /></button></div>)}</div>{formError && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">{formError}</p>}<button disabled={saving || !fromId || !toId} className="min-h-11 w-full rounded-xl bg-[#274f3a] px-4 font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu..." : "Lập yêu cầu"}</button></form></SheetContent></Sheet>
    <Sheet open={detail !== null || detailLoading} onOpenChange={(value) => { if (!value) { setDetail(null); setDetailLoading(false) } }}><SheetContent className="w-full overflow-y-auto bg-[#fbfaf5] p-6 data-[side=right]:sm:max-w-xl"><SheetTitle>Chi tiết điều chuyển</SheetTitle><SheetDescription>Dữ liệu phiếu và các lô từ PostgreSQL.</SheetDescription>{detailLoading ? <Skeleton className="mt-6 h-44 w-full" /> : detail && <div className="mt-6 space-y-5 text-sm"><div className="rounded-xl border border-black/10 bg-white p-4"><p className="text-lg font-semibold">{detail.data.transfer_no}</p><p className="mt-1 text-muted-foreground">{statusLabel[detail.data.status] ?? detail.data.status} · {detail.data.requester_name}</p><p className="mt-4">{detail.data.from_branch_name} / {detail.data.from_warehouse_name}</p><p className="my-1 text-primary">↓</p><p>{detail.data.to_branch_name} / {detail.data.to_warehouse_name}</p></div><div className="space-y-2">{detail.items.map((item) => <div key={item.id} className="rounded-xl border border-black/10 bg-white p-4"><p className="font-semibold">{item.product_name} · lô {item.lot_no}</p><p className="mt-1 text-muted-foreground">Yêu cầu {formatQuantity(item.requested_quantity)} {item.unit_name} · Đã xuất {formatQuantity(item.dispatched_quantity)} · Đã nhận {formatQuantity(item.received_quantity)}</p>{(detail.data.can_dispatch || detail.data.can_receive) && <label className="mt-3 block font-medium">{detail.data.can_dispatch ? "Số lượng thực xuất" : "Số lượng thực nhận"}<input type="number" min={detail.data.can_dispatch ? "0.001" : "0"} max={detail.data.can_dispatch ? item.requested_quantity : item.dispatched_quantity} step="0.001" value={actual[item.lot_id] ?? ""} onChange={(event) => setActual({ ...actual, [item.lot_id]: event.target.value })} className="mt-2 h-11 w-full rounded-xl border border-black/10 bg-white px-3" /></label>}</div>)}</div>{detail.data.can_reconcile && <ReconciliationPanel items={detail.items} values={reconciliation} onChange={setReconciliation} reason={reconciliationReason} onReasonChange={setReconciliationReason} />}{detail.data.status === "reconciled" && <p className="rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-emerald-900">Đã đối soát: {detail.data.reconciliation_reason}. {detail.items.map((item) => `${item.lot_no}: nhận bổ sung ${item.supplemental_received_quantity}, hoàn nguồn ${item.returned_quantity}, hao hụt ${item.lost_quantity}`).join("; ")}</p>}{detail.data.can_reject && <label className="block font-medium">Lý do từ chối (nếu có)<textarea value={rejectReason} onChange={(event) => setRejectReason(event.target.value)} maxLength={1000} className="mt-2 min-h-20 w-full rounded-xl border border-black/10 bg-white p-3" /></label>}{actionError && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 p-3 text-red-800">{actionError}</p>}<div className="flex flex-wrap gap-2">{detail.data.can_approve && <button type="button" disabled={actionBusy} onClick={() => performAction("approve")} className="min-h-11 rounded-xl bg-[#274f3a] px-4 font-semibold text-white disabled:opacity-50">Duyệt yêu cầu</button>}{detail.data.can_reject && <button type="button" disabled={actionBusy} onClick={() => performAction("reject")} className="min-h-11 rounded-xl border border-red-300 px-4 font-semibold text-red-800 disabled:opacity-50">Từ chối</button>}{detail.data.can_dispatch && <button type="button" disabled={actionBusy} onClick={() => performAction("dispatch")} className="min-h-11 rounded-xl bg-[#274f3a] px-4 font-semibold text-white disabled:opacity-50">Ghi xuất kho nguồn</button>}{detail.data.can_receive && <button type="button" disabled={actionBusy} onClick={() => performAction("receive")} className="min-h-11 rounded-xl bg-[#274f3a] px-4 font-semibold text-white disabled:opacity-50">Xác nhận thực nhận</button>}{detail.data.can_reconcile && <button type="button" disabled={actionBusy || reconciliationReason.trim().length < 3} onClick={() => performAction("reconcile")} className="min-h-11 rounded-xl bg-[#274f3a] px-4 font-semibold text-white disabled:opacity-50">Chốt đối soát</button>}</div></div>}</SheetContent></Sheet>
  </main>
}
