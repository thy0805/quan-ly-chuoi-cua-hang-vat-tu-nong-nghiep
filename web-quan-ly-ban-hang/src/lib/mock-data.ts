export type Product = {
  slug: string
  name: string
  category: string
  price: number
  unit: string
  image: string
  description: string
  stock: number
  lot: string
  expiry: string
  badge?: string
}

export const products: Product[] = [
  {
    slug: "phan-huu-co-vi-sinh",
    name: "Phân hữu cơ vi sinh",
    category: "Phân bón",
    price: 285000,
    unit: "bao 25 kg",
    image: "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?auto=format&fit=crop&w=1200&q=85",
    description: "Bổ sung hữu cơ, cải tạo đất và hỗ trợ bộ rễ khỏe trong giai đoạn sinh trưởng.",
    stock: 128,
    lot: "PB-260901",
    expiry: "09/2028",
    badge: "Bán chạy",
  },
  {
    slug: "hat-giong-ca-chua",
    name: "Hạt giống cà chua F1",
    category: "Hạt giống",
    price: 68000,
    unit: "gói",
    image: "https://images.unsplash.com/photo-1592924357228-91a4daadcfea?auto=format&fit=crop&w=1200&q=85",
    description: "Giống sinh trưởng khỏe, trái đồng đều, phù hợp canh tác nhà màng và ngoài đồng.",
    stock: 74,
    lot: "HG-260823",
    expiry: "03/2027",
    badge: "Mùa vụ mới",
  },
  {
    slug: "bo-voi-phun-ap-luc",
    name: "Bộ vòi phun áp lực",
    category: "Dụng cụ",
    price: 425000,
    unit: "bộ",
    image: "https://images.unsplash.com/photo-1617576683096-00fc8eecb3af?auto=format&fit=crop&w=1200&q=85",
    description: "Đầu phun điều chỉnh tia, dây chịu áp và tay cầm chống trượt cho công việc ngoài vườn.",
    stock: 19,
    lot: "DC-260712",
    expiry: "Không áp dụng",
  },
  {
    slug: "che-pham-sinh-hoc",
    name: "Chế phẩm sinh học",
    category: "Bảo vệ thực vật",
    price: 156000,
    unit: "chai 1 lít",
    image: "https://images.unsplash.com/photo-1464226184884-fa280b87c399?auto=format&fit=crop&w=1200&q=85",
    description: "Giải pháp sinh học hỗ trợ chăm sóc cây trồng, sử dụng theo đúng hướng dẫn trên nhãn.",
    stock: 42,
    lot: "BV-260815",
    expiry: "02/2027",
  },
  {
    slug: "hat-giong-dua-luoi",
    name: "Hạt giống dưa lưới",
    category: "Hạt giống",
    price: 92000,
    unit: "gói",
    image: "https://images.unsplash.com/photo-1571575173700-afb9492e6a50?auto=format&fit=crop&w=1200&q=85",
    description: "Hạt giống chọn lọc, độ đồng đều cao, phù hợp mô hình trồng giá thể.",
    stock: 8,
    lot: "HG-260829",
    expiry: "11/2026",
    badge: "Sắp hết",
  },
  {
    slug: "keo-cat-canh-chuyen-dung",
    name: "Kéo cắt cành chuyên dụng",
    category: "Dụng cụ",
    price: 238000,
    unit: "cái",
    image: "https://images.unsplash.com/photo-1416339306562-f3d12fefd36f?auto=format&fit=crop&w=1200&q=85",
    description: "Lưỡi thép sắc bén, tay cầm chắc chắn, phù hợp tỉa cành cây ăn trái.",
    stock: 31,
    lot: "DC-260630",
    expiry: "Không áp dụng",
  },
]

export const inventory = [
  { sku: "PB-HC-25", name: "Phân hữu cơ vi sinh", branch: "Chi nhánh Trung tâm", lot: "PB-260901", stock: 128, expiry: "09/2028", status: "Ổn định" },
  { sku: "HG-CT-F1", name: "Hạt giống cà chua F1", branch: "Chi nhánh Trung tâm", lot: "HG-260823", stock: 74, expiry: "03/2027", status: "Ổn định" },
  { sku: "DC-VP-01", name: "Bộ vòi phun áp lực", branch: "Chi nhánh Bình Chánh", lot: "DC-260712", stock: 19, expiry: "Không áp dụng", status: "Theo dõi" },
  { sku: "BV-SH-1L", name: "Chế phẩm sinh học", branch: "Chi nhánh Củ Chi", lot: "BV-260815", stock: 42, expiry: "02/2027", status: "Ổn định" },
  { sku: "HG-DL-02", name: "Hạt giống dưa lưới", branch: "Chi nhánh Bình Chánh", lot: "HG-260829", stock: 8, expiry: "11/2026", status: "Sắp hết" },
  { sku: "DC-KC-06", name: "Kéo cắt cành chuyên dụng", branch: "Chi nhánh Củ Chi", lot: "DC-260630", stock: 31, expiry: "Không áp dụng", status: "Ổn định" },
]

export const formatMoney = (value: number) =>
  new Intl.NumberFormat("vi-VN", {
    style: "currency",
    currency: "VND",
    maximumFractionDigits: 0,
  }).format(value)
