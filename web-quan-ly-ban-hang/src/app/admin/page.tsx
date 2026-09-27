import { cookies } from "next/headers"
import { redirect } from "next/navigation"
import Link from "next/link"
import { AlertTriangle, ArrowRight, Boxes, MapPin, TrendingUp, Wallet, ReceiptText, CircleDollarSign } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import type { InventoryResponse, Profile } from "@/lib/api"
import { formatVnd } from "@/lib/money"

const numberFormat = new Intl.NumberFormat("vi-VN", { maximumFractionDigits: 3 })
const formatExpiry = (value: string | null) => value ? new Intl.DateTimeFormat("vi-VN").format(new Date(`${value.slice(0, 10)}T00:00:00`)) : "Không áp dụng"
type ReportSummary = {
  invoice_count: number
  net_sales: string
  gross_profit: string | null
  invoice_total: string | null
  amount_collected: string
  receivable_remaining: string | null
  incomplete_cost_count: number
  incomplete_tax_count: number
  invoice_mismatch_count: number
}
type SalesReport = { summary: ReportSummary }
const money = (value: string | null) => {
  if (value === null) return "Chưa đủ dữ liệu"
  return formatVnd(value)
}

async function inventoryOverview(): Promise<InventoryResponse | null> {
  const session = (await cookies()).get("klcn186_api_session")
  if (!session) redirect("/login")
  let response: Response
  try {
    response = await fetch(`${process.env.API_URL ?? "http://127.0.0.1:8000"}/api/inventory?per_page=5`, {
      headers: {
        Accept: "application/json",
        Origin: "http://127.0.0.1:3210",
        Cookie: `klcn186_api_session=${encodeURIComponent(session.value)}`,
      },
      cache: "no-store",
    })
  } catch {
    return null
  }
  if (response.status === 401) redirect("/login")
  if (!response.ok) return null
  return await response.json() as InventoryResponse
}

async function reportOverview(): Promise<SalesReport | "forbidden" | "multi_chain" | null> {
  const session = (await cookies()).get("klcn186_api_session")
  if (!session) redirect("/login")
  try {
    const headers = {
      Accept: "application/json",
      Origin: "http://127.0.0.1:3210",
      Cookie: `klcn186_api_session=${encodeURIComponent(session.value)}`,
    }
    const profileResponse = await fetch(`${process.env.API_URL ?? "http://127.0.0.1:8000"}/api/me`, { headers, cache: "no-store" })
    if (profileResponse.status === 401) redirect("/login")
    if (!profileResponse.ok) return null
    const profile = await profileResponse.json() as Profile
    if (!profile.user.can_view_reports) return "forbidden"
    if (profile.report_chains.length !== 1) return "multi_chain"
    const date = new Date().toLocaleDateString("sv-SE", { timeZone: "Asia/Ho_Chi_Minh" })
    const params = new URLSearchParams({ period: "month", date, chain_id: profile.report_chains[0].id })
    const response = await fetch(`${process.env.API_URL ?? "http://127.0.0.1:8000"}/api/reports/sales?${params}`, { headers, cache: "no-store" })
    if (response.status === 401) redirect("/login")
    if (response.status === 403) return "forbidden"
    if (!response.ok) return null
    return await response.json() as SalesReport
  } catch (error) {
    if (error && typeof error === "object" && "digest" in error) throw error
    return null
  }
}

export default async function AdminPage() {
  const [inventory, report] = await Promise.all([inventoryOverview(), reportOverview()])
  const metrics = inventory ? [
    { label: "Dòng tồn kho", value: inventory.summary.inventory_rows, icon: Boxes },
    { label: "Lô gần hết hạn", value: inventory.summary.expiring_lots, icon: AlertTriangle },
    { label: "Chi nhánh có tồn", value: inventory.summary.branches_with_stock, icon: MapPin },
  ] : []
  const reportCards = report && report !== "forbidden" && report !== "multi_chain" ? [
    { label: "Doanh thu thuần", value: report.summary.net_sales, icon: TrendingUp },
    { label: "Lợi nhuận gộp", value: report.summary.gross_profit, icon: CircleDollarSign },
    { label: "Tiền đã thu", value: report.summary.amount_collected, icon: Wallet },
    { label: "Còn phải thu", value: report.summary.receivable_remaining, icon: ReceiptText },
  ] : []

  return (
    <main className="p-5 lg:p-8">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div><p className="text-sm font-medium text-primary">Tổng quan theo quyền truy cập</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Tình hình kho hàng</h1><p className="mt-2 text-sm text-muted-foreground">Số liệu tồn kho hiện tại từ các chi nhánh bạn được phân quyền.</p></div>
        <Link href="/admin/inventory" className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white hover:bg-[#203d2e]">Xem tồn kho <ArrowRight className="size-4" /></Link>
      </div>

      {!inventory ? <div role="alert" className="mt-7 rounded-2xl border border-red-200 bg-red-50 p-6 text-sm text-red-800">Không tải được số liệu kho. <a href="/admin" className="font-semibold underline underline-offset-4">Thử lại</a></div> : (
        <>
          <section className="mt-7 grid gap-4 sm:grid-cols-3">
            {metrics.map(({ label, value, icon: Icon }) => <Card key={label} className="border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader className="flex flex-row items-center justify-between"><CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle><span className="grid size-9 place-items-center rounded-xl bg-[#e1e5d3]"><Icon className="size-4 text-primary" /></span></CardHeader><CardContent><p className="text-3xl font-semibold tracking-[-0.04em]">{numberFormat.format(value)}</p></CardContent></Card>)}
          </section>
          <Card className="mt-6 border-black/8 bg-[#fbfaf5] shadow-none">
            <CardHeader className="flex flex-row items-center justify-between gap-4"><div><CardTitle className="text-lg">Một số dòng tồn kho</CardTitle><p className="mt-1 text-sm text-muted-foreground">Tối đa 5 dòng đầu theo tên vật tư; xem danh sách đầy đủ để lọc theo chi nhánh.</p></div><Link href="/admin/inventory" className="text-sm font-semibold text-primary hover:underline">Xem tất cả</Link></CardHeader>
            <CardContent>{inventory.data.length === 0 ? <div className="py-10 text-center text-sm text-muted-foreground">Chưa có dòng tồn kho trong phạm vi được phân quyền.</div> : <div className="overflow-x-auto"><table className="w-full min-w-[700px] text-left text-sm"><thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3 font-medium">Vật tư</th><th className="py-3 font-medium">Chi nhánh / kho</th><th className="py-3 font-medium">Số lô</th><th className="py-3 font-medium">Số lượng</th><th className="py-3 font-medium">Hạn dùng</th></tr></thead><tbody>{inventory.data.map((item) => <tr key={item.id} className="border-b border-black/6 last:border-0"><td className="py-4 font-semibold">{item.product_name}</td><td className="py-4 text-muted-foreground">{item.branch_name}<br />{item.warehouse_name}</td><td className="py-4">{item.lot_no}</td><td className="py-4">{numberFormat.format(Number(item.quantity))} {item.unit_name}</td><td className="py-4"><span className="mr-2">{formatExpiry(item.expires_on)}</span><Badge variant={item.status === "Hết hạn" ? "destructive" : "outline"}>{item.status}</Badge></td></tr>)}</tbody></table></div>}</CardContent>
          </Card>
        </>
      )}
      {report !== "forbidden" && <section className="mt-8" aria-labelledby="sales-overview-title">
        <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Báo cáo trực tiếp</p><h2 id="sales-overview-title" className="mt-1 text-2xl font-semibold tracking-[-0.04em]">Kết quả bán hàng tháng này</h2><p className="mt-1 text-sm text-muted-foreground">Theo ngày xác nhận ở Việt Nam, trong các chi nhánh bạn được xem.</p></div><Link href="/admin/reports" className="inline-flex min-h-10 items-center gap-2 rounded-full bg-[#274f3a] px-4 text-sm font-semibold text-white">Mở báo cáo <ArrowRight className="size-4" /></Link></div>
        {report === "multi_chain" ? <p className="mt-5 rounded-2xl border border-black/10 bg-[#fbfaf5] p-5 text-sm text-muted-foreground">Bạn có quyền ở nhiều chuỗi. Mở báo cáo và chọn một chuỗi để xem số liệu chính xác.</p> : !report ? <p role="alert" className="mt-5 rounded-2xl border border-red-200 bg-red-50 p-5 text-sm text-red-800">Không tải được báo cáo bán hàng. <a href="/admin" className="font-semibold underline underline-offset-4">Thử lại</a></p> : <>
          {(report.summary.incomplete_cost_count > 0 || report.summary.incomplete_tax_count > 0 || report.summary.invoice_mismatch_count > 0) && <p role="alert" className="mt-5 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">Có chứng từ thiếu snapshot hoặc tổng hóa đơn không khớp. Mở báo cáo để xem chi tiết trước khi sử dụng số liệu.</p>}
          <div className="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">{reportCards.map(({ label, value, icon: Icon }) => <Card key={label} className="border-black/8 bg-[#e1e5d3] shadow-none"><CardHeader className="flex flex-row items-center justify-between"><CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle><Icon className="size-4 text-primary" /></CardHeader><CardContent><p className="break-words text-2xl font-semibold tracking-[-0.04em] tabular-nums">{money(value)}</p></CardContent></Card>)}</div>
          <p className="mt-3 text-xs text-muted-foreground">{report.summary.invoice_count} hóa đơn đã xác nhận · Doanh thu và lợi nhuận gộp chưa gồm thuế; tiền đã thu được trình bày riêng.</p>
        </>}
      </section>}
    </main>
  )
}
