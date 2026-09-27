"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { ArrowLeft, ArrowDownLeft, ArrowUpRight, History, RotateCw, Search } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { ApiError, apiFetch, type Branch } from "@/lib/api"

type Movement = {
  id: string
  movement_type: string
  quantity_delta: string
  occurred_at: string
  branch_name: string
  warehouse_name: string
  product_code: string
  product_name: string
  lot_no: string
  unit_name: string
  purchase_receipt_id: string | null
  sales_order_id: string | null
  stock_transfer_id: string | null
  receipt_no: string | null
  order_no: string | null
  transfer_no: string | null
}

type MovementResponse = {
  data: Movement[]
  branches: Branch[]
  pagination: { current_page: number; last_page: number; total: number }
}

const quantityFormat = new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 3 })
const dateFormat = new Intl.DateTimeFormat("vi-VN", { dateStyle: "short", timeStyle: "short", timeZone: "Asia/Ho_Chi_Minh" })

function sourceLabel(row: Movement) {
  if (row.purchase_receipt_id) return { type: "Phiếu nhập", number: row.receipt_no ?? row.purchase_receipt_id, href: `/admin/purchases` }
  if (row.sales_order_id) return { type: "Đơn bán", number: row.order_no ?? row.sales_order_id, href: `/admin/sales` }
  return { type: "Điều chuyển", number: row.transfer_no ?? row.stock_transfer_id ?? "—", href: "" }
}

export default function InventoryMovementsPage() {
  const router = useRouter()
  const [search, setSearch] = useState("")
  const [branchId, setBranchId] = useState("")
  const [page, setPage] = useState(1)
  const [result, setResult] = useState<MovementResponse | null>(null)
  const [branches, setBranches] = useState<Branch[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [reload, setReload] = useState(0)

  useEffect(() => {
    const controller = new AbortController()
    const timer = window.setTimeout(async () => {
      setLoading(true)
      setError("")
      const params = new URLSearchParams({ page: String(page), per_page: "20" })
      if (search.trim()) params.set("search", search.trim())
      if (branchId) params.set("branch_id", branchId)
      try {
        const data = await apiFetch<MovementResponse>(`/api/inventory/movements?${params}`, { signal: controller.signal })
        if (!controller.signal.aborted) {
          setResult(data)
          setBranches(data.branches)
        }
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) {
          router.replace("/login")
          return
        }
        setResult(null)
        setError(caught instanceof Error ? caught.message : "Không tải được lịch sử biến động.")
      } finally {
        if (!controller.signal.aborted) setLoading(false)
      }
    }, search ? 250 : 0)
    return () => { window.clearTimeout(timer); controller.abort() }
  }, [branchId, page, reload, router, search])

  return <main className="p-5 lg:p-8">
    <Link href="/admin/inventory" className="inline-flex min-h-10 items-center gap-2 text-sm font-semibold text-primary hover:underline"><ArrowLeft className="size-4" />Tồn kho theo lô</Link>
    <div className="mt-4">
      <p className="text-sm font-medium text-primary">Nhật ký kho hàng</p>
      <h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Lịch sử biến động</h1>
      <p className="mt-2 text-sm text-muted-foreground">Mỗi dòng ghi nhận một lần nhập, bán hoặc điều chuyển tại kho được phân quyền. Số dương là nhập kho, số âm là xuất kho.</p>
    </div>
    {error && <div role="alert" className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-2 rounded-lg border border-red-300 px-3 font-semibold hover:bg-red-100"><RotateCw className="size-4" />Thử lại</button></div>}
    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none">
      <CardHeader className="gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div><CardTitle className="text-lg">Biến động theo thời gian</CardTitle><p className="mt-1 text-sm text-muted-foreground">Tra theo vật tư, số lô hoặc số chứng từ.</p></div>
        <div className="flex flex-col gap-2 sm:flex-row">
          <label className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" /><input aria-label="Tìm biến động kho" value={search} onChange={(event) => { setSearch(event.target.value); setPage(1); setResult(null) }} placeholder="Vật tư, lô, chứng từ" className="h-11 w-full rounded-xl border border-black/10 bg-white pl-9 pr-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a] sm:w-56" /></label>
          <select aria-label="Lọc chi nhánh" value={branchId} onChange={(event) => { setBranchId(event.target.value); setPage(1); setResult(null) }} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"><option value="">Tất cả chi nhánh được cấp quyền</option>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select>
        </div>
      </CardHeader>
      <CardContent>
        <div className="overflow-x-auto"><table className="w-full min-w-[850px] text-left text-sm">
          <thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3 pr-5 font-medium">Thời điểm</th><th className="py-3 pr-5 font-medium">Vật tư / lô</th><th className="py-3 pr-5 font-medium">Chi nhánh / kho</th><th className="py-3 pr-5 font-medium">Chứng từ</th><th className="py-3 text-right font-medium">Thay đổi</th></tr></thead>
          <tbody>{!loading && result?.data.map((row) => {
            const source = sourceLabel(row)
            const incoming = Number(row.quantity_delta) > 0
            return <tr key={row.id} className="border-b border-black/6 last:border-0">
              <td className="py-4 pr-5 whitespace-nowrap text-muted-foreground">{dateFormat.format(new Date(row.occurred_at))}</td>
              <td className="py-4 pr-5"><p className="font-semibold">{row.product_name}</p><p className="mt-1 text-xs text-muted-foreground">{row.product_code} · Lô {row.lot_no}</p></td>
              <td className="py-4 pr-5">{row.branch_name}<br /><span className="text-muted-foreground">{row.warehouse_name}</span></td>
              <td className="py-4 pr-5"><p className="text-xs text-muted-foreground">{source.type}</p>{source.href ? <Link href={source.href} className="font-semibold text-primary hover:underline">{source.number}</Link> : <span className="font-semibold">{source.number}</span>}</td>
              <td className={`py-4 text-right font-semibold whitespace-nowrap ${incoming ? "text-emerald-700" : "text-amber-800"}`}><span className="inline-flex items-center gap-1">{incoming ? <ArrowDownLeft className="size-4" /> : <ArrowUpRight className="size-4" />}{incoming ? "+" : "−"}{quantityFormat.format(Math.abs(Number(row.quantity_delta)))} {row.unit_name}</span></td>
            </tr>
          })}</tbody>
        </table>
          {loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải lịch sử biến động</span>{[1, 2, 3].map((row) => <Skeleton key={row} className="h-12 w-full" />)}</div>}
          {!loading && !error && result?.data.length === 0 && <div className="py-12 text-center"><History className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Chưa có biến động phù hợp</p><p className="mt-1 text-sm text-muted-foreground">Thử thay đổi từ khóa hoặc chi nhánh.</p></div>}
        </div>
        {result && result.pagination.last_page > 1 && <div className="mt-5 flex items-center justify-end gap-3 text-sm"><button type="button" disabled={page <= 1 || loading} onClick={() => { setPage(page - 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 py-2 hover:bg-[#e9eadf] disabled:opacity-40">Trang trước</button><span>{result.pagination.current_page} / {result.pagination.last_page}</span><button type="button" disabled={page >= result.pagination.last_page || loading} onClick={() => { setPage(page + 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 py-2 hover:bg-[#e9eadf] disabled:opacity-40">Trang sau</button></div>}
      </CardContent>
    </Card>
  </main>
}
