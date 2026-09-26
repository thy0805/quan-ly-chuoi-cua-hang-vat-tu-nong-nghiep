import Image from "next/image"
import Link from "next/link"
import { ArrowLeft, ArrowRight, Minus, Plus, Trash2 } from "lucide-react"
import { formatMoney, products } from "@/lib/mock-data"

export default function CartPage() {
  const cartItems = products.slice(0, 2)
  const subtotal = cartItems.reduce((sum, item) => sum + item.price, 0)

  return (
    <main className="page-shell py-12">
      <Link href="/shop/products" className="inline-flex items-center gap-2 text-sm font-semibold"><ArrowLeft className="size-4" /> Tiếp tục chọn hàng</Link>
      <h1 className="mt-8 text-5xl font-semibold tracking-[-0.06em] sm:text-7xl">Giỏ hàng của bạn</h1>
      <div className="mt-12 grid gap-12 lg:grid-cols-12">
        <section className="lg:col-span-8">
          {cartItems.map((item) => (
            <article key={item.slug} className="grid grid-cols-[110px_1fr] gap-5 border-t border-black/10 py-6 sm:grid-cols-[140px_1fr_auto]">
              <div className="relative aspect-square overflow-hidden rounded-2xl bg-[#e8e1cf]">
                <Image src={item.image} alt={item.name} fill className="object-cover" sizes="140px" />
              </div>
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">{item.category}</p>
                <h2 className="mt-2 text-lg font-semibold">{item.name}</h2>
                <p className="mt-1 text-sm text-muted-foreground">{item.unit}</p>
                <div className="mt-5 flex items-center gap-4">
                  <div className="flex h-9 items-center rounded-full border border-black/12 bg-white">
                    <button aria-label="Giảm số lượng" className="grid size-9 place-items-center"><Minus className="size-3" /></button>
                    <span className="w-7 text-center text-xs font-semibold">1</span>
                    <button aria-label="Tăng số lượng" className="grid size-9 place-items-center"><Plus className="size-3" /></button>
                  </div>
                  <button aria-label="Xóa sản phẩm" className="text-muted-foreground hover:text-destructive"><Trash2 className="size-4" /></button>
                </div>
              </div>
              <p className="col-start-2 font-semibold sm:col-start-auto">{formatMoney(item.price)}</p>
            </article>
          ))}
        </section>
        <aside className="h-fit rounded-[1.75rem] bg-[#e1e5d3] p-7 lg:col-span-4">
          <h2 className="text-2xl font-semibold tracking-[-0.04em]">Tóm tắt đơn hàng</h2>
          <div className="mt-7 space-y-4 text-sm">
            <div className="flex justify-between"><span className="text-muted-foreground">Tạm tính</span><span>{formatMoney(subtotal)}</span></div>
            <div className="flex justify-between"><span className="text-muted-foreground">Phí giao hàng</span><span>Xác nhận sau</span></div>
            <div className="flex justify-between border-t border-black/10 pt-4 text-base font-semibold"><span>Tổng dự kiến</span><span>{formatMoney(subtotal)}</span></div>
          </div>
          <button className="mt-8 inline-flex h-12 w-full items-center justify-center gap-3 rounded-full bg-[#274f3a] text-sm font-semibold text-white">Tiếp tục đặt hàng <ArrowRight className="size-4" /></button>
          <p className="mt-4 text-xs leading-5 text-muted-foreground">Giá, tồn kho và chi nhánh giao hàng sẽ được xác nhận trước khi duyệt đơn.</p>
        </aside>
      </div>
    </main>
  )
}
