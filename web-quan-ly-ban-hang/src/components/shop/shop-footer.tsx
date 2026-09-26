import Link from "next/link"

export function ShopFooter() {
  return (
    <footer className="mt-24 bg-[#203d2e] text-white">
      <div className="page-shell grid gap-10 py-14 md:grid-cols-3">
        <div>
          <p className="text-2xl font-semibold tracking-[-0.04em]">Nông Gia</p>
          <p className="mt-4 max-w-sm text-sm leading-6 text-white/65">Vật tư rõ nguồn gốc, tra cứu tồn kho và hỗ trợ mua sắm thuận tiện cho từng mùa vụ.</p>
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
          <p className="text-sm font-semibold">Liên hệ cửa hàng</p>
          <p className="mt-4 text-sm leading-6 text-white/65">Thứ hai – Chủ nhật<br />07:00 – 18:00</p>
        </div>
      </div>
    </footer>
  )
}
