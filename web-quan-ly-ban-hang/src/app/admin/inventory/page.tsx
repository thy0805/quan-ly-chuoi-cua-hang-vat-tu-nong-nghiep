import { Download, Filter, Plus, Search } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { inventory } from "@/lib/mock-data"

const statusVariant = (status: string) => {
  if (status === "Sắp hết") return "destructive" as const
  if (status === "Theo dõi") return "outline" as const
  return "secondary" as const
}

export default function InventoryPage() {
  return (
    <main className="p-5 lg:p-8">
      <div className="flex flex-col justify-between gap-5 lg:flex-row lg:items-end">
        <div>
          <p className="text-sm font-medium text-muted-foreground">Kho và lô hàng</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Tồn kho vật tư</h1>
          <p className="mt-2 text-sm text-muted-foreground">Theo dõi số lượng, số lô và hạn sử dụng tại từng chi nhánh.</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline"><Download className="size-4" /> Xuất dữ liệu</Button>
          <Button className="bg-[#274f3a] hover:bg-[#203d2e]"><Plus className="size-4" /> Nhập vật tư</Button>
        </div>
      </div>

      <div className="mt-7 grid gap-3 sm:grid-cols-3">
        {[
          ["302", "Tổng đơn vị tồn"],
          ["5", "Mặt hàng cần chú ý"],
          ["3", "Chi nhánh có dữ liệu"],
        ].map(([value, label]) => (
          <Card key={label} className="border-black/8 bg-[#fbfaf5] shadow-none">
            <CardContent className="py-5">
              <p className="text-2xl font-semibold tracking-[-0.04em]">{value}</p>
              <p className="mt-1 text-xs text-muted-foreground">{label}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card className="mt-4 border-black/8 bg-[#fbfaf5] shadow-none">
        <CardContent className="p-0">
          <div className="flex flex-col gap-3 border-b border-black/8 p-4 sm:flex-row sm:items-center">
            <div className="relative max-w-md flex-1">
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input aria-label="Tìm kiếm tồn kho" placeholder="Tìm theo mã, tên vật tư hoặc số lô" className="pl-9" />
            </div>
            <Button variant="outline"><Filter className="size-4" /> Bộ lọc</Button>
            <select aria-label="Chọn chi nhánh" className="h-9 rounded-lg border border-input bg-transparent px-3 text-sm">
              <option>Tất cả chi nhánh</option>
              <option>Chi nhánh Trung tâm</option>
              <option>Chi nhánh Bình Chánh</option>
              <option>Chi nhánh Củ Chi</option>
            </select>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[920px] text-left text-sm">
              <thead className="bg-[#f3f1e8] text-xs uppercase tracking-wide text-muted-foreground">
                <tr><th className="px-5 py-4 font-medium">Mã vật tư</th><th className="px-5 py-4 font-medium">Tên vật tư</th><th className="px-5 py-4 font-medium">Chi nhánh</th><th className="px-5 py-4 font-medium">Số lô</th><th className="px-5 py-4 font-medium">Hạn dùng</th><th className="px-5 py-4 text-right font-medium">Tồn kho</th><th className="px-5 py-4 font-medium">Trạng thái</th></tr>
              </thead>
              <tbody>
                {inventory.map((item) => (
                  <tr key={item.sku} className="border-t border-black/6 hover:bg-[#f7f5ed]">
                    <td className="px-5 py-4 font-mono text-xs">{item.sku}</td>
                    <td className="px-5 py-4 font-medium">{item.name}</td>
                    <td className="px-5 py-4 text-muted-foreground">{item.branch}</td>
                    <td className="px-5 py-4">{item.lot}</td>
                    <td className="px-5 py-4">{item.expiry}</td>
                    <td className="px-5 py-4 text-right font-semibold">{item.stock}</td>
                    <td className="px-5 py-4"><Badge variant={statusVariant(item.status)}>{item.status}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="flex items-center justify-between border-t border-black/8 px-5 py-4 text-xs text-muted-foreground">
            <span>Hiển thị 6 mặt hàng minh họa</span>
            <span>Trang 1 / 1</span>
          </div>
        </CardContent>
      </Card>
    </main>
  )
}
