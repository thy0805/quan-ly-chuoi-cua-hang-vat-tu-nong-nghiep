"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { AlertTriangle, Boxes, MapPin, RotateCw, Search } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { ApiError, apiFetch, type Branch, type InventoryItem, type InventoryResponse } from "@/lib/api"

const numberFormat = new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 3 })

function statusVariant(status: string): "destructive" | "secondary" | "outline" {
  if (status === "Hết hạn") return "destructive"
  if (status === "Gần hết hạn") return "secondary"
  return "outline"
}

function formatExpiry(value: string | null) {
  if (!value) return "Không có hạn dùng"
  const [year, month, day] = value.slice(0, 10).split("-")
  return `${day}/${month}/${year}`
}

function InventoryRow({ item }: { item: InventoryItem }) {
  return (
    <tr className="border-b border-black/6 last:border-0">
      <td className="py-4 pr-5">
        <p className="font-semibold">{item.product_name}</p>
        <p className="mt-1 text-xs text-muted-foreground">{item.product_code}</p>
      </td>
      <td className="py-4 pr-5 text-muted-foreground">{item.branch_name}<br />{item.warehouse_name}</td>
      <td className="py-4 pr-5">{item.lot_no}</td>
      <td className="py-4 pr-5">{formatExpiry(item.expires_on)}</td>
      <td className="py-4 pr-5 font-medium">{numberFormat.format(Number(item.quantity))} {item.unit_name}</td>
      <td className="py-4"><Badge variant={statusVariant(item.status)}>{item.status}</Badge></td>
    </tr>
  )
}

export default function InventoryPage() {
  const router = useRouter()
  const [search, setSearch] = useState("")
  const [branchId, setBranchId] = useState("")
  const [page, setPage] = useState(1)
  const [result, setResult] = useState<InventoryResponse | null>(null)
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
        const data = await apiFetch<InventoryResponse>(`/api/inventory?${params}`, { signal: controller.signal })
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
        setError(caught instanceof Error ? caught.message : "Không tải được dữ liệu tồn kho.")
      } finally {
        if (!controller.signal.aborted) setLoading(false)
      }
    }, search ? 250 : 0)

    return () => {
      window.clearTimeout(timer)
      controller.abort()
    }
  }, [branchId, page, reload, router, search])

  const metrics = [
    { label: "Dòng tồn kho", value: result?.summary.inventory_rows, icon: Boxes },
    { label: "Lô gần hết hạn", value: result?.summary.expiring_lots, icon: AlertTriangle },
    { label: "Chi nhánh có tồn", value: result?.summary.branches_with_stock, icon: MapPin },
  ]

  return (
    <main className="p-5 lg:p-8">
      <div>
        <p className="text-sm font-medium text-primary">Quản lý kho hàng</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Tồn kho theo lô</h1>
        <p className="mt-2 text-sm text-muted-foreground">Theo dõi số lượng và hạn dùng tại các kho bạn được phân quyền.</p>
      </div>

      {error && <div role="alert" className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-2 rounded-lg border border-red-300 px-3 font-semibold hover:bg-red-100"><RotateCw className="size-4" />Thử lại</button></div>}

      <section className="mt-7 grid gap-4 sm:grid-cols-3">
        {metrics.map(({ label, value, icon: Icon }) => (
          <Card key={label} className="border-black/8 bg-[#fbfaf5] shadow-none">
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
              <span className="grid size-9 place-items-center rounded-xl bg-[#e1e5d3]"><Icon className="size-4 text-primary" /></span>
            </CardHeader>
            <CardContent>{loading && !result ? <Skeleton className="h-9 w-20" /> : <p className="text-3xl font-semibold tracking-[-0.04em]">{value === undefined ? "—" : numberFormat.format(value)}</p>}</CardContent>
          </Card>
        ))}
      </section>

      <Card className="mt-6 border-black/8 bg-[#fbfaf5] shadow-none">
        <CardHeader className="gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <CardTitle className="text-lg">Danh sách tồn kho</CardTitle>
            <p className="mt-1 text-sm text-muted-foreground">Tra theo mã vật tư, tên hoặc số lô. Cận hạn theo vật tư, mặc định 30 ngày nếu chưa cấu hình.</p>
          </div>
          <div className="flex flex-col gap-2 sm:flex-row">
            <label className="relative">
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <input aria-label="Tìm vật tư hoặc số lô" value={search} onChange={(event) => { setSearch(event.target.value); setPage(1); setResult(null) }} placeholder="Tìm vật tư, số lô" className="h-11 w-full rounded-xl border border-black/10 bg-white pl-9 pr-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a] sm:w-56" />
            </label>
            <select aria-label="Lọc chi nhánh" value={branchId} onChange={(event) => { setBranchId(event.target.value); setPage(1); setResult(null) }} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]">
              <option value="">Tất cả chi nhánh được cấp quyền</option>
              {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
            </select>
          </div>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[800px] text-left text-sm">
              <thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground">
                <tr><th className="py-3 pr-5 font-medium">Vật tư</th><th className="py-3 pr-5 font-medium">Chi nhánh / kho</th><th className="py-3 pr-5 font-medium">Số lô</th><th className="py-3 pr-5 font-medium">Hạn dùng</th><th className="py-3 pr-5 font-medium">Số lượng</th><th className="py-3 font-medium">Trạng thái</th></tr>
              </thead>
              <tbody>{!loading && result?.data.map((item) => <InventoryRow key={item.id} item={item} />)}</tbody>
            </table>
            {loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải dữ liệu tồn kho</span>{[1, 2, 3].map((row) => <Skeleton key={row} className="h-12 w-full" />)}</div>}
            {!loading && !error && result?.data.length === 0 && <div className="py-12 text-center"><Boxes className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Không có dòng tồn kho phù hợp</p><p className="mt-1 text-sm text-muted-foreground">Thử thay đổi từ khóa hoặc chi nhánh.</p></div>}
          </div>
          {result && result.pagination.last_page > 1 && (
            <div className="mt-5 flex items-center justify-end gap-3 text-sm">
              <button disabled={page <= 1 || loading} onClick={() => { setPage(page - 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 py-2 hover:bg-[#e9eadf] disabled:opacity-40">Trang trước</button>
              <span>{result.pagination.current_page} / {result.pagination.last_page}</span>
              <button disabled={page >= result.pagination.last_page || loading} onClick={() => { setPage(page + 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 py-2 hover:bg-[#e9eadf] disabled:opacity-40">Trang sau</button>
            </div>
          )}
        </CardContent>
      </Card>
    </main>
  )
}
