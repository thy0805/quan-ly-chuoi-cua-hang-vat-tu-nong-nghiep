"use client"

import Image from "next/image"
import Link from "next/link"
import { ArrowLeft, Minus, Plus, ShoppingBag, Trash2 } from "lucide-react"
import { useCart } from "@/components/shop/cart-context"
import { formatMoney, products } from "@/lib/mock-data"

export default function CartPage() {
  const { items, ready, update, remove } = useCart()
  const cartItems = items.flatMap((item) => {
    const product = products.find((entry) => entry.slug === item.slug)
    return product ? [{ product, quantity: item.quantity }] : []
  })
  const subtotal = cartItems.reduce((sum, item) => sum + item.product.price * item.quantity, 0)
  const count = cartItems.reduce((sum, item) => sum + item.quantity, 0)

  return (
    <main className="page-shell py-12">
      <Link href="/shop/products" className="inline-flex items-center gap-2 text-sm font-semibold"><ArrowLeft className="size-4" /> Tiếp tục chọn hàng</Link>
      <h1 className="mt-8 text-5xl font-semibold tracking-[-0.06em] sm:text-7xl">Giỏ hàng của bạn</h1>
      <p className="mt-4 max-w-2xl text-sm leading-6 text-muted-foreground">Danh sách tham khảo được lưu trên trình duyệt này. Giá chỉ để minh họa; cửa hàng chưa công khai tồn kho hay nhận đặt hàng trực tuyến.</p>
      {!ready ? <div role="status" className="mt-12 rounded-2xl bg-white/70 p-8 text-sm text-muted-foreground">Đang tải giỏ hàng...</div> : cartItems.length === 0 ? (
        <div className="mt-12 flex min-h-72 flex-col items-center justify-center rounded-[1.75rem] border border-black/10 bg-white/65 p-8 text-center">
          <ShoppingBag className="size-10 text-primary" />
          <h2 className="mt-5 text-2xl font-semibold">Giỏ hàng đang trống</h2>
          <p className="mt-2 text-sm text-muted-foreground">Chọn vật tư để xem tổng tiền tham khảo.</p>
          <Link href="/shop/products" className="mt-6 inline-flex min-h-11 items-center rounded-full bg-[#274f3a] px-6 text-sm font-semibold text-white">Xem sản phẩm</Link>
        </div>
      ) : (
        <div className="mt-12 grid gap-10 lg:grid-cols-12">
          <section aria-label="Sản phẩm trong giỏ" className="lg:col-span-8">
            {cartItems.map(({ product, quantity }) => (
              <article key={product.slug} className="grid grid-cols-[96px_1fr] gap-4 border-t border-black/10 py-6 sm:grid-cols-[140px_1fr_auto] sm:gap-5">
                <Link href={`/shop/products/${product.slug}`} className="relative aspect-square overflow-hidden rounded-2xl bg-[#e8e1cf]">
                  <Image src={product.image} alt={`Ảnh minh họa: ${product.name}`} fill className="object-cover" sizes="140px" />
                </Link>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">{product.category}</p>
                  <Link href={`/shop/products/${product.slug}`} className="mt-2 block text-lg font-semibold">{product.name}</Link>
                  <p className="mt-1 text-sm text-muted-foreground">{product.unit}</p>
                  <div className="mt-4 flex items-center gap-4">
                    <div className="flex h-10 items-center rounded-full border border-black/12 bg-white">
                      <button type="button" aria-label={`Giảm số lượng ${product.name}`} disabled={quantity <= 1} onClick={() => update(product.slug, quantity - 1)} className="grid size-10 place-items-center rounded-full disabled:opacity-35"><Minus className="size-3" /></button>
                      <output className="w-7 text-center text-xs font-semibold">{quantity}</output>
                      <button type="button" aria-label={`Tăng số lượng ${product.name}`} disabled={quantity >= 99} onClick={() => update(product.slug, quantity + 1)} className="grid size-10 place-items-center rounded-full disabled:opacity-35"><Plus className="size-3" /></button>
                    </div>
                    <button type="button" aria-label={`Xóa ${product.name} khỏi giỏ`} onClick={() => remove(product.slug)} className="grid size-10 place-items-center rounded-full text-muted-foreground hover:bg-red-50 hover:text-destructive"><Trash2 className="size-4" /></button>
                  </div>
                </div>
                <p className="col-start-2 font-semibold sm:col-start-auto">{formatMoney(product.price * quantity)}</p>
              </article>
            ))}
          </section>
          <aside className="h-fit rounded-[1.75rem] bg-[#e1e5d3] p-7 lg:col-span-4">
            <h2 className="text-2xl font-semibold tracking-[-0.04em]">Tổng tiền tham khảo</h2>
            <div className="mt-7 space-y-4 text-sm">
              <div className="flex justify-between"><span className="text-muted-foreground">Số lượng</span><span>{count} sản phẩm</span></div>
              <div className="flex justify-between border-t border-black/10 pt-4 text-base font-semibold"><span>Tạm tính</span><span>{formatMoney(subtotal)}</span></div>
            </div>
            <button type="button" disabled className="mt-8 flex h-12 w-full cursor-not-allowed items-center justify-center rounded-full bg-[#274f3a] px-4 text-sm font-semibold text-white opacity-55">Đặt hàng trực tuyến chưa mở</button>
            <p className="mt-4 text-xs leading-5 text-muted-foreground">Giỏ này chỉ lưu trên thiết bị và không gửi đơn hàng. Danh mục, giá và khả năng mua thực tế chưa được công khai.</p>
          </aside>
        </div>
      )}
    </main>
  )
}
