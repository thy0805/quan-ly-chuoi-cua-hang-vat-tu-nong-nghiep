import { SlidersHorizontal } from "lucide-react"
import { ProductCard } from "@/components/shop/product-card"
import { products } from "@/lib/mock-data"

export default function ProductsPage() {
  return (
    <main className="page-shell py-16">
      <div className="grid gap-10 lg:grid-cols-12">
        <div className="lg:col-span-8">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-primary">Danh mục sản phẩm</p>
          <h1 className="mt-4 text-5xl font-semibold tracking-[-0.06em] sm:text-7xl">Vật tư cho từng nhu cầu canh tác.</h1>
        </div>
        <p className="self-end text-base leading-7 text-muted-foreground lg:col-span-4">Tra cứu nhóm hàng, giá tham khảo và tình trạng tồn trước khi chọn mua tại chi nhánh.</p>
      </div>
      <div className="mt-14 flex flex-wrap items-center justify-between gap-4 border-y border-black/10 py-4">
        <div className="flex flex-wrap gap-2">
          {["Tất cả", "Phân bón", "Hạt giống", "Bảo vệ thực vật", "Dụng cụ"].map((item, index) => (
            <button key={item} className={`rounded-full px-4 py-2 text-sm font-medium ${index === 0 ? "bg-[#274f3a] text-white" : "bg-white/60"}`}>{item}</button>
          ))}
        </div>
        <button className="inline-flex items-center gap-2 text-sm font-semibold"><SlidersHorizontal className="size-4" /> Sắp xếp</button>
      </div>
      <div className="mt-10 grid gap-x-6 gap-y-12 sm:grid-cols-2 lg:grid-cols-3">
        {products.map((product) => <ProductCard key={product.slug} product={product} />)}
      </div>
    </main>
  )
}
