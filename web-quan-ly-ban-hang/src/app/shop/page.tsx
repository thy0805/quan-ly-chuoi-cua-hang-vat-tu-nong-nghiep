import Image from "next/image"
import Link from "next/link"
import { ArrowRight, PackageCheck, ShieldCheck, Truck } from "lucide-react"
import { ProductCard } from "@/components/shop/product-card"
import { StorefrontMotion } from "@/components/storefront-motion"
import { products } from "@/lib/mock-data"

export default function ShopPage() {
  const features = [
    { icon: PackageCheck, title: "Thông tin rõ ràng", text: "Theo dõi nhóm hàng, số lô và hạn sử dụng." },
    { icon: Truck, title: "Nhận hàng thuận tiện", text: "Chọn chi nhánh có tồn kho phù hợp với nhu cầu." },
    { icon: ShieldCheck, title: "Hỗ trợ có trách nhiệm", text: "Nội dung sử dụng hiển thị theo thông tin sản phẩm." },
  ]

  return (
    <StorefrontMotion>
      <main>
        <section className="editorial-grid overflow-hidden border-b border-black/8">
          <div className="page-shell grid min-h-[720px] items-center gap-12 py-16 lg:grid-cols-12 lg:py-20">
            <div className="lg:col-span-7">
              <p data-reveal className="text-sm font-semibold uppercase tracking-[0.22em] text-primary">Đồng hành cùng mùa vụ</p>
              <h1 data-reveal className="mt-6 max-w-5xl text-5xl font-semibold leading-[0.96] tracking-[-0.065em] sm:text-7xl lg:text-[6.5rem]">Chọn đúng vật tư, chăm tốt từng mùa.</h1>
              <p data-reveal className="mt-8 max-w-xl text-lg leading-8 text-muted-foreground">Mua sắm phân bón, hạt giống, sản phẩm bảo vệ thực vật và dụng cụ với thông tin lô hàng, tồn kho rõ ràng.</p>
              <div data-reveal className="mt-9 flex flex-wrap gap-3">
                <Link href="/shop/products" className="inline-flex h-12 items-center gap-3 rounded-full bg-[#274f3a] px-6 text-sm font-semibold text-white">Xem sản phẩm <ArrowRight className="size-4" /></Link>
                <a href="#categories" className="inline-flex h-12 items-center rounded-full border border-black/15 px-6 text-sm font-semibold">Khám phá danh mục</a>
              </div>
            </div>
            <div data-visual className="relative lg:col-span-5">
              <div className="relative aspect-[4/5] overflow-hidden rounded-[2.25rem]">
                <Image src="https://images.unsplash.com/photo-1464226184884-fa280b87c399?auto=format&fit=crop&w=1400&q=90" alt="Cánh đồng và cây trồng" fill priority className="object-cover" sizes="(max-width: 1024px) 100vw, 42vw" />
              </div>
              <div className="absolute -bottom-5 -left-5 max-w-[230px] rounded-2xl bg-[#e8c675] p-5 shadow-xl">
                <p className="text-xs font-semibold uppercase tracking-[0.15em]">Tra cứu nhanh</p>
                <p className="mt-2 text-lg font-semibold leading-6">Tồn kho, số lô và hạn sử dụng tại từng chi nhánh.</p>
              </div>
            </div>
          </div>
        </section>

        <section id="categories" className="page-shell py-24">
          <div className="flex flex-col justify-between gap-6 md:flex-row md:items-end">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.18em] text-primary">Danh mục chính</p>
              <h2 className="mt-4 max-w-2xl text-4xl font-semibold tracking-[-0.05em] sm:text-5xl">Đủ nhóm vật tư cho một mùa canh tác.</h2>
            </div>
            <Link href="/shop/products" className="inline-flex items-center gap-2 text-sm font-semibold">Xem tất cả <ArrowRight className="size-4" /></Link>
          </div>
          <div className="mt-12 grid grid-cols-1 gap-4 md:grid-cols-12">
            {[
              ["Phân bón", "Dinh dưỡng cân đối", "md:col-span-5 bg-[#d8dfc6]"],
              ["Hạt giống", "Khởi đầu mùa vụ", "md:col-span-4 bg-[#ead9ad]"],
              ["Dụng cụ", "Bền bỉ ngoài vườn", "md:col-span-3 bg-[#cadbd4]"],
            ].map(([title, text, classes]) => (
              <Link key={title} href="/shop/products" className={`min-h-64 rounded-[1.75rem] p-7 ${classes}`}>
                <p className="text-2xl font-semibold tracking-[-0.04em]">{title}</p>
                <p className="mt-2 text-sm text-foreground/60">{text}</p>
                <ArrowRight className="mt-24 size-5" />
              </Link>
            ))}
          </div>
        </section>

        <section className="page-shell pb-24">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-primary">Gợi ý hôm nay</p>
          <h2 className="mt-4 text-4xl font-semibold tracking-[-0.05em] sm:text-5xl">Vật tư được quan tâm</h2>
          <div className="mt-12 grid gap-8 md:grid-cols-2 lg:grid-cols-3">
            {products.slice(0, 3).map((product) => <ProductCard key={product.slug} product={product} />)}
          </div>
        </section>

        <section id="support" className="bg-[#203d2e] py-16 text-white">
          <div className="page-shell grid gap-8 md:grid-cols-3">
            {features.map(({ icon: Icon, title, text }) => (
              <div key={title} className="border-t border-white/20 pt-6">
                <Icon className="size-5 text-[#e8c675]" />
                <p className="mt-5 text-lg font-semibold">{title}</p>
                <p className="mt-2 text-sm leading-6 text-white/60">{text}</p>
              </div>
            ))}
          </div>
        </section>
      </main>
    </StorefrontMotion>
  )
}
