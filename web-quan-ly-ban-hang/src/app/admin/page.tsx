import Link from "next/link"
import { AlertTriangle, ArrowRight, Banknote, Boxes, ClipboardCheck, TrendingUp } from "lucide-react"
import { RevenueChart } from "@/components/admin/revenue-chart"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { inventory } from "@/lib/mock-data"

const metrics = [
  { label: "Doanh thu tháng", value: "648,2 tr", detail: "+9,8% so với tháng trước", icon: Banknote },
  { label: "Đơn đã hoàn tất", value: "326", detail: "18 đơn trong hôm nay", icon: ClipboardCheck },
  { label: "Giá trị tồn kho", value: "1,24 tỷ", detail: "3 chi nhánh đang hoạt động", icon: Boxes },
  { label: "Lợi nhuận dự kiến", value: "236,4 tr", detail: "36,5% trên doanh thu", icon: TrendingUp },
]

export default function AdminPage() {
  return (
    <main className="p-5 lg:p-8">
      <div className="flex flex-col justify-between gap-5 sm:flex-row sm:items-end">
        <div>
          <p className="text-sm font-medium text-muted-foreground">Thứ bảy, 12 tháng 09 năm 2026</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Tổng quan vận hành</h1>
        </div>
        <button className="h-10 rounded-xl bg-[#274f3a] px-4 text-sm font-semibold text-white">Tạo báo cáo</button>
      </div>

      <section className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {metrics.map(({ label, value, detail, icon: Icon }) => (
          <Card key={label} className="border-black/8 bg-[#fbfaf5] shadow-none">
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
              <span className="grid size-9 place-items-center rounded-xl bg-[#e1e5d3]"><Icon className="size-4 text-primary" /></span>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-semibold tracking-[-0.04em]">{value}</p>
              <p className="mt-2 text-xs text-muted-foreground">{detail}</p>
            </CardContent>
          </Card>
        ))}
      </section>

      <section className="mt-4 grid gap-4 xl:grid-cols-12">
        <Card className="border-black/8 bg-[#fbfaf5] shadow-none xl:col-span-8">
          <CardHeader className="flex flex-row items-start justify-between">
            <div>
              <CardTitle className="text-lg">Doanh thu và chi phí</CardTitle>
              <p className="mt-1 text-sm text-muted-foreground">Số liệu minh họa trong 6 tháng gần nhất</p>
            </div>
            <Badge variant="outline">Toàn chuỗi</Badge>
          </CardHeader>
          <CardContent><RevenueChart /></CardContent>
        </Card>
        <Card className="border-black/8 bg-[#fbfaf5] shadow-none xl:col-span-4">
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle className="text-lg">Cần xử lý</CardTitle>
              <span className="grid size-8 place-items-center rounded-full bg-amber-100"><AlertTriangle className="size-4 text-amber-700" /></span>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {[
              ["2 phiếu nhập", "Đang chờ duyệt"],
              ["5 mặt hàng", "Sắp hết tồn kho"],
              ["3 lô hàng", "Sắp hết hạn"],
              ["4 khoản nợ", "Đến hạn thu"],
            ].map(([value, label]) => (
              <div key={label} className="flex items-center justify-between border-b border-black/8 pb-4 last:border-0">
                <div><p className="text-sm font-semibold">{value}</p><p className="text-xs text-muted-foreground">{label}</p></div>
                <ArrowRight className="size-4 text-muted-foreground" />
              </div>
            ))}
          </CardContent>
        </Card>
      </section>

      <Card className="mt-4 border-black/8 bg-[#fbfaf5] shadow-none">
        <CardHeader className="flex flex-row items-center justify-between">
          <div><CardTitle className="text-lg">Tồn kho cần chú ý</CardTitle><p className="mt-1 text-sm text-muted-foreground">Ưu tiên kiểm tra tại các chi nhánh</p></div>
          <Link href="/admin/inventory" className="inline-flex items-center gap-2 text-sm font-semibold text-primary">Xem toàn bộ <ArrowRight className="size-4" /></Link>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3 font-medium">Mặt hàng</th><th className="py-3 font-medium">Chi nhánh</th><th className="py-3 font-medium">Số lô</th><th className="py-3 font-medium">Tồn</th><th className="py-3 font-medium">Trạng thái</th></tr></thead>
            <tbody>
              {inventory.slice(2, 5).map((item) => (
                <tr key={item.sku} className="border-b border-black/6 last:border-0">
                  <td className="py-4 font-medium">{item.name}</td><td className="py-4 text-muted-foreground">{item.branch}</td><td className="py-4">{item.lot}</td><td className="py-4">{item.stock}</td><td className="py-4"><Badge variant={item.status === "Sắp hết" ? "destructive" : "secondary"}>{item.status}</Badge></td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>
    </main>
  )
}
