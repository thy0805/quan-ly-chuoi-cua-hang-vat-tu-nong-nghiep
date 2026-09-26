import Image from "next/image"
import Link from "next/link"
import { ArrowUpRight } from "lucide-react"
import { formatMoney, type Product } from "@/lib/mock-data"

export function ProductCard({ product }: { product: Product }) {
  return (
    <article className="group">
      <Link href={`/shop/products/${product.slug}`} className="block overflow-hidden rounded-[1.5rem] bg-[#e8e1cf]">
        <div className="relative aspect-[4/5] overflow-hidden">
          <Image src={product.image} alt={product.name} fill className="object-cover transition duration-700 group-hover:scale-105" sizes="(max-width: 768px) 100vw, 33vw" />
          {product.badge && <span className="absolute left-4 top-4 rounded-full bg-[#f7f3e8] px-3 py-1.5 text-xs font-semibold">{product.badge}</span>}
          <span className="absolute bottom-4 right-4 grid size-11 place-items-center rounded-full bg-white text-[#274f3a] opacity-0 transition group-hover:opacity-100">
            <ArrowUpRight className="size-4" />
          </span>
        </div>
      </Link>
      <div className="mt-4 flex items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">{product.category}</p>
          <Link href={`/shop/products/${product.slug}`} className="mt-1 block text-lg font-semibold tracking-[-0.025em]">{product.name}</Link>
        </div>
        <p className="whitespace-nowrap text-sm font-semibold">{formatMoney(product.price)}</p>
      </div>
    </article>
  )
}
