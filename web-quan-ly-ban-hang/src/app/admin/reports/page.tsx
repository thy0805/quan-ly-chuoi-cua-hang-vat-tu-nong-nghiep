"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { ArrowUpRight, BarChart3, RotateCw } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"
import { useAdminProfile } from "@/components/admin/admin-shell"
import { ApiError, apiFetch } from "@/lib/api"

type Metrics = {
  invoice_count: number
  gross_sales: string
  total_discount: string
  net_sales: string
  total_tax: string
  invoice_total: string
  cogs: string | null
  gross_profit: string | null
  amount_collected: string
  receivable_remaining: string
  incomplete_cost_count: number
  incomplete_tax_count: number
  invoice_mismatch_count: number
}
type Report = {
  period: "day" | "month" | "year"
  date: string
  chain_id: string
  timezone: string
  summary: Metrics
  by_branch: { branch_id: string; branch_name: string; metrics: Metrics }[]
  trend: { bucket: string; metrics: Metrics }[]
}

const currency = (value: string | null) => {
  if (value === null) return "Chưa đủ dữ liệu"
  const [whole, fraction = ""] = value.split(".")
  const integer = new Intl.NumberFormat("vi-VN").format(BigInt(whole))
  return `${integer}${fraction && fraction !== "00" ? `,${fraction}` : ""} ₫`
}
const inputClass = "mt-2 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"
const today = () => new Date().toLocaleDateString("sv-SE", { timeZone: "Asia/Ho_Chi_Minh" })

export default function ReportsPage() {
  const router = useRouter()
  const profile = useAdminProfile()
  const [period, setPeriod] = useState<Report["period"]>("month")
  const [date, setDate] = useState(today)
  const [chainId, setChainId] = useState(() => profile.report_chains[0]?.id ?? "")
  const [branchId, setBranchId] = useState("")
  const [result, setResult] = useState<Report | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [reload, setReload] = useState(0)

  useEffect(() => {
    const controller = new AbortController()
    const params = new URLSearchParams({ period, date, chain_id: chainId })
    if (branchId) params.set("branch_id", branchId)
    async function load() {
      setLoading(true)
      setError("")
      try {
        const data = await apiFetch<Report>(`/api/reports/sales?${params}`, { signal: controller.signal })
        if (!controller.signal.aborted) setResult(data)
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setResult(null)
        setError(caught instanceof Error ? caught.message : "Không tải được báo cáo bán hàng.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }
    load()
    return () => controller.abort()
  }, [period, date, chainId, branchId, reload, router])

  const value = period === "day" ? date : period === "month" ? date.slice(0, 7) : date.slice(0, 4)
  const visibleBranches = profile.branches.filter((branch) => branch.chain_id === chainId)
  const cards = result ? [
    { label: "Doanh thu thuần trước thuế", value: result.summary.net_sales, note: "Doanh số gốc trừ chiết khấu", accent: true },
    { label: "Lợi nhuận gộp", value: result.summary.gross_profit, note: "Doanh thu thuần trừ giá vốn snapshot", accent: true },
    { label: "Tổng hóa đơn", value: result.summary.invoice_total, note: "Doanh thu thuần cộng thuế" },
    { label: "Còn phải thu", value: result.summary.receivable_remaining, note: "Tổng hóa đơn trừ tiền đã thu" },
  ] : []

  return <main className="p-5 lg:p-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Báo cáo bán hàng</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Hiệu quả kinh doanh</h1><p className="mt-2 max-w-3xl text-sm leading-6 text-muted-foreground">Tính từ đơn đã xác nhận và hóa đơn thật trong phạm vi bạn được phân quyền. Kỳ báo cáo theo giờ Việt Nam.</p></div><button type="button" onClick={() => setReload((current) => current + 1)} disabled={loading} className="inline-flex min-h-11 items-center gap-2 rounded-xl border border-black/10 bg-white px-4 text-sm font-semibold disabled:opacity-50"><RotateCw className="size-4" />Làm mới</button></div>

    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardContent className="grid gap-4 pt-6 sm:grid-cols-2 xl:grid-cols-4"><label className="text-sm font-medium">Chuỗi<select value={chainId} onChange={(event) => { setChainId(event.target.value); setBranchId("") }} className={inputClass}>{profile.report_chains.map((chain) => <option key={chain.id} value={chain.id}>{chain.name}</option>)}</select></label><label className="text-sm font-medium">Kỳ báo cáo<select value={period} onChange={(event) => setPeriod(event.target.value as Report["period"])} className={inputClass}><option value="day">Theo ngày</option><option value="month">Theo tháng</option><option value="year">Theo năm</option></select></label><label className="text-sm font-medium">{period === "day" ? "Ngày" : period === "month" ? "Tháng" : "Năm"}<input type={period === "day" ? "date" : period === "month" ? "month" : "number"} min={period === "year" ? 2000 : undefined} max={period === "year" ? 2100 : undefined} value={value} onChange={(event) => setDate(period === "day" ? event.target.value : period === "month" ? `${event.target.value}-01` : `${event.target.value}-01-01`)} className={inputClass} /></label><label className="text-sm font-medium">Chi nhánh<select value={branchId} onChange={(event) => setBranchId(event.target.value)} className={inputClass}><option value="">Toàn chuỗi được xem</option>{visibleBranches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label></CardContent></Card>
    {error && <p role="alert" className="mt-5 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</p>}
    {loading && <div role="status" className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><span className="sr-only">Đang tải báo cáo</span>{[1, 2, 3, 4].map((item) => <Skeleton key={item} className="h-36 rounded-2xl" />)}</div>}
    {!loading && result && <>
      {result.summary.incomplete_cost_count > 0 && <p role="alert" className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">{result.summary.incomplete_cost_count} hóa đơn thiếu snapshot giá vốn. Giá vốn và lợi nhuận gộp được để trống để tránh báo cáo sai.</p>}
      {result.summary.incomplete_tax_count > 0 && <p role="alert" className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">{result.summary.incomplete_tax_count} hóa đơn thiếu snapshot thuế. Thuế, tổng hóa đơn và số còn phải thu được để trống để tránh báo cáo sai.</p>}
      {result.summary.invoice_mismatch_count > 0 && <p role="alert" className="mt-4 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">{result.summary.invoice_mismatch_count} hóa đơn có tổng lưu khác tổng tính từ dòng bán. Cần đối soát chứng từ trước khi sử dụng báo cáo.</p>}
      <section aria-label="Chỉ tiêu chính" className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{cards.map((card) => <Card key={card.label} className={`border-black/8 shadow-none ${card.accent ? "bg-[#e1e5d3]" : "bg-[#fbfaf5]"}`}><CardHeader><CardTitle className="flex items-start justify-between gap-2 text-sm font-medium text-muted-foreground">{card.label}<ArrowUpRight className="size-4 shrink-0 text-primary" /></CardTitle></CardHeader><CardContent><p className="break-words text-2xl font-semibold tracking-[-0.04em] tabular-nums lg:text-3xl">{currency(card.value)}</p><p className="mt-2 text-xs text-muted-foreground">{card.note}</p></CardContent></Card>)}</section>
      <div className="mt-6 grid gap-5 xl:grid-cols-[1fr_1.2fr]"><Card className="border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="flex items-center gap-2 text-lg"><BarChart3 className="size-5 text-primary" />Cấu phần doanh thu</CardTitle><p className="text-sm text-muted-foreground">{result.summary.invoice_count} hóa đơn hợp lệ trong kỳ</p></CardHeader><CardContent className="space-y-3 text-sm">{[["Doanh số gốc", result.summary.gross_sales], ["Chiết khấu", result.summary.total_discount], ["Doanh thu thuần", result.summary.net_sales], ["Thuế", result.summary.total_tax], ["Giá vốn snapshot", result.summary.cogs], ["Tiền đã thu", result.summary.amount_collected]].map(([label, amount]) => <div key={label} className="flex items-start justify-between gap-4 border-b border-black/8 pb-3 last:border-0"><span className="text-muted-foreground">{label}</span><strong className="text-right tabular-nums">{currency(amount)}</strong></div>)}</CardContent></Card><Card className="border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="text-lg">So sánh chi nhánh</CardTitle><p className="text-sm text-muted-foreground">Theo chi nhánh của giao dịch bán, trong phạm vi đang xem.</p></CardHeader><CardContent>{result.by_branch.length === 0 ? <p className="py-10 text-center text-sm text-muted-foreground">Chưa có hóa đơn bán được xác nhận trong kỳ này.</p> : <div className="overflow-x-auto"><table className="w-full min-w-[570px] text-left text-sm"><thead className="border-b border-black/10 text-xs uppercase text-muted-foreground"><tr><th className="py-3">Chi nhánh</th><th className="text-right">Hóa đơn</th><th className="text-right">Doanh thu thuần</th><th className="text-right">Lợi nhuận gộp</th></tr></thead><tbody>{result.by_branch.map((row) => <tr key={row.branch_id} className="border-b border-black/6 last:border-0"><td className="py-4 font-medium">{row.branch_name}</td><td className="text-right tabular-nums">{row.metrics.invoice_count}</td><td className="text-right tabular-nums">{currency(row.metrics.net_sales)}</td><td className="text-right tabular-nums">{currency(row.metrics.gross_profit)}</td></tr>)}</tbody></table></div>}</CardContent></Card></div>
      <Card className="mt-6 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="text-lg">Diễn biến trong kỳ</CardTitle><p className="text-sm text-muted-foreground">{period === "day" ? "Theo giờ xác nhận" : period === "month" ? "Theo ngày xác nhận" : "Theo tháng xác nhận"} · Asia/Ho_Chi_Minh</p></CardHeader><CardContent>{result.trend.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Chưa có giao dịch phù hợp.</p> : <div className="overflow-x-auto"><table className="w-full min-w-[650px] text-left text-sm"><thead className="border-b border-black/10 text-xs uppercase text-muted-foreground"><tr><th className="py-3">Mốc</th><th className="text-right">Hóa đơn</th><th className="text-right">Doanh thu thuần</th><th className="text-right">Đã thu</th><th className="text-right">Còn phải thu</th></tr></thead><tbody>{result.trend.map((row) => <tr key={row.bucket} className="border-b border-black/6 last:border-0"><td className="py-3 font-medium">{row.bucket}</td><td className="text-right tabular-nums">{row.metrics.invoice_count}</td><td className="text-right tabular-nums">{currency(row.metrics.net_sales)}</td><td className="text-right tabular-nums">{currency(row.metrics.amount_collected)}</td><td className="text-right tabular-nums">{currency(row.metrics.receivable_remaining)}</td></tr>)}</tbody></table></div>}</CardContent></Card>
      <p className="mt-5 text-xs leading-5 text-muted-foreground">Lợi nhuận hiển thị là lợi nhuận gộp trước chi phí vận hành. Tiền đã thu là khoản thanh toán hợp lệ của các hóa đơn trong kỳ bán, kể cả khoản thu sau ngày xác nhận.</p>
    </>}
  </main>
}
