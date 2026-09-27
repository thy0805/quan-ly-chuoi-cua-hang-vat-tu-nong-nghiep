"use client"

import { useState } from "react"
import { Search } from "lucide-react"
import { ProductCard } from "@/components/shop/product-card"
import { products } from "@/lib/mock-data"

const categories = ["Tất cả", "Phân bón", "Hạt giống", "Bảo vệ thực vật", "Dụng cụ"]

export function ProductsCatalog({ initialCategory = "Tất cả" }: { initialCategory?: string }) {
  const [category, setCategory] = useState(categories.includes(initialCategory) ? initialCategory : "Tất cả")
  const [search, setSearch] = useState("")
  const [sort, setSort] = useState("featured")
  const normalized = search.trim().toLocaleLowerCase("vi-VN")
  const visible = products.filter((product) =>
    (category === "Tất cả" || product.category === category) &&
    (!normalized || `${product.name} ${product.category}`.toLocaleLowerCase("vi-VN").includes(normalized)),
  ).sort((a, b) => sort === "price-asc" ? a.price - b.price : sort === "price-desc" ? b.price - a.price : sort === "name" ? a.name.localeCompare(b.name, "vi") : 0)

  return (
    <section aria-label="Danh mục vật tư minh họa">
      <div className="mt-14 flex flex-col gap-4 border-y border-black/10 py-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex flex-wrap gap-2" aria-label="Lọc theo nhóm vật tư">
          {categories.map((item) => <button type="button" key={item} onClick={() => setCategory(item)} aria-pressed={category === item} className={`min-h-10 rounded-full px-4 text-sm font-medium transition ${category === item ? "bg-[#274f3a] text-white" : "bg-white/65 hover:bg-[#e1e5d3]"}`}>{item}</button>)}
        </div>
        <div className="flex flex-col gap-2 sm:flex-row">
          <label className="relative">
            <span className="sr-only">Tìm sản phẩm minh họa</span>
            <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <input id="catalog-search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Tìm vật tư" className="h-11 w-full rounded-xl border border-black/10 bg-white pl-9 pr-3 text-sm focus-visible:outline-2 focus-visible:outline-[#274f3a] sm:w-48" />
          </label>
          <select aria-label="Sắp xếp sản phẩm" value={sort} onChange={(event) => setSort(event.target.value)} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm focus-visible:outline-2 focus-visible:outline-[#274f3a]">
            <option value="featured">Mặc định</option>
            <option value="price-asc">Giá thấp trước</option>
            <option value="price-desc">Giá cao trước</option>
            <option value="name">Tên A–Z</option>
          </select>
        </div>
      </div>
      <p role="status" className="mt-5 text-sm text-muted-foreground">{visible.length} sản phẩm minh họa</p>
      {visible.length ? <div className="mt-6 grid gap-x-6 gap-y-12 sm:grid-cols-2 lg:grid-cols-3">{visible.map((product) => <ProductCard key={product.slug} product={product} />)}</div> : <div className="mt-6 rounded-2xl border border-black/10 bg-white/60 px-6 py-14 text-center"><p className="font-semibold">Không tìm thấy vật tư phù hợp</p><p className="mt-2 text-sm text-muted-foreground">Thử đổi từ khóa hoặc nhóm vật tư.</p><button type="button" onClick={() => { setSearch(""); setCategory("Tất cả") }} className="mt-5 rounded-full border border-black/15 px-5 py-2 text-sm font-semibold">Xóa bộ lọc</button></div>}
    </section>
  )
}
