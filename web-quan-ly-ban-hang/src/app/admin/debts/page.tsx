"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { HandCoins, RotateCw } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { useAdminProfile } from "@/components/admin/admin-shell"
import { ApiError, apiFetch } from "@/lib/api"
import { formatVnd, moneyCents } from "@/lib/money"

type Charge = {
  id: string; debt_id: string; invoice_id: string | null; purchase_receipt_id: string | null
  branch_id: string; branch_name: string; debt_type: "receivable" | "payable"
  customer_name: string | null; supplier_name: string | null; invoice_no: string | null; receipt_no: string | null
  amount: string; paid_amount: string; remaining_amount: string; occurred_at: string; season_label: string | null; can_pay: boolean
}
type Result = { data: Charge[]; total: number; page: number }

const fieldClass = "mt-1 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"

export default function DebtsPage() {
  const router = useRouter()
  const profile = useAdminProfile()
  const [result, setResult] = useState<Result | null>(null)
  const [type, setType] = useState("")
  const [status, setStatus] = useState("")
  const [branchId, setBranchId] = useState("")
  const [page, setPage] = useState(1)
  const [reload, setReload] = useState(0)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  const [formError, setFormError] = useState("")
  const [success, setSuccess] = useState("")
  const [selected, setSelected] = useState<Charge | null>(null)
  const [amount, setAmount] = useState("")
  const [method, setMethod] = useState("cash")
  const [referenceNote, setReferenceNote] = useState("")
  const [requestKey, setRequestKey] = useState("")
  const amountCents = moneyCents(amount)
  const remainingCents = selected ? moneyCents(selected.remaining_amount) : null

  useEffect(() => {
    const controller = new AbortController()
    const params = new URLSearchParams({ page: String(page) })
    if (type) params.set("type", type)
    if (status) params.set("status", status)
    if (branchId) params.set("branch_id", branchId)
    async function load() {
      setLoading(true)
      setError("")
      try {
        const data = await apiFetch<Result>(`/api/debts?${params}`, { signal: controller.signal })
        if (!controller.signal.aborted) setResult(data)
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setResult(null)
        setError(caught instanceof Error ? caught.message : "Không tải được công nợ.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }
    load()
    return () => controller.abort()
  }, [type, status, branchId, page, reload, router])

  function choose(charge: Charge) {
    setSelected(charge)
    setAmount(charge.remaining_amount)
    setMethod("cash")
    setReferenceNote("")
    setRequestKey(crypto.randomUUID())
    setFormError("")
  }

  async function pay(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!selected || saving) return
    setSaving(true)
    setFormError("")
    setSuccess("")
    try {
      await apiFetch(`/api/debts/${selected.id}/payments`, {
        method: "POST",
        body: JSON.stringify({ amount, method, request_key: requestKey, reference_note: referenceNote || null }),
      })
      setSelected(null)
      setSuccess(selected.debt_type === "receivable" ? "Đã ghi nhận thu nợ khách hàng." : "Đã ghi nhận chi trả nhà cung cấp.")
      setReload((value) => value + 1)
    } catch (caught) { setFormError(caught instanceof Error ? caught.message : "Không ghi nhận được thanh toán.") }
    finally { setSaving(false) }
  }

  return <main className="p-5 lg:p-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Sổ công nợ</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Phải thu & phải trả</h1><p className="mt-2 text-sm text-muted-foreground">Mỗi khoản gắn hóa đơn bán hoặc phiếu nhập đã duyệt. Số dư được tính từ các lần thu, chi thực tế.</p></div><button type="button" onClick={() => setReload((value) => value + 1)} disabled={loading} className="inline-flex min-h-11 items-center gap-2 rounded-full border border-black/10 px-4 text-sm font-semibold disabled:opacity-50"><RotateCw className="size-4" />Tải lại</button></div>
    {success && <p role="status" className="mt-6 rounded-xl bg-green-50 px-4 py-3 text-sm text-green-900">{success}</p>}
    {error && <p role="alert" className="mt-6 rounded-xl bg-red-50 px-4 py-3 text-sm text-red-900">{error}</p>}
    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="text-lg">Khoản phát sinh theo chứng từ</CardTitle></CardHeader><CardContent>
      <div className="grid gap-3 sm:grid-cols-3"><label className="text-sm font-medium">Loại công nợ<select value={type} onChange={(event) => { setType(event.target.value); setPage(1) }} className={fieldClass}><option value="">Tất cả</option><option value="receivable">Phải thu khách</option><option value="payable">Phải trả NCC</option></select></label><label className="text-sm font-medium">Trạng thái<select value={status} onChange={(event) => { setStatus(event.target.value); setPage(1) }} className={fieldClass}><option value="">Tất cả</option><option value="open">Còn nợ</option><option value="paid">Đã tất toán</option></select></label><label className="text-sm font-medium">Chi nhánh nguồn<select value={branchId} onChange={(event) => { setBranchId(event.target.value); setPage(1) }} className={fieldClass}><option value="">Chi nhánh được xem</option>{profile.branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label></div>
      <div className="mt-5 overflow-x-auto"><table className="w-full min-w-[780px] text-left text-sm"><thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3">Chứng từ</th><th>Đối tác</th><th>Chi nhánh</th><th className="text-right">Phát sinh</th><th className="text-right">Đã thu/chi</th><th className="text-right">Còn lại</th><th className="text-right">Thao tác</th></tr></thead><tbody>{result?.data.map((charge) => <tr key={charge.id} className="border-b border-black/6 last:border-0"><td className="py-4"><span className="font-semibold">{charge.invoice_no ?? charge.receipt_no}</span><span className="block text-xs text-muted-foreground">{charge.debt_type === "receivable" ? "Phải thu" : "Phải trả"} · {new Intl.DateTimeFormat("vi-VN", { dateStyle: "short" }).format(new Date(charge.occurred_at))}</span></td><td>{charge.customer_name ?? charge.supplier_name}{charge.season_label && <span className="block text-xs text-muted-foreground">Mùa vụ: {charge.season_label}</span>}</td><td>{charge.branch_name}</td><td className="text-right tabular-nums">{formatVnd(charge.amount)}</td><td className="text-right tabular-nums">{formatVnd(charge.paid_amount)}</td><td className="text-right font-semibold tabular-nums">{formatVnd(charge.remaining_amount)}</td><td className="text-right">{charge.can_pay && <button type="button" onClick={() => choose(charge)} className="min-h-10 rounded-lg px-3 font-semibold text-[#274f3a] hover:bg-[#e9eadf]">{charge.debt_type === "receivable" ? "Thu nợ" : "Chi trả"}</button>}</td></tr>)}</tbody></table>
      {loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải công nợ</span>{[1, 2, 3].map((item) => <Skeleton key={item} className="h-12 w-full" />)}</div>}
      {!loading && !error && result?.data.length === 0 && <div className="py-14 text-center"><HandCoins className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Chưa có khoản công nợ phù hợp</p><p className="mt-1 text-sm text-muted-foreground">Khoản phải thu phát sinh từ hóa đơn có khách; khoản phải trả phát sinh khi duyệt phiếu nhập.</p></div>}
      </div><div className="mt-4 flex items-center justify-between text-sm text-muted-foreground"><span>{result?.total ?? 0} khoản</span><div className="flex gap-2"><button type="button" onClick={() => setPage((current) => current - 1)} disabled={loading || page <= 1} className="min-h-10 rounded-lg border px-3 disabled:opacity-40">Trước</button><span className="grid min-w-8 place-items-center">{page}</span><button type="button" onClick={() => setPage((current) => current + 1)} disabled={loading || !result || page * 20 >= result.total} className="min-h-10 rounded-lg border px-3 disabled:opacity-40">Sau</button></div></div>
    </CardContent></Card>
    <Sheet open={selected !== null} onOpenChange={(open) => { if (!open && !saving) setSelected(null) }}><SheetContent side="right" className="w-full overflow-y-auto border-black/10 bg-[#fbfaf5] p-6 data-[side=right]:sm:max-w-xl"><SheetTitle className="text-2xl font-semibold">{selected?.debt_type === "receivable" ? "Ghi nhận thu nợ" : "Ghi nhận chi trả"}</SheetTitle><SheetDescription className="mt-2">Chỉ ghi nhận khoản tiền đã kiểm tra thực tế. Giao dịch hoàn tất sẽ lưu dấu vết và không sửa trực tiếp.</SheetDescription>{selected && <form onSubmit={pay} className="mt-7 space-y-4"><div className="rounded-2xl bg-[#e9eadf] p-4 text-sm"><p className="font-semibold">{selected.invoice_no ?? selected.receipt_no} · {selected.customer_name ?? selected.supplier_name}</p><p className="mt-2">Chi nhánh: {selected.branch_name}</p><p className="mt-2">Còn lại: <strong>{formatVnd(selected.remaining_amount)}</strong></p></div><label className="block text-sm font-medium">Số tiền (VND)<input required type="number" min="0.01" max={selected.remaining_amount} step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} className={fieldClass} /></label><label className="block text-sm font-medium">Phương thức<select required value={method} onChange={(event) => setMethod(event.target.value)} className={fieldClass}><option value="cash">Tiền mặt</option><option value="bank_transfer">Chuyển khoản thủ công</option></select></label>{method === "bank_transfer" && <label className="block text-sm font-medium">Mã tham chiếu / ghi chú<input maxLength={200} value={referenceNote} onChange={(event) => setReferenceNote(event.target.value)} className={fieldClass} placeholder="Tùy chọn; tự đối chiếu giao dịch ngân hàng" /></label>}{formError && <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800">{formError}</p>}<button type="submit" disabled={saving || amountCents === null || remainingCents === null || amountCents <= BigInt(0) || amountCents > remainingCents} className="min-h-11 w-full rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang ghi nhận…" : selected.debt_type === "receivable" ? "Xác nhận đã thu" : "Xác nhận đã chi"}</button></form>}</SheetContent></Sheet>
  </main>
}
