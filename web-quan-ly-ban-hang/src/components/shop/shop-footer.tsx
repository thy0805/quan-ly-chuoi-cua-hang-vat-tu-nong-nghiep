import Link from "next/link"

export function ShopFooter() {
  return (
    <footer className="mt-24 bg-[#203d2e] text-white">
      <div className="page-shell grid gap-10 py-14 md:grid-cols-3">
        <div>
          <p className="text-2xl font-semibold tracking-[-0.04em]">Nông Gia</p>
          <p className="mt-4 max-w-sm text-sm leading-6 text-white/65">Bản xem trước danh mục vật tư nông nghiệp và trải nghiệm chọn hàng cho từng mùa vụ.</p>
        </div>
        <div>
          <p className="text-sm font-semibold">Khám phá</p>
          <div className="mt-4 flex flex-col gap-3 text-sm text-white/65">
            <Link href="/shop/products">Tất cả sản phẩm</Link>
            <Link href="/shop/cart">Giỏ hàng</Link>
            <Link href="/admin">Giao diện quản lý</Link>
          </div>
        </div>
        <div>
          <p className="text-sm font-semibold">Trạng thái cửa hàng</p>
          <p className="mt-4 text-sm leading-6 text-white/65">Danh mục và giá đang minh họa. Đặt hàng trực tuyến chưa được mở.</p>
        </div>
      </div>
    </footer>
  )
}
