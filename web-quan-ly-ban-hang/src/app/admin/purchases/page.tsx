"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { ArrowRight, PackagePlus, Plus, RotateCw, Search, Trash2 } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { ApiError, apiFetch, type CatalogProduct, type CatalogResponse, type PurchaseReceipt, type PurchaseReceiptDetail, type PurchaseReceiptOptions, type PurchaseReceiptResponse } from "@/lib/api"
import { formatQuantity } from "@/lib/quantity"
import { formatVnd } from "@/lib/money"

type DraftItem = { product_id: string; product_name: string; lot_no: string; manufactured_on: string; expires_on: string; quantity: string; unit_cost: string }
type Draft = { supplier_id: string; warehouse_id: string; items: DraftItem[] }
const emptyItem = (): DraftItem => ({ product_id: "", product_name: "", lot_no: "", manufactured_on: "", expires_on: "", quantity: "1", unit_cost: "0" })
const labels = { draft: "Bản nháp", submitted: "Chờ duyệt", approved: "Đã duyệt", rejected: "Đã từ chối" }
const dateTime = (value: string) => new Intl.DateTimeFormat("vi-VN", { dateStyle: "short", timeStyle: "short" }).format(new Date(value))

export default function PurchasesPage() {
  const router = useRouter()
  const [result, setResult] = useState<PurchaseReceiptResponse | null>(null)
  const [options, setOptions] = useState<PurchaseReceiptOptions | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [reload, setReload] = useState(0)
  const [page, setPage] = useState(1)
  const [branchId, setBranchId] = useState("")
  const [status, setStatus] = useState("")
  const [open, setOpen] = useState(false)
  const [mode, setMode] = useState<"new" | "edit" | "view">("view")
  const [detail, setDetail] = useState<PurchaseReceiptDetail | null>(null)
  const [draft, setDraft] = useState<Draft>({ supplier_id: "", warehouse_id: "", items: [emptyItem()] })
  const [productSearch, setProductSearch] = useState("")
  const [products, setProducts] = useState<CatalogProduct[]>([])
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState("")
  const [rejectReason, setRejectReason] = useState("")

  useEffect(() => {
    const controller = new AbortController()
    async function load() {
      setLoading(true)
      setError("")
      const params = new URLSearchParams({ page: String(page), per_page: "20" })
      if (branchId) params.set("branch_id", branchId)
      if (status) params.set("status", status)
      try {
        const [receipts, choices] = await Promise.all([
          apiFetch<PurchaseReceiptResponse>(`/api/purchase-receipts?${params}`, { signal: controller.signal }),
          apiFetch<PurchaseReceiptOptions>("/api/purchase-receipts/options", { signal: controller.signal }),
        ])
        if (!controller.signal.aborted) { setResult(receipts); setOptions(choices) }
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setResult(null)
        setError(caught instanceof Error ? caught.message : "Không tải được phiếu nhập.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }
    load()
    return () => controller.abort()
  }, [branchId, page, reload, router, status])

  useEffect(() => {
    if (!open || mode === "view") return
    const controller = new AbortController()
    const timer = window.setTimeout(async () => {
      const params = new URLSearchParams({ active_only: "1", per_page: "50" })
      if (productSearch.trim()) params.set("search", productSearch.trim())
      try {
        const catalog = await apiFetch<CatalogResponse>(`/api/catalog?${params}`, { signal: controller.signal })
        if (!controller.signal.aborted) setProducts(catalog.data)
      } catch { if (!controller.signal.aborted) setProducts([]) }
    }, productSearch ? 250 : 0)
    return () => { window.clearTimeout(timer); controller.abort() }
  }, [mode, open, productSearch])

  const selectedWarehouse = options?.warehouses.find((warehouse) => String(warehouse.id) === draft.warehouse_id)
  const availableSuppliers = options?.suppliers.filter((supplier) => supplier.chain_id === selectedWarehouse?.chain_id) ?? []

  function beginNew() {
    const warehouse = options?.warehouses[0]
    setDraft({ warehouse_id: warehouse ? String(warehouse.id) : "", supplier_id: String(options?.suppliers.find((item) => item.chain_id === warehouse?.chain_id)?.id ?? ""), items: [emptyItem()] })
    setDetail(null)
    setMode("new")
    setProductSearch("")
    setFormError("")
    setOpen(true)
  }

  async function openReceipt(item: PurchaseReceipt) {
    setFormError("")
    setOpen(true)
    setMode("view")
    setDetail(null)
    try { setDetail(await apiFetch<PurchaseReceiptDetail>(`/api/purchase-receipts/${item.id}`)) }
    catch (caught) { setFormError(caught instanceof Error ? caught.message : "Không tải được chi tiết phiếu.") }
  }

  function editDraft() {
    if (!detail) return
    setDraft({
      supplier_id: String(detail.data.supplier_id), warehouse_id: String(detail.data.warehouse_id),
      items: detail.items.map((item) => ({ product_id: String(item.product_id), product_name: item.product_name, lot_no: item.lot_no, manufactured_on: item.manufactured_on ?? "", expires_on: item.expires_on ?? "", quantity: item.quantity, unit_cost: item.unit_cost })),
    })
    setMode("edit")
    setFormError("")
  }

  function updateItem(index: number, key: keyof DraftItem, value: string) {
    setDraft((current) => ({ ...current, items: current.items.map((item, position) => position === index ? { ...item, [key]: value } : item) }))
  }

  async function saveDraft(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saving) return
    setSaving(true)
    setFormError("")
    try {
      const body = {
        supplier_id: draft.supplier_id, warehouse_id: draft.warehouse_id,
        items: draft.items.map((item) => ({ product_id: item.product_id, lot_no: item.lot_no.trim(), manufactured_on: item.manufactured_on || null, expires_on: item.expires_on || null, quantity: item.quantity, unit_cost: item.unit_cost })),
      }
      const response = await apiFetch<{ id: string }>(`/api/purchase-receipts${mode === "edit" ? `/${detail?.data.id}` : ""}`, { method: mode === "edit" ? "PUT" : "POST", body: JSON.stringify(body) })
      setDetail(await apiFetch<PurchaseReceiptDetail>(`/api/purchase-receipts/${response.id}`))
      setMode("view")
      setReload((value) => value + 1)
      setSuccess("Đã lưu bản nháp phiếu nhập. Bạn có thể gửi duyệt khi kiểm tra xong.")
    } catch (caught) { setFormError(caught instanceof Error ? caught.message : "Không lưu được phiếu nhập.") }
    finally { setSaving(false) }
  }

  async function transition(action: "submit" | "approve" | "reject") {
    if (!detail || saving) return
    setSaving(true)
    setFormError("")
    try {
      await apiFetch(`/api/purchase-receipts/${detail.data.id}/${action}`, { method: "POST", body: action === "reject" ? JSON.stringify({ reason: rejectReason.trim() || null }) : undefined })
      setDetail(await apiFetch<PurchaseReceiptDetail>(`/api/purchase-receipts/${detail.data.id}`))
      setReload((value) => value + 1)
      setSuccess(action === "submit" ? "Đã gửi phiếu chờ duyệt." : action === "approve" ? "Đã duyệt và cộng tồn kho." : "Đã từ chối phiếu; tồn kho không đổi.")
    } catch (caught) { setFormError(caught instanceof Error ? caught.message : "Không xử lý được phiếu.") }
    finally { setSaving(false) }
  }

  const inputClass = "mt-1 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"

  return <main className="p-5 lg:p-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Nhập hàng theo kho</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Phiếu nhập</h1><p className="mt-2 text-sm text-muted-foreground">Lập, gửi và duyệt phiếu theo quyền. Tồn kho chỉ tăng sau khi duyệt thành công.</p></div>{options && options.warehouses.length > 0 && <button type="button" onClick={beginNew} className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white hover:bg-[#203d2e]"><Plus className="size-4" />Lập phiếu nhập</button>}</div>
    {success && <p role="status" className="mt-5 rounded-xl bg-[#e1e5d3] p-3 text-sm text-[#274f3a]">{success}</p>}
    {error && <div role="alert" className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-2 rounded-lg border border-red-300 px-3 font-semibold hover:bg-red-100"><RotateCw className="size-4" />Thử lại</button></div>}
    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader className="gap-4 lg:flex-row lg:items-center lg:justify-between"><div><CardTitle className="text-lg">Danh sách phiếu nhập</CardTitle><p className="mt-1 text-sm text-muted-foreground">Mở phiếu để xem chi tiết và thao tác được phép.</p></div><div className="flex flex-col gap-2 sm:flex-row"><select aria-label="Lọc chi nhánh" value={branchId} onChange={(event) => { setBranchId(event.target.value); setPage(1); setResult(null) }} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm"><option value="">Tất cả chi nhánh</option>{result?.branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select><select aria-label="Lọc trạng thái" value={status} onChange={(event) => { setStatus(event.target.value); setPage(1); setResult(null) }} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm"><option value="">Mọi trạng thái</option>{Object.entries(labels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></div></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full min-w-[800px] text-left text-sm"><thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3 pr-5 font-medium">Số phiếu</th><th className="py-3 pr-5 font-medium">Nhà cung cấp</th><th className="py-3 pr-5 font-medium">Chi nhánh / kho</th><th className="py-3 pr-5 font-medium">Người lập</th><th className="py-3 pr-5 font-medium">Tổng tiền</th><th className="py-3 font-medium">Trạng thái</th></tr></thead><tbody>{!loading && result?.data.map((item) => <tr key={item.id} className="cursor-pointer border-b border-black/6 last:border-0 hover:bg-[#f3f1e8]" onClick={() => openReceipt(item)}><td className="py-4 pr-5"><button type="button" className="inline-flex items-center gap-1 font-semibold text-primary hover:underline">{item.receipt_no}<ArrowRight className="size-3" /></button><p className="mt-1 text-xs text-muted-foreground">{dateTime(item.received_at)}</p></td><td className="py-4 pr-5">{item.supplier_name}</td><td className="py-4 pr-5">{item.branch_name}<br /><span className="text-xs text-muted-foreground">{item.warehouse_name}</span></td><td className="py-4 pr-5">{item.creator_name}</td><td className="py-4 pr-5 font-semibold tabular-nums">{formatVnd(item.total_amount)}</td><td className="py-4"><span className={`rounded-full px-2.5 py-1 text-xs font-medium ${item.status === "approved" ? "bg-[#e1e5d3] text-[#274f3a]" : item.status === "rejected" ? "bg-red-100 text-red-800" : "bg-amber-100 text-amber-900"}`}>{labels[item.status]}</span></td></tr>)}</tbody></table>{loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải phiếu nhập</span>{[1, 2, 3].map((row) => <Skeleton key={row} className="h-12 w-full" />)}</div>}{!loading && !error && result?.data.length === 0 && <div className="py-12 text-center"><PackagePlus className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Chưa có phiếu nhập phù hợp</p><p className="mt-1 text-sm text-muted-foreground">Thử bộ lọc khác hoặc lập phiếu khi có quyền và dữ liệu nhà cung cấp.</p></div>}</div>{result && result.pagination.last_page > 1 && <div className="mt-5 flex items-center justify-end gap-3 text-sm"><button type="button" disabled={page <= 1 || loading} onClick={() => { setPage(page - 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trang trước</button><span>{result.pagination.current_page} / {result.pagination.last_page}</span><button type="button" disabled={page >= result.pagination.last_page || loading} onClick={() => { setPage(page + 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trang sau</button></div>}</CardContent></Card>
    <Sheet open={open} onOpenChange={(value) => { if (!saving) setOpen(value) }}><SheetContent side="right" className="data-[side=right]:w-full data-[side=right]:sm:w-[40rem] data-[side=right]:sm:max-w-none overflow-y-auto bg-[#fbfaf5] p-6"><SheetTitle className="text-xl">{mode === "new" ? "Lập phiếu nhập" : mode === "edit" ? "Sửa bản nháp" : detail ? detail.data.receipt_no : "Chi tiết phiếu nhập"}</SheetTitle><SheetDescription className="mt-2">{mode === "view" && detail ? `${detail.data.supplier_name} · ${detail.data.warehouse_name} · ${labels[detail.data.status]}` : "Giá và số lượng từng lô được Backend kiểm tra và tính lại khi lưu."}</SheetDescription>
      {mode !== "view" && <form onSubmit={saveDraft} className="mt-7 space-y-5"><div className="grid gap-4 sm:grid-cols-2"><label className="block text-sm font-medium">Kho nhập<select required disabled={mode === "edit"} value={draft.warehouse_id} onChange={(event) => { const warehouse = options?.warehouses.find((item) => String(item.id) === event.target.value); setDraft((current) => ({ ...current, warehouse_id: event.target.value, supplier_id: String(options?.suppliers.find((item) => item.chain_id === warehouse?.chain_id)?.id ?? "") })) }} className={inputClass}>{options?.warehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>{warehouse.branch_name} / {warehouse.name}</option>)}</select></label><label className="block text-sm font-medium">Nhà cung cấp<select required value={draft.supplier_id} onChange={(event) => setDraft((current) => ({ ...current, supplier_id: event.target.value }))} className={inputClass}><option value="">Chọn nhà cung cấp</option>{availableSuppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}</option>)}</select></label></div>{availableSuppliers.length === 0 && <p className="rounded-lg bg-amber-50 p-3 text-sm text-amber-900">Chuỗi này chưa có nhà cung cấp. Chủ chuỗi cần thêm trước khi lập phiếu.</p>}
      <label className="block text-sm font-medium">Tìm vật tư cho dòng nhập<div className="relative mt-1"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" /><input value={productSearch} onChange={(event) => setProductSearch(event.target.value)} placeholder="Tên, mã hoặc hoạt chất" className="h-11 w-full rounded-xl border border-black/10 bg-white pl-9 pr-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]" /></div></label>
      <div className="space-y-4">{draft.items.map((item, index) => <div key={index} className="rounded-xl border border-black/10 bg-white p-4"><div className="flex items-center justify-between"><p className="font-semibold">Dòng nhập {index + 1}</p><button type="button" aria-label={`Xóa dòng ${index + 1}`} disabled={draft.items.length <= 1} onClick={() => setDraft((current) => ({ ...current, items: current.items.filter((_, position) => position !== index) }))} className="grid size-9 place-items-center rounded-lg text-red-700 hover:bg-red-50 disabled:opacity-40"><Trash2 className="size-4" /></button></div><div className="mt-3 grid gap-3 sm:grid-cols-2"><label className="block text-sm">Vật tư<select required value={item.product_id} onChange={(event) => { const product = products.find((choice) => String(choice.id) === event.target.value); updateItem(index, "product_id", event.target.value); updateItem(index, "product_name", product?.name ?? item.product_name) }} className={inputClass}><option value="">Chọn vật tư</option>{item.product_id && !products.some((choice) => String(choice.id) === item.product_id) && <option value={item.product_id}>{item.product_name}</option>}{products.map((product) => <option key={product.id} value={product.id}>{product.name} · {product.code}</option>)}</select></label><label className="block text-sm">Số lô<input required maxLength={80} value={item.lot_no} onChange={(event) => updateItem(index, "lot_no", event.target.value)} className={inputClass} /></label><label className="block text-sm">Ngày sản xuất<input type="date" value={item.manufactured_on} onChange={(event) => updateItem(index, "manufactured_on", event.target.value)} className={inputClass} /></label><label className="block text-sm">Hạn dùng<input type="date" value={item.expires_on} onChange={(event) => updateItem(index, "expires_on", event.target.value)} className={inputClass} /></label><label className="block text-sm">Số lượng<input type="number" min="0.001" step="0.001" required value={item.quantity} onChange={(event) => updateItem(index, "quantity", event.target.value)} className={inputClass} /></label><label className="block text-sm">Giá nhập / đơn vị (VND)<input type="number" min="0" step="0.01" required value={item.unit_cost} onChange={(event) => updateItem(index, "unit_cost", event.target.value)} className={inputClass} /></label></div></div>)}</div><button type="button" onClick={() => setDraft((current) => ({ ...current, items: [...current.items, emptyItem()] }))} className="inline-flex min-h-10 items-center gap-2 rounded-full border border-black/10 px-4 text-sm font-semibold hover:bg-[#e9eadf]"><Plus className="size-4" />Thêm dòng</button>{formError && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{formError}</p>}<div className="flex justify-end gap-2"><button type="button" onClick={() => setOpen(false)} disabled={saving} className="min-h-11 rounded-full border border-black/10 px-5 text-sm font-semibold disabled:opacity-50">Đóng</button><button type="submit" disabled={saving || availableSuppliers.length === 0} className="min-h-11 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu…" : "Lưu bản nháp"}</button></div></form>}
      {mode === "view" && detail && <div className="mt-7 space-y-5"><div className="grid gap-3 rounded-xl border border-black/10 bg-white p-4 text-sm sm:grid-cols-2"><p><span className="text-muted-foreground">Nhà cung cấp</span><br /><strong>{detail.data.supplier_name}</strong></p><p><span className="text-muted-foreground">Kho nhập</span><br /><strong>{detail.data.branch_name} / {detail.data.warehouse_name}</strong></p><p><span className="text-muted-foreground">Tổng tiền</span><br /><strong>{formatVnd(detail.data.total_amount)}</strong></p><p><span className="text-muted-foreground">Trạng thái</span><br /><strong>{labels[detail.data.status]}</strong></p>{detail.data.rejection_reason && <p className="sm:col-span-2"><span className="text-muted-foreground">Lý do từ chối</span><br />{detail.data.rejection_reason}</p>}</div><div><h3 className="font-semibold">Chi tiết theo lô</h3><div className="mt-3 space-y-2">{detail.items.map((item) => <div key={item.id} className="rounded-xl border border-black/10 bg-white p-4 text-sm"><p className="font-semibold">{item.product_name} · {item.lot_no}</p><p className="mt-1 text-muted-foreground">{formatQuantity(item.quantity)} {item.unit_name} × {formatVnd(item.unit_cost)} = {formatVnd(item.line_total)}</p><p className="mt-1 text-xs text-muted-foreground">Hạn dùng: {item.expires_on || "Không có"}</p></div>)}</div></div>{detail.data.can_reject && <label className="block text-sm">Lý do từ chối (nếu có)<textarea value={rejectReason} onChange={(event) => setRejectReason(event.target.value)} maxLength={1000} className="mt-1 min-h-20 w-full rounded-xl border border-black/10 bg-white p-3 text-sm" /></label>}{formError && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{formError}</p>}<div className="flex flex-wrap justify-end gap-2">{detail.data.can_edit && <button type="button" onClick={editDraft} disabled={saving} className="min-h-11 rounded-full border border-black/10 px-5 text-sm font-semibold disabled:opacity-50">Sửa bản nháp</button>}{detail.data.can_submit && <button type="button" onClick={() => transition("submit")} disabled={saving} className="min-h-11 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang xử lý…" : "Gửi duyệt"}</button>}{detail.data.can_reject && <button type="button" onClick={() => transition("reject")} disabled={saving} className="min-h-11 rounded-full border border-red-300 px-5 text-sm font-semibold text-red-800 disabled:opacity-50">Từ chối</button>}{detail.data.can_approve && <button type="button" onClick={() => transition("approve")} disabled={saving} className="min-h-11 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang duyệt…" : "Duyệt và cộng tồn"}</button>}</div></div>}
      {mode === "view" && !detail && <p role="status" className="mt-8 text-sm text-muted-foreground">Đang tải chi tiết phiếu nhập…</p>}
    </SheetContent></Sheet>
  </main>
}
