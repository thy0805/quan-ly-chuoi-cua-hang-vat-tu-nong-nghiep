"use client"

import { useState } from "react"
import Link from "next/link"
import { Minus, Plus, ShoppingBag } from "lucide-react"
import { useCart } from "@/components/shop/cart-context"
import type { Product } from "@/lib/mock-data"

export function ProductPurchase({ product }: { product: Product }) {
  const { add, ready } = useCart()
  const [quantity, setQuantity] = useState(1)
  const [added, setAdded] = useState(false)

  return (
    <div className="mt-6">
      <div className="flex flex-wrap gap-3">
        <div className="flex h-12 items-center rounded-full border border-black/12 bg-white">
          <button type="button" aria-label="Giảm số lượng" disabled={quantity <= 1} onClick={() => { setQuantity((value) => value - 1); setAdded(false) }} className="grid size-12 place-items-center rounded-full disabled:opacity-40"><Minus className="size-4" /></button>
          <output className="w-8 text-center text-sm font-semibold">{quantity}</output>
          <button type="button" aria-label="Tăng số lượng" disabled={quantity >= 99} onClick={() => { setQuantity((value) => value + 1); setAdded(false) }} className="grid size-12 place-items-center rounded-full disabled:opacity-40"><Plus className="size-4" /></button>
        </div>
        <button type="button" disabled={!ready} onClick={() => { add(product.slug, quantity); setAdded(true) }} className="inline-flex h-12 min-w-48 flex-1 items-center justify-center gap-3 rounded-full bg-[#274f3a] px-6 text-sm font-semibold text-white transition hover:bg-[#203d2e] disabled:opacity-50"><ShoppingBag className="size-4" />{ready ? "Thêm vào giỏ tham khảo" : "Đang tải giỏ..."}</button>
      </div>
      {added && <p role="status" className="mt-4 text-sm font-medium text-primary">Đã thêm vào giỏ tham khảo. <Link href="/shop/cart" className="underline underline-offset-4">Xem giỏ hàng</Link></p>}
    </div>
  )
}
