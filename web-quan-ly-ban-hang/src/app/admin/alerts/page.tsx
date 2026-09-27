"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { AlertTriangle, CalendarClock, RotateCw, Settings2 } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { NotificationPanel } from "@/components/admin/notification-panel"
import { ApiError, apiFetch, type Branch } from "@/lib/api"
import { formatQuantity, formatQuantityDifference } from "@/lib/quantity"

type LowStock = { id: string; warehouse_id: string; warehouse_name: string; branch_id: string; branch_name: string; product_id: string; product_code: string; product_name: string; unit_name: string; quantity: string; min_stock_quantity: string }
type Expiry = { id: string; branch_name: string; warehouse_name: string; product_code: string; product_name: string; lot_no: string; expires_on: string; quantity: string; unit_name: string; status: "expired" | "expiring"; warning_days: number }
type Pagination = { current_page: number; last_page: number; total: number }
type Alerts = { low_stock: LowStock[]; expiring_lots: Expiry[]; low_pagination: Pagination; expiry_pagination: Pagination; branches: Branch[]; as_of_date: string }
type Thresholds = { warehouses: { id: string; name: string; branch_name: string; can_manage: boolean }[]; products: { id: string; code: string; name: string; unit_name: string }[]; settings: { id: string; warehouse_id: string; product_id: string; min_stock_quantity: string }[] }

const date = (value: string) => { const [year, month, day] = value.slice(0, 10).split("-"); return `${day}/${month}/${year}` }

export default function AlertsPage() {
  const router = useRouter()
  const [alerts, setAlerts] = useState<Alerts | null>(null)
  const [thresholds, setThresholds] = useState<Thresholds | null>(null)
  const [branchId, setBranchId] = useState("")
  const [lowPage, setLowPage] = useState(1)
  const [expiryPage, setExpiryPage] = useState(1)
  const [warehouseId, setWarehouseId] = useState("")
  const [productId, setProductId] = useState("")
  const [minimum, setMinimum] = useState("")
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  const [formError, setFormError] = useState("")
  const [success, setSuccess] = useState("")
  const [reload, setReload] = useState(0)

  useEffect(() => {
    const controller = new AbortController()
    async function load() {
      setLoading(true)
      setError("")
      const params = new URLSearchParams({ low_page: String(lowPage), expiry_page: String(expiryPage) })
      if (branchId) params.set("branch_id", branchId)
      try {
        const [data, settings] = await Promise.all([
          apiFetch<Alerts>(`/api/inventory/alerts?${params}`, { signal: controller.signal }),
          apiFetch<Thresholds>("/api/inventory/thresholds", { signal: controller.signal }),
        ])
        if (!controller.signal.aborted) { setAlerts(data); setThresholds(settings) }
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setAlerts(null)
        setError(caught instanceof Error ? caught.message : "Không tải được cảnh báo kho.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }
    load()
    return () => controller.abort()
  }, [branchId, lowPage, expiryPage, reload, router])

  const selectedWarehouse = thresholds?.warehouses.find((warehouse) => warehouse.id === warehouseId)
  const currentSetting = thresholds?.settings.find((setting) => setting.warehouse_id === warehouseId && setting.product_id === productId)

  function choose(warehouse: string, product: string) {
    setWarehouseId(warehouse)
    setProductId(product)
    setMinimum(thresholds?.settings.find((setting) => setting.warehouse_id === warehouse && setting.product_id === product)?.min_stock_quantity ?? "")
    setFormError("")
  }

  async function saveThreshold(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!warehouseId || !productId || saving) return
    setSaving(true)
    setFormError("")
    setSuccess("")
    try {
      await apiFetch(`/api/inventory/thresholds/${warehouseId}/${productId}`, { method: "PUT", body: JSON.stringify({ min_stock_quantity: minimum }) })
      setSuccess("Đã lưu ngưỡng tồn thấp cho kho và vật tư đã chọn.")
      setReload((value) => value + 1)
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
      setFormError(caught instanceof Error ? caught.message : "Không lưu được ngưỡng tồn thấp.")
    } finally { setSaving(false) }
  }

  return <main className="p-5 lg:p-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Kiểm soát tồn kho</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Cảnh báo kho hàng</h1><p className="mt-2 text-sm text-muted-foreground">Tồn thấp theo kho và vật tư; cận hạn theo từng lô. Ngày kiểm tra do máy chủ xác định theo giờ Việt Nam.</p></div><button type="button" onClick={() => setReload((value) => value + 1)} disabled={loading} className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-black/10 bg-white px-4 text-sm font-semibold hover:bg-[#e9eadf] disabled:opacity-50"><RotateCw className="size-4" />Làm mới</button></div>
    {error && <div role="alert" className="mt-6 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
    {success && <div role="status" className="mt-6 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-900">{success}</div>}
    <NotificationPanel />
    <div className="mt-7 flex flex-wrap items-center justify-between gap-3"><p className="text-sm text-muted-foreground">{alerts ? `Dữ liệu ngày ${date(alerts.as_of_date)}` : "Đang tải dữ liệu"}</p><select aria-label="Lọc chi nhánh" value={branchId} onChange={(event) => { setBranchId(event.target.value); setLowPage(1); setExpiryPage(1) }} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm"><option value="">Tất cả chi nhánh được cấp quyền</option>{alerts?.branches.map((branch) => <option value={branch.id} key={branch.id}>{branch.name}</option>)}</select></div>
    <div className="mt-5 grid gap-5 xl:grid-cols-2">
      <Card className="border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="flex items-center gap-2 text-lg"><AlertTriangle className="size-5 text-amber-700" />Tồn dưới ngưỡng</CardTitle><p className="text-sm text-muted-foreground">Cộng tất cả lô của cùng vật tư trong mỗi kho. Chỉ hiện kho đã cấu hình ngưỡng.</p></CardHeader><CardContent>{loading ? <div role="status" className="space-y-3"><span className="sr-only">Đang tải cảnh báo tồn</span>{[1, 2, 3].map((row) => <Skeleton key={row} className="h-24 w-full" />)}</div> : !error && alerts?.low_stock.length === 0 ? <div className="rounded-xl border border-dashed border-black/10 p-8 text-center text-sm text-muted-foreground">Không có vật tư nào dưới ngưỡng đã cấu hình.</div> : <div className="space-y-3">{alerts?.low_stock.map((row) => <div key={row.id} className="rounded-xl border border-black/10 bg-white p-4"><div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-semibold">{row.product_name}</p><p className="mt-1 text-xs text-muted-foreground">{row.product_code} · {row.branch_name} / {row.warehouse_name}</p></div><span className="rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-900">Thiếu {formatQuantityDifference(row.min_stock_quantity, row.quantity)} {row.unit_name}</span></div><p className="mt-3 text-sm">Hiện có <strong>{formatQuantity(row.quantity)}</strong> / tối thiểu {formatQuantity(row.min_stock_quantity)} {row.unit_name}</p></div>)}</div>}{alerts && alerts.low_pagination.last_page > 1 && <div className="mt-5 flex items-center justify-end gap-3 text-sm"><button type="button" disabled={loading || lowPage === 1} onClick={() => setLowPage(lowPage - 1)} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trước</button><span>{lowPage} / {alerts.low_pagination.last_page}</span><button type="button" disabled={loading || lowPage >= alerts.low_pagination.last_page} onClick={() => setLowPage(lowPage + 1)} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Sau</button></div>}</CardContent></Card>
      <Card className="border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="flex items-center gap-2 text-lg"><CalendarClock className="size-5 text-primary" />Lô cận hạn và hết hạn</CardTitle><p className="text-sm text-muted-foreground">Theo số ngày cảnh báo của vật tư; mặc định 30 ngày khi chưa cấu hình.</p></CardHeader><CardContent>{loading ? <div role="status" className="space-y-3"><span className="sr-only">Đang tải cảnh báo hạn dùng</span>{[1, 2, 3].map((row) => <Skeleton key={row} className="h-24 w-full" />)}</div> : !error && alerts?.expiring_lots.length === 0 ? <div className="rounded-xl border border-dashed border-black/10 p-8 text-center text-sm text-muted-foreground">Không có lô cận hạn trong phạm vi đang xem.</div> : <div className="space-y-3">{alerts?.expiring_lots.map((row) => <div key={row.id} className="rounded-xl border border-black/10 bg-white p-4"><div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-semibold">{row.product_name} · lô {row.lot_no}</p><p className="mt-1 text-xs text-muted-foreground">{row.product_code} · {row.branch_name} / {row.warehouse_name}</p></div><span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${row.status === "expired" ? "bg-red-100 text-red-800" : "bg-amber-100 text-amber-900"}`}>{row.status === "expired" ? "Hết hạn" : "Cận hạn"}</span></div><p className="mt-3 text-sm">Hạn {date(row.expires_on)} · còn {formatQuantity(row.quantity)} {row.unit_name}</p></div>)}</div>}{alerts && alerts.expiry_pagination.last_page > 1 && <div className="mt-5 flex items-center justify-end gap-3 text-sm"><button type="button" disabled={loading || expiryPage === 1} onClick={() => setExpiryPage(expiryPage - 1)} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trước</button><span>{expiryPage} / {alerts.expiry_pagination.last_page}</span><button type="button" disabled={loading || expiryPage >= alerts.expiry_pagination.last_page} onClick={() => setExpiryPage(expiryPage + 1)} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Sau</button></div>}</CardContent></Card>
    </div>
    <Card className="mt-6 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="flex items-center gap-2 text-lg"><Settings2 className="size-5 text-primary" />Ngưỡng tồn theo kho</CardTitle><p className="text-sm text-muted-foreground">Chủ chuỗi được sửa kho trong chuỗi; Quản lý chi nhánh được sửa kho mình phụ trách. Nhân viên có thể xem ngưỡng đã lưu.</p></CardHeader><CardContent><form onSubmit={saveThreshold} className="grid gap-4 lg:grid-cols-[1fr_1fr_10rem_auto] lg:items-end"><label className="text-sm font-medium">Kho<select value={warehouseId} onChange={(event) => choose(event.target.value, productId)} className="mt-2 h-11 w-full rounded-xl border border-black/10 bg-white px-3"><option value="">Chọn kho</option>{thresholds?.warehouses.map((warehouse) => <option value={warehouse.id} key={warehouse.id}>{warehouse.branch_name} · {warehouse.name}</option>)}</select></label><label className="text-sm font-medium">Vật tư<select value={productId} onChange={(event) => choose(warehouseId, event.target.value)} className="mt-2 h-11 w-full rounded-xl border border-black/10 bg-white px-3"><option value="">Chọn vật tư</option>{thresholds?.products.map((product) => <option value={product.id} key={product.id}>{product.code} · {product.name}</option>)}</select></label><label className="text-sm font-medium">Tối thiểu<input type="number" min="0" step="0.001" value={minimum} onChange={(event) => setMinimum(event.target.value)} disabled={!selectedWarehouse?.can_manage} placeholder="Chưa đặt" className="mt-2 h-11 w-full rounded-xl border border-black/10 bg-white px-3 disabled:opacity-50" /></label><button disabled={!selectedWarehouse?.can_manage || !productId || minimum === "" || saving} className="min-h-11 rounded-xl bg-[#274f3a] px-4 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu" : "Lưu ngưỡng"}</button></form>{currentSetting && <p className="mt-3 text-sm text-muted-foreground">Ngưỡng đang lưu: {formatQuantity(currentSetting.min_stock_quantity)} {thresholds?.products.find((product) => product.id === productId)?.unit_name}.</p>}{warehouseId && !selectedWarehouse?.can_manage && <p className="mt-3 text-sm text-muted-foreground">Bạn có quyền xem, chưa có quyền sửa ngưỡng của kho này.</p>}{formError && <p role="alert" className="mt-3 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">{formError}</p>}</CardContent></Card>
  </main>
}
