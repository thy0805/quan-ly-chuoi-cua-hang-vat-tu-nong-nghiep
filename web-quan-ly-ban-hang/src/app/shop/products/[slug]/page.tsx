import Image from "next/image"
import Link from "next/link"
import { ArrowLeft, Check, MapPin, Minus, Plus, ShoppingBag } from "lucide-react"
import { notFound } from "next/navigation"
import { formatMoney, products } from "@/lib/mock-data"

export default async function ProductDetailPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params
  const product = products.find((item) => item.slug === slug)

  if (!product) notFound()

  return (
    <main className="page-shell py-10">
      <Link href="/shop/products" className="inline-flex items-center gap-2 text-sm font-semibold"><ArrowLeft className="size-4" /> Trở lại danh sách</Link>
      <div className="mt-8 grid gap-12 lg:grid-cols-12">
        <div className="relative aspect-[4/5] overflow-hidden rounded-[2rem] bg-[#e8e1cf] lg:col-span-7">
          <Image src={product.image} alt={product.name} fill priority className="object-cover" sizes="(max-width: 1024px) 100vw, 58vw" />
        </div>
        <div className="self-center lg:col-span-5">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-primary">{product.category}</p>
          <h1 className="mt-4 text-5xl font-semibold leading-[1.02] tracking-[-0.055em]">{product.name}</h1>
          <p className="mt-5 text-2xl font-semibold">{formatMoney(product.price)} <span className="text-sm font-normal text-muted-foreground">/ {product.unit}</span></p>
          <p className="mt-7 text-base leading-7 text-muted-foreground">{product.description}</p>
          <div className="mt-8 rounded-2xl border border-black/10 bg-white/55 p-5">
            <div className="flex items-center justify-between border-b border-black/8 pb-4"><span className="text-sm text-muted-foreground">Số lô</span><span className="text-sm font-semibold">{product.lot}</span></div>
            <div className="flex items-center justify-between border-b border-black/8 py-4"><span className="text-sm text-muted-foreground">Hạn sử dụng</span><span className="text-sm font-semibold">{product.expiry}</span></div>
            <div className="flex items-center justify-between pt-4"><span className="text-sm text-muted-foreground">Tồn tham khảo</span><span className="inline-flex items-center gap-2 text-sm font-semibold text-primary"><Check className="size-4" /> {product.stock} {product.unit}</span></div>
          </div>
          <div className="mt-6 flex gap-3">
            <div className="flex h-12 items-center rounded-full border border-black/12 bg-white">
              <button aria-label="Giảm số lượng" className="grid size-12 place-items-center"><Minus className="size-4" /></button>
              <span className="w-8 text-center text-sm font-semibold">1</span>
              <button aria-label="Tăng số lượng" className="grid size-12 place-items-center"><Plus className="size-4" /></button>
            </div>
            <Link href="/shop/cart" className="inline-flex h-12 flex-1 items-center justify-center gap-3 rounded-full bg-[#274f3a] px-6 text-sm font-semibold text-white"><ShoppingBag className="size-4" /> Thêm vào giỏ</Link>
          </div>
          <p className="mt-5 flex items-center gap-2 text-xs text-muted-foreground"><MapPin className="size-4" /> Tồn kho thực tế được xác nhận theo chi nhánh khi đặt hàng.</p>
        </div>
      </div>
    </main>
  )
}
