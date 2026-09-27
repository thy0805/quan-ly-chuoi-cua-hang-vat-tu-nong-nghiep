import { ProductsCatalog } from "@/components/shop/products-catalog"

export default async function ProductsPage({ searchParams }: { searchParams: Promise<{ category?: string | string[] }> }) {
  const categoryValue = (await searchParams).category
  const category = typeof categoryValue === "string" ? categoryValue : "Tất cả"
  return (
    <main className="page-shell py-16">
      <div className="grid gap-10 lg:grid-cols-12">
        <div className="lg:col-span-8">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-primary">Danh mục sản phẩm</p>
          <h1 className="mt-4 text-5xl font-semibold tracking-[-0.06em] sm:text-7xl">Vật tư cho từng nhu cầu canh tác.</h1>
        </div>
        <p className="self-end text-base leading-7 text-muted-foreground lg:col-span-4">Lọc nhóm hàng, tìm vật tư và xem thông tin minh họa trước khi lập danh sách quan tâm.</p>
      </div>
      <ProductsCatalog key={category} initialCategory={category} />
    </main>
  )
}
