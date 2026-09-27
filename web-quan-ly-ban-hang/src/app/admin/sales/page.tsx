"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { Check, ClipboardList, Plus, Printer, RotateCw, Trash2 } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { ApiError, apiFetch } from "@/lib/api"

type Warehouse = { id: string; name: string; branch_id: string; chain_id: string; branch_name: string }
type Customer = { id: string; chain_id: string; name: string; customer_type: string }
type Stock = { warehouse_id: string; lot_id: string; quantity: string; product_id: string; code: string; name: string; sale_price: string; tax_rate: string | null; lot_no: string; expires_on: string | null; unit_name: string }
type Options = { warehouses: Warehouse[]; customers: Customer[]; stock: Stock[] }
type Order = { id: string; order_no: string; status: string; total_amount: string; sold_at: string; branch_id: string; branch_name: string; customer_id: string | null; customer_name: string | null; invoice_id: string | null; invoice_no: string | null }
type Line = { id: string; lot_id: string; quantity: string; unit_price: string; discount_amount: string; line_total: string; tax_rate_snapshot: string; tax_amount: string; unit_cost_snapshot: string | null; cost_total: string | null; lot_no: string; product_code: string; product_name: string }
type Detail = { data: Order & { warehouse_id: string; created_by: string; season_label: string | null; subtotal: string | null; invoice_discount_amount: string | null; invoice_tax_amount: string | null; paid_amount: string | null; remaining_amount: string | null }; items: Line[] }
type DraftLine = { lot_id: string; quantity: string; discount_amount: string }

const money = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 2 })
const blankLine = (): DraftLine => ({ lot_id: "", quantity: "1", discount_amount: "0" })
const fieldClass = "mt-1 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a] disabled:bg-stone-100"

export default function SalesPage() {
  const router = useRouter()
  const [orders, setOrders] = useState<Order[]>([])
  const [options, setOptions] = useState<Options | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [reload, setReload] = useState(0)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState("")
  const [detail, setDetail] = useState<Detail | null>(null)
  const [warehouseId, setWarehouseId] = useState("")
  const [customerId, setCustomerId] = useState("")
  const [seasonLabel, setSeasonLabel] = useState("")
  const [lines, setLines] = useState<DraftLine[]>([blankLine()])
  const [paymentAmount, setPaymentAmount] = useState("")
  const [paymentMethod, setPaymentMethod] = useState("cash")
  const [referenceNote, setReferenceNote] = useState("")

  useEffect(() => {
    const controller = new AbortController()
    async function load() {
      setLoading(true)
      setError("")
      try {
        const [history, choices] = await Promise.all([
          apiFetch<{ data: Order[] }>("/api/sales-orders", { signal: controller.signal }),
          apiFetch<Options>("/api/sales-orders/options", { signal: controller.signal }),
        ])
        if (!controller.signal.aborted) { setOrders(history.data); setOptions(choices) }
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setError(caught instanceof Error ? caught.message : "Không tải được bán hàng.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }
    load()
    return () => controller.abort()
  }, [reload, router])

  const warehouse = options?.warehouses.find((row) => row.id === warehouseId)
  const customers = options?.customers.filter((row) => row.chain_id === warehouse?.chain_id) ?? []
  const stock = useMemo(() => options?.stock.filter((row) => row.warehouse_id === warehouseId) ?? [], [options, warehouseId])
  const availableStock = stock.filter((row) => row.tax_rate !== null)
  const draftTotal = detail?.items.reduce((total, item) => total + Number(item.line_total) + Number(item.tax_amount), 0) ?? 0
  const paymentValid = paymentAmount !== "" && Number.isFinite(Number(paymentAmount))
    && Number(paymentAmount) >= 0 && Number(paymentAmount) <= draftTotal + 0.001
    && (detail?.data.customer_id !== null || Number(paymentAmount) >= draftTotal - 0.001)

  function begin() {
    setDetail(null)
    setWarehouseId(options?.warehouses[0]?.id ?? "")
    setCustomerId("")
    setSeasonLabel("")
    setLines([blankLine()])
    setPaymentAmount("")
    setPaymentMethod("cash")
    setReferenceNote("")
    setFormError("")
    setOpen(true)
  }

  async function show(id: string) {
    setDetail(null)
    setFormError("")
    setOpen(true)
    try {
      const next = await apiFetch<Detail>(`/api/sales-orders/${id}`)
      setDetail(next)
      setPaymentAmount(next.items.reduce((total, item) => total + Number(item.line_total) + Number(item.tax_amount), 0).toFixed(2))
      setPaymentMethod("cash")
      setReferenceNote("")
    }
    catch (caught) { setFormError(caught instanceof Error ? caught.message : "Không tải được đơn bán.") }
  }

  function editLine(index: number, key: keyof DraftLine, value: string) {
    setLines((current) => current.map((line, position) => position === index ? { ...line, [key]: value } : line))
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saving || !warehouse) return
    setSaving(true)
    setFormError("")
    try {
      const result = await apiFetch<{ id: string }>("/api/sales-orders", {
        method: "POST",
        body: JSON.stringify({ branch_id: warehouse.branch_id, warehouse_id: warehouse.id, customer_id: customerId || null, season_label: customerId ? seasonLabel || null : null, items: lines }),
      })
      const next = await apiFetch<Detail>(`/api/sales-orders/${result.id}`)
      setDetail(next)
      setPaymentAmount(next.items.reduce((total, item) => total + Number(item.line_total) + Number(item.tax_amount), 0).toFixed(2))
      setSuccess("Đã lưu bản nháp. Kiểm tra chi tiết rồi xác nhận bán để trừ tồn và phát hành hóa đơn.")
      setReload((value) => value + 1)
    } catch (caught) { setFormError(caught instanceof Error ? caught.message : "Không lưu được đơn bán.") }
    finally { setSaving(false) }
  }

  async function confirm() {
    if (!detail || saving) return
    setSaving(true)
    setFormError("")
    try {
      await apiFetch(`/api/sales-orders/${detail.data.id}/confirm`, {
        method: "POST",
        body: JSON.stringify({ amount: paymentAmount, method: Number(paymentAmount) > 0 ? paymentMethod : null, reference_note: referenceNote || null }),
      })
      setDetail(await apiFetch<Detail>(`/api/sales-orders/${detail.data.id}`))
      setSuccess("Đã xác nhận bán, cập nhật tồn kho và phát hành hóa đơn.")
      setReload((value) => value + 1)
    } catch (caught) { setFormError(caught instanceof Error ? caught.message : "Không xác nhận được đơn bán.") }
    finally { setSaving(false) }
  }

  return (
    <main className="p-5 lg:p-8">
      <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Bán hàng tại quầy</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Đơn bán & hóa đơn</h1><p className="mt-2 text-sm text-muted-foreground">Chọn đúng kho và lô thực xuất. Giá, thuế, tổng tiền và giá vốn được Backend chốt khi bán.</p></div><button type="button" onClick={begin} disabled={!options?.warehouses.length || loading} className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50"><Plus className="size-4" />Tạo đơn bán</button></div>
      {success && <p role="status" className="mt-6 rounded-xl bg-green-50 px-4 py-3 text-sm text-green-900">{success}</p>}
      {error && <div role="alert" className="mt-6 flex items-center justify-between gap-3 rounded-xl bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-1 font-semibold"><RotateCw className="size-4" />Thử lại</button></div>}
      <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="text-lg">Đơn gần đây</CardTitle></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full min-w-[650px] text-left text-sm"><thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3">Đơn / hóa đơn</th><th>Chi nhánh</th><th>Khách hàng</th><th>Thành tiền</th><th>Trạng thái</th><th className="text-right">Thao tác</th></tr></thead><tbody>{orders.map((order) => <tr key={order.id} className="border-b border-black/6 last:border-0"><td className="py-4"><span className="font-semibold">{order.order_no}</span><span className="block text-xs text-muted-foreground">{order.invoice_no ?? "Chưa phát hành hóa đơn"}</span></td><td>{order.branch_name}</td><td>{order.customer_name ?? "Khách lẻ"}</td><td className="tabular-nums">{order.status === "confirmed" ? money.format(Number(order.total_amount)) : "Chưa chốt"}</td><td><span className={`rounded-full px-2.5 py-1 text-xs font-medium ${order.status === "confirmed" ? "bg-[#e1e5d3] text-[#274f3a]" : "bg-amber-100 text-amber-900"}`}>{order.status === "confirmed" ? "Đã xác nhận" : "Bản nháp"}</span></td><td className="text-right"><button type="button" onClick={() => show(order.id)} className="min-h-10 rounded-lg px-3 font-semibold text-[#274f3a] hover:bg-[#e9eadf]">Chi tiết</button></td></tr>)}</tbody></table>{loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải đơn bán</span>{[1, 2, 3].map((row) => <Skeleton key={row} className="h-12 w-full" />)}</div>}{!loading && !error && orders.length === 0 && <div className="py-14 text-center"><ClipboardList className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Chưa có đơn bán</p><p className="mt-1 text-sm text-muted-foreground">Tạo đơn đầu tiên khi kho đã có lô và vật tư đã được cấu hình thuế.</p></div>}</div></CardContent></Card>
      <Sheet open={open} onOpenChange={(value) => { if (!saving) setOpen(value) }}><SheetContent side="right" className="data-[side=right]:w-full data-[side=right]:sm:w-[42rem] data-[side=right]:sm:max-w-none overflow-y-auto bg-[#fbfaf5] p-6"><SheetTitle className="text-xl">{detail ? detail.data.order_no : "Tạo đơn bán tại quầy"}</SheetTitle><SheetDescription className="mt-2">{detail ? "Thông tin chứng từ và các dòng vật tư đã ghi." : "Bản nháp chưa trừ tồn. Xác nhận sau khi kiểm tra lô, số lượng và chiết khấu."}</SheetDescription>
        {formError && <p role="alert" className="mt-5 rounded-xl bg-red-50 p-3 text-sm text-red-800">{formError}</p>}
        {detail ? <div className="mt-7 space-y-5"><div className="grid gap-3 rounded-2xl border border-black/8 bg-white p-4 text-sm sm:grid-cols-2"><div><span className="text-muted-foreground">Trạng thái</span><p className="mt-1 font-semibold">{detail.data.status === "confirmed" ? "Đã xác nhận" : "Bản nháp"}</p></div><div><span className="text-muted-foreground">Khách hàng</span><p className="mt-1 font-semibold">{detail.data.customer_name ?? "Khách lẻ"}</p></div>{detail.data.season_label && <div><span className="text-muted-foreground">Mùa vụ</span><p className="mt-1 font-semibold">{detail.data.season_label}</p></div>}<div><span className="text-muted-foreground">Hóa đơn</span><p className="mt-1 font-semibold">{detail.data.invoice_no ?? "Chưa phát hành"}</p></div><div><span className="text-muted-foreground">Tổng thanh toán</span><p className="mt-1 font-semibold tabular-nums">{detail.data.status === "confirmed" ? money.format(Number(detail.data.total_amount)) : "Chờ xác nhận"}</p></div></div><div className="space-y-3">{detail.items.map((item) => <div key={item.id} className="rounded-2xl border border-black/8 bg-white p-4 text-sm"><div className="flex justify-between gap-3"><div><p className="font-semibold">{item.product_name}</p><p className="mt-1 text-xs text-muted-foreground">{item.product_code} · Lô {item.lot_no}</p></div><span className="font-semibold tabular-nums">{item.quantity}</span></div><div className="mt-3 grid grid-cols-2 gap-2 text-xs text-muted-foreground sm:grid-cols-4"><span>Giá {money.format(Number(item.unit_price))}</span><span>Giảm {money.format(Number(item.discount_amount))}</span><span>Thuế {item.tax_rate_snapshot}% · {money.format(Number(item.tax_amount))}</span><span>Trước thuế {money.format(Number(item.line_total))}</span></div></div>)}</div>{detail.data.status === "confirmed" && <div className="rounded-2xl bg-[#e9eadf] p-4 text-sm"><div className="flex justify-between"><span>Tiền hàng</span><strong>{money.format(Number(detail.data.subtotal))}</strong></div><div className="mt-2 flex justify-between"><span>Chiết khấu</span><strong>−{money.format(Number(detail.data.invoice_discount_amount))}</strong></div><div className="mt-2 flex justify-between"><span>Thuế</span><strong>+{money.format(Number(detail.data.invoice_tax_amount))}</strong></div><div className="mt-3 flex justify-between border-t border-black/10 pt-3 text-base"><span>Thành tiền</span><strong>{money.format(Number(detail.data.total_amount))}</strong></div></div>}{detail.data.status === "draft" && <div className="space-y-3 rounded-2xl border border-[#d8ddc9] bg-[#f2f3e9] p-4 text-sm"><div className="flex items-center justify-between gap-3"><span>Tổng cần thanh toán</span><strong className="tabular-nums">{money.format(draftTotal)}</strong></div><p className="text-xs text-muted-foreground">{detail.data.customer_id ? "Có thể thu một phần; phần còn lại vào công nợ khách hàng." : "Khách lẻ cần thanh toán đủ trước khi xác nhận bán."}</p><div className="grid gap-3 sm:grid-cols-2"><label className="font-medium">Số tiền đã thu (VND)<input type="number" min={detail.data.customer_id ? "0" : draftTotal.toFixed(2)} max={draftTotal.toFixed(2)} step="0.01" value={paymentAmount} onChange={(event) => setPaymentAmount(event.target.value)} className={fieldClass} /></label><label className="font-medium">Phương thức<select value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)} disabled={Number(paymentAmount) === 0} className={fieldClass}><option value="cash">Tiền mặt</option><option value="bank_transfer">Chuyển khoản thủ công</option></select></label></div>{paymentMethod === "bank_transfer" && Number(paymentAmount) > 0 && <label className="block font-medium">Mã tham chiếu / ghi chú chuyển khoản<input maxLength={200} value={referenceNote} onChange={(event) => setReferenceNote(event.target.value)} className={fieldClass} placeholder="Tùy chọn; người thu tự đối chiếu giao dịch" /></label>}{paymentAmount !== "" && Number(paymentAmount) < draftTotal && detail.data.customer_id && <p className="font-medium text-amber-900">Còn phải thu: {money.format(draftTotal - Number(paymentAmount))}</p>}{!paymentValid && <p role="alert" className="text-red-700">Số tiền thu không hợp lệ hoặc khách lẻ chưa thanh toán đủ.</p>}</div>}{detail.data.status === "confirmed" && <div className="rounded-2xl border border-black/8 bg-white p-4 text-sm"><div className="flex justify-between gap-3"><span>Đã thu</span><strong>{money.format(Number(detail.data.paid_amount ?? 0))}</strong></div><div className="mt-2 flex justify-between gap-3"><span>Còn phải thu</span><strong>{money.format(Number(detail.data.remaining_amount ?? 0))}</strong></div></div>}<div className="flex flex-wrap justify-end gap-2">{detail.data.status === "confirmed" && <a href={`/admin/sales/print/${detail.data.id}`} target="_blank" rel="noopener noreferrer" className="inline-flex min-h-11 items-center gap-2 rounded-full border border-black/10 px-5 text-sm font-semibold"><Printer className="size-4" />Bản in hóa đơn</a>}{detail.data.status === "draft" && <button type="button" onClick={confirm} disabled={saving || !paymentValid} className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50"><Check className="size-4" />{saving ? "Đang xác nhận…" : "Xác nhận bán"}</button>}</div></div> : <form onSubmit={save} className="mt-7 space-y-5"><label className="block text-sm font-medium">Kho xuất<select required value={warehouseId} onChange={(event) => { setWarehouseId(event.target.value); setCustomerId(""); setLines([blankLine()]) }} className={fieldClass}><option value="">Chọn kho</option>{options?.warehouses.map((row) => <option key={row.id} value={row.id}>{row.branch_name} · {row.name}</option>)}</select></label><label className="block text-sm font-medium">Khách hàng<select value={customerId} onChange={(event) => setCustomerId(event.target.value)} className={fieldClass}><option value="">Khách lẻ</option>{customers.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label>{customerId && <label className="block text-sm font-medium">Mùa vụ / đợt canh tác (tùy chọn)<input maxLength={120} value={seasonLabel} onChange={(event) => setSeasonLabel(event.target.value)} className={fieldClass} placeholder="Ví dụ: Đông Xuân 2026–2027" /></label>}<div><div className="flex items-center justify-between"><h3 className="text-sm font-semibold">Vật tư và lô thực xuất</h3><button type="button" onClick={() => setLines((current) => [...current, blankLine()])} disabled={availableStock.length <= lines.length} className="inline-flex min-h-10 items-center gap-1 text-sm font-semibold text-[#274f3a] disabled:opacity-40"><Plus className="size-4" />Thêm dòng</button></div>{stock.length > 0 && availableStock.length === 0 && <p className="mt-2 rounded-lg bg-amber-50 p-3 text-xs text-amber-900">Các vật tư còn tồn chưa được cấu hình thuế suất. Chủ chuỗi quản trị danh mục cần cập nhật trước khi bán.</p>}<div className="mt-3 space-y-3">{lines.map((line, index) => <div key={index} className="rounded-2xl border border-black/8 bg-white p-4"><div className="flex items-start gap-2"><label className="min-w-0 flex-1 text-sm font-medium">Lô vật tư<select required value={line.lot_id} onChange={(event) => editLine(index, "lot_id", event.target.value)} className={fieldClass}><option value="">Chọn vật tư / lô</option>{availableStock.map((row) => <option key={row.lot_id} value={row.lot_id} disabled={lines.some((other, position) => position !== index && other.lot_id === row.lot_id)}>{row.name} · lô {row.lot_no} · tồn {row.quantity} {row.unit_name}</option>)}</select></label><button type="button" aria-label={`Xóa dòng ${index + 1}`} onClick={() => setLines((current) => current.filter((_, position) => position !== index))} disabled={lines.length === 1} className="mt-6 grid size-11 place-items-center rounded-xl text-red-700 hover:bg-red-50 disabled:opacity-30"><Trash2 className="size-4" /></button></div>{line.lot_id && <p className="mt-2 text-xs text-muted-foreground">Giá cơ sở {money.format(Number(stock.find((row) => row.lot_id === line.lot_id)?.sale_price ?? 0))} · thuế {stock.find((row) => row.lot_id === line.lot_id)?.tax_rate}%</p>}<div className="mt-3 grid grid-cols-2 gap-3"><label className="text-sm font-medium">Số lượng<input required type="number" min="0.001" step="0.001" value={line.quantity} onChange={(event) => editLine(index, "quantity", event.target.value)} className={fieldClass} /></label><label className="text-sm font-medium">Chiết khấu dòng (VND)<input required type="number" min="0" step="0.01" value={line.discount_amount} onChange={(event) => editLine(index, "discount_amount", event.target.value)} className={fieldClass} /></label></div></div>)}</div></div><p className="text-xs text-muted-foreground">Giá và thuế được lưu theo từng dòng. Nếu danh mục đổi trước lúc xác nhận, hệ thống yêu cầu lập lại đơn.</p><div className="flex justify-end"><button type="submit" disabled={saving || !warehouse || availableStock.length === 0} className="min-h-11 rounded-full bg-[#274f3a] px-6 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu…" : "Lưu bản nháp"}</button></div></form>}
      </SheetContent></Sheet>
    </main>
  )
}
