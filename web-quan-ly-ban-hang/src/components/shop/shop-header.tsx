import Link from "next/link"
import { Menu, Search, ShoppingBag } from "lucide-react"

export function ShopHeader() {
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
          <a href="#categories" className="hover:text-primary">Danh mục</a>
          <a href="#support" className="hover:text-primary">Hỗ trợ mùa vụ</a>
        </nav>
        <div className="flex items-center gap-2">
          <button aria-label="Tìm kiếm" className="grid size-10 place-items-center rounded-full border border-black/10 bg-white/60 hover:bg-white">
            <Search className="size-4" />
          </button>
          <Link href="/shop/cart" aria-label="Giỏ hàng" className="relative grid size-10 place-items-center rounded-full bg-[#274f3a] text-white">
            <ShoppingBag className="size-4" />
            <span className="absolute -right-1 -top-1 grid size-5 place-items-center rounded-full bg-[#e8c675] text-[10px] font-bold text-[#24392e]">2</span>
          </Link>
          <button aria-label="Mở menu" className="grid size-10 place-items-center lg:hidden">
            <Menu className="size-5" />
          </button>
        </div>
      </div>
    </header>
  )
}
