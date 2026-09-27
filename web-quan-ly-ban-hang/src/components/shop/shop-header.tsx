"use client"

import { useState } from "react"
import Link from "next/link"
import { Menu, Search, ShoppingBag } from "lucide-react"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { useCart } from "@/components/shop/cart-context"

export function ShopHeader() {
  const { items, ready } = useCart()
  const [menuOpen, setMenuOpen] = useState(false)
  const count = items.reduce((sum, item) => sum + item.quantity, 0)

  return (
    <header className="sticky top-0 z-50 border-b border-black/8 bg-[#f7f3e8]/95 backdrop-blur-xl">
      <div className="page-shell flex h-20 items-center justify-between gap-8">
        <Link href="/shop" className="flex items-center gap-3">
          <span className="grid size-10 place-items-center rounded-full bg-[#274f3a] text-sm font-bold text-white">NG</span>
          <span className="text-xl font-semibold tracking-[-0.04em]">Nông Gia</span>
        </Link>
        <nav className="hidden items-center gap-8 text-sm font-medium lg:flex">
          <Link href="/shop" className="hover:text-primary">Trang chủ</Link>
          <Link href="/shop/products" className="hover:text-primary">Sản phẩm</Link>
          <Link href="/shop#categories" className="hover:text-primary">Danh mục</Link>
          <Link href="/shop#support" className="hover:text-primary">Hỗ trợ mùa vụ</Link>
        </nav>
        <div className="flex items-center gap-2">
          <Link href="/shop/products#catalog-search" aria-label="Tìm sản phẩm" className="grid size-10 place-items-center rounded-full border border-black/10 bg-white/60 hover:bg-white">
            <Search className="size-4" />
          </Link>
          <Link href="/shop/cart" aria-label="Giỏ hàng" className="relative grid size-10 place-items-center rounded-full bg-[#274f3a] text-white">
            <ShoppingBag className="size-4" />
            {ready && count > 0 && <span className="absolute -right-1 -top-1 grid min-w-5 place-items-center rounded-full bg-[#e8c675] px-1 text-[10px] font-bold text-[#24392e]">{count}</span>}
          </Link>
          <button type="button" aria-label="Mở menu cửa hàng" onClick={() => setMenuOpen(true)} className="grid size-10 place-items-center lg:hidden">
            <Menu className="size-5" />
          </button>
        </div>
      </div>
      <Sheet open={menuOpen} onOpenChange={setMenuOpen}>
        <SheetContent side="right" className="bg-[#f7f3e8] p-6 lg:hidden">
          <SheetTitle className="text-xl font-semibold">Nông Gia</SheetTitle>
          <SheetDescription>Chọn khu vực cửa hàng.</SheetDescription>
          <nav aria-label="Điều hướng cửa hàng" className="mt-8 flex flex-col gap-2 text-base font-semibold">
            <Link href="/shop" onClick={() => setMenuOpen(false)} className="rounded-xl px-3 py-3 hover:bg-[#e1e5d3]">Trang chủ</Link>
            <Link href="/shop/products" onClick={() => setMenuOpen(false)} className="rounded-xl px-3 py-3 hover:bg-[#e1e5d3]">Sản phẩm</Link>
            <Link href="/shop#categories" onClick={() => setMenuOpen(false)} className="rounded-xl px-3 py-3 hover:bg-[#e1e5d3]">Danh mục</Link>
            <Link href="/shop/cart" onClick={() => setMenuOpen(false)} className="rounded-xl px-3 py-3 hover:bg-[#e1e5d3]">Giỏ hàng{count > 0 ? ` (${count})` : ""}</Link>
          </nav>
        </SheetContent>
      </Sheet>
    </header>
  )
}
