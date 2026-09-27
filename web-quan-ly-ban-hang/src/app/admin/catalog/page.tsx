"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Package, RotateCw, Search } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { CatalogManager } from "@/components/admin/catalog-manager"
import { useAdminProfile } from "@/components/admin/admin-shell"
import { ApiError, apiFetch, type CatalogCategory, type CatalogResponse } from "@/lib/api"

const priceFormat = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 })

export default function CatalogPage() {
  const profile = useAdminProfile()
  const router = useRouter()
  const [search, setSearch] = useState("")
  const [categoryId, setCategoryId] = useState("")
  const [page, setPage] = useState(1)
  const [activeOnly, setActiveOnly] = useState(false)
  const [result, setResult] = useState<CatalogResponse | null>(null)
  const [categories, setCategories] = useState<CatalogCategory[]>([])
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
      if (categoryId) params.set("category_id", categoryId)
      if (activeOnly) params.set("active_only", "1")

      try {
        const data = await apiFetch<CatalogResponse>(`/api/catalog?${params}`, { signal: controller.signal })
        if (!controller.signal.aborted) {
          setResult(data)
          setCategories(data.categories)
        }
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) {
          router.replace("/login")
          return
        }
        setResult(null)
        setError(caught instanceof Error ? caught.message : "Không tải được danh mục vật tư.")
      } finally {
        if (!controller.signal.aborted) setLoading(false)
      }
    }, search ? 250 : 0)

    return () => {
      window.clearTimeout(timer)
      controller.abort()
    }
  }, [activeOnly, categoryId, page, reload, router, search])

  return (
    <main className="p-5 lg:p-8">
      <div>
        <p className="text-sm font-medium text-primary">Danh mục toàn hệ thống</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Vật tư nông nghiệp</h1>
        <p className="mt-2 text-sm text-muted-foreground">Tra cứu nhóm, hoạt chất, đơn vị và giá bán chung. Quyền chỉnh sửa dành cho Chủ chuỗi.</p>
      </div>

      {error && <div role="alert" className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-2 rounded-lg border border-red-300 px-3 font-semibold hover:bg-red-100"><RotateCw className="size-4" />Thử lại</button></div>}
      {profile.user.can_manage_catalog && result && <CatalogManager source={result} onSaved={() => setReload((value) => value + 1)} />}

      <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none">
        <CardHeader className="gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <CardTitle className="text-lg">Danh sách vật tư</CardTitle>
            <p className="mt-1 text-sm text-muted-foreground">Dữ liệu trực tiếp từ PostgreSQL, dùng chung cho mọi chuỗi.</p>
          </div>
          <div className="flex flex-col gap-2 sm:flex-row">
            <label className="relative">
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <input aria-label="Tìm vật tư" value={search} onChange={(event) => { setSearch(event.target.value); setPage(1); setResult(null) }} placeholder="Tên, mã hoặc hoạt chất" className="h-11 w-full rounded-xl border border-black/10 bg-white pl-9 pr-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a] sm:w-60" />
            </label>
            <select aria-label="Lọc nhóm vật tư" value={categoryId} onChange={(event) => { setCategoryId(event.target.value); setPage(1); setResult(null) }} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]">
              <option value="">Tất cả nhóm</option>
              {categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
            </select>
            <label className="flex min-h-11 items-center gap-2 rounded-xl border border-black/10 bg-white px-3 text-sm"><input type="checkbox" checked={activeOnly} onChange={(event) => { setActiveOnly(event.target.checked); setPage(1); setResult(null) }} className="size-4 accent-[#274f3a]" />Chỉ còn dùng</label>
          </div>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[700px] text-left text-sm">
              <thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground">
                <tr><th className="py-3 pr-5 font-medium">Vật tư</th><th className="py-3 pr-5 font-medium">Nhóm</th><th className="py-3 pr-5 font-medium">Hoạt chất</th><th className="py-3 pr-5 font-medium">Đơn vị</th><th className="py-3 pr-5 font-medium">Giá bán</th><th className="py-3 pr-5 font-medium">Thuế</th><th className="py-3 font-medium">Trạng thái</th></tr>
              </thead>
              <tbody>{!loading && result?.data.map((item) => <tr key={item.id} className="border-b border-black/6 last:border-0"><td className="py-4 pr-5"><p className="font-semibold">{item.name}</p><p className="mt-1 text-xs text-muted-foreground">{item.code}</p></td><td className="py-4 pr-5">{item.category_name}</td><td className="py-4 pr-5 text-muted-foreground">{item.active_ingredient || "—"}</td><td className="py-4 pr-5">{item.unit_name}</td><td className="py-4 pr-5 font-semibold tabular-nums">{priceFormat.format(Number(item.sale_price))}</td><td className="py-4 pr-5 tabular-nums">{item.tax_rate === null ? "Chưa cấu hình" : `${item.tax_rate}%`}</td><td className="py-4"><span className={`rounded-full px-2.5 py-1 text-xs font-medium ${item.is_active && item.category_is_active && item.unit_is_active ? "bg-[#e1e5d3] text-[#274f3a]" : "bg-amber-100 text-amber-900"}`}>{item.is_active && item.category_is_active && item.unit_is_active ? "Còn dùng" : "Đã ngừng"}</span></td></tr>)}</tbody>
            </table>
            {loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải danh mục vật tư</span>{[1, 2, 3].map((row) => <Skeleton key={row} className="h-12 w-full" />)}</div>}
            {!loading && !error && result?.data.length === 0 && <div className="py-12 text-center"><Package className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Không có vật tư phù hợp</p><p className="mt-1 text-sm text-muted-foreground">Thử từ khóa hoặc nhóm khác.</p></div>}
          </div>
          {result && <div className="mt-5 flex flex-wrap items-center justify-between gap-3 text-sm text-muted-foreground"><span>{result.pagination.total} vật tư</span>{result.pagination.last_page > 1 && <div className="flex items-center gap-3"><button type="button" disabled={page <= 1 || loading} onClick={() => { setPage(page - 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 py-2 text-foreground hover:bg-[#e9eadf] disabled:opacity-40">Trang trước</button><span>{result.pagination.current_page} / {result.pagination.last_page}</span><button type="button" disabled={page >= result.pagination.last_page || loading} onClick={() => { setPage(page + 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 py-2 text-foreground hover:bg-[#e9eadf] disabled:opacity-40">Trang sau</button></div>}</div>}
        </CardContent>
      </Card>
    </main>
  )
}
