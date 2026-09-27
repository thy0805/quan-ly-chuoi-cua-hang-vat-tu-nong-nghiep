"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Building2, RotateCw, Warehouse } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { ApiError, apiFetch, type OrganizationResponse } from "@/lib/api"
import { OrganizationManager } from "@/components/admin/organization-manager"

export default function OrganizationPage() {
  const router = useRouter()
  const [data, setData] = useState<OrganizationResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [reload, setReload] = useState(0)

  useEffect(() => {
    const controller = new AbortController()
    async function load() {
      setLoading(true)
      setError("")
      try {
        const result = await apiFetch<OrganizationResponse>("/api/organization", { signal: controller.signal })
        if (!controller.signal.aborted) setData(result)
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) {
          router.replace("/login")
          return
        }
        setData(null)
        setError(caught instanceof Error ? caught.message : "Không tải được tổ chức.")
      } finally {
        if (!controller.signal.aborted) setLoading(false)
      }
    }
    load()
    return () => controller.abort()
  }, [reload, router])

  return (
    <main className="p-5 lg:p-8">
      <div><p className="text-sm font-medium text-primary">Cơ cấu được phân quyền</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Chuỗi, chi nhánh và kho</h1><p className="mt-2 text-sm text-muted-foreground">Thông tin tổ chức trực tiếp từ PostgreSQL trong phạm vi tài khoản của bạn.</p></div>
      {error && <div role="alert" className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-2 rounded-lg border border-red-300 px-3 font-semibold hover:bg-red-100"><RotateCw className="size-4" />Thử lại</button></div>}
      {loading && <div role="status" className="mt-7 space-y-4"><span className="sr-only">Đang tải tổ chức</span><Skeleton className="h-28 w-full rounded-2xl" /><Skeleton className="h-52 w-full rounded-2xl" /></div>}
      {!loading && data && <>
        <OrganizationManager data={data} onSaved={() => setReload((value) => value + 1)} />
        <section className="mt-7 grid gap-4 sm:grid-cols-2"><Card className="border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader className="flex flex-row items-center justify-between"><CardTitle className="text-sm font-medium text-muted-foreground">Chuỗi trong phạm vi</CardTitle><Building2 className="size-5 text-primary" /></CardHeader><CardContent><p className="text-3xl font-semibold">{data.chains.length}</p></CardContent></Card><Card className="border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader className="flex flex-row items-center justify-between"><CardTitle className="text-sm font-medium text-muted-foreground">Kho được xem</CardTitle><Warehouse className="size-5 text-primary" /></CardHeader><CardContent><p className="text-3xl font-semibold">{data.warehouses.length}</p></CardContent></Card></section>
        {data.chains.length === 0 && <div className="mt-6 rounded-2xl border border-black/8 bg-[#fbfaf5] p-10 text-center text-sm text-muted-foreground">Không có chuỗi trong phạm vi được phân quyền.</div>}
        <div className="mt-6 space-y-5">{data.chains.map((chain) => <Card key={chain.id} className="border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader className="gap-2 sm:flex-row sm:items-center sm:justify-between"><div><CardTitle className="text-xl">{chain.name}</CardTitle><p className="mt-1 text-sm text-muted-foreground">{data.branches.filter((branch) => branch.chain_id === chain.id).length} chi nhánh được xem</p></div><span className={`w-fit rounded-full px-3 py-1 text-xs font-medium ${chain.is_active ? "bg-[#e1e5d3] text-[#274f3a]" : "bg-amber-100 text-amber-900"}`}>{chain.is_active ? "Đang hoạt động" : "Ngừng hoạt động"}</span></CardHeader><CardContent className="space-y-3">{data.branches.filter((branch) => branch.chain_id === chain.id).map((branch) => { const warehouses = data.warehouses.filter((warehouse) => warehouse.branch_id === branch.id); return <div key={branch.id} className="rounded-xl border border-black/8 bg-white p-4"><div className="flex flex-wrap items-start justify-between gap-2"><div><p className="font-semibold">{branch.name} <span className="ml-1 text-xs font-normal text-muted-foreground">{branch.code}</span></p><p className="mt-1 text-sm text-muted-foreground">{branch.address || "Chưa có địa chỉ"}</p></div><span className={`rounded-full px-2.5 py-1 text-xs ${branch.is_active ? "bg-[#e1e5d3] text-[#274f3a]" : "bg-amber-100 text-amber-900"}`}>{branch.is_active ? "Đang hoạt động" : "Ngừng hoạt động"}</span></div><div className="mt-4 grid gap-2 sm:grid-cols-2">{warehouses.map((warehouse) => <div key={warehouse.id} className="flex items-start gap-2 rounded-lg bg-[#f3f1e8] p-3 text-sm"><Warehouse className="mt-0.5 size-4 shrink-0 text-primary" /><div><p className="font-medium">{warehouse.name}</p><p className="text-xs text-muted-foreground">{warehouse.code} · {warehouse.warehouse_type}{branch.default_sales_warehouse_id === warehouse.id ? " · Kho bán mặc định" : ""}</p></div></div>)}</div>{warehouses.length === 0 && <p className="mt-3 text-sm text-muted-foreground">Chi nhánh chưa có kho trong dữ liệu hiện tại.</p>}</div> })}</CardContent></Card>)}</div>
      </>}
    </main>
  )
}
