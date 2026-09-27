export type Product = {
  slug: string
  name: string
  category: string
  price: number
  unit: string
  image: string
  description: string
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
  },
  {
    slug: "hat-giong-ca-chua",
    name: "Hạt giống cà chua F1",
    category: "Hạt giống",
    price: 68000,
    unit: "gói",
    image: "https://images.unsplash.com/photo-1592924357228-91a4daadcfea?auto=format&fit=crop&w=1200&q=85",
    description: "Giống sinh trưởng khỏe, trái đồng đều, phù hợp canh tác nhà màng và ngoài đồng.",
  },
  {
    slug: "bo-voi-phun-ap-luc",
    name: "Bộ vòi phun áp lực",
    category: "Dụng cụ",
    price: 425000,
    unit: "bộ",
    image: "https://images.unsplash.com/photo-1617576683096-00fc8eecb3af?auto=format&fit=crop&w=1200&q=85",
    description: "Đầu phun điều chỉnh tia, dây chịu áp và tay cầm chống trượt cho công việc ngoài vườn.",
  },
  {
    slug: "che-pham-sinh-hoc",
    name: "Chế phẩm sinh học",
    category: "Bảo vệ thực vật",
    price: 156000,
    unit: "chai 1 lít",
    image: "https://images.unsplash.com/photo-1464226184884-fa280b87c399?auto=format&fit=crop&w=1200&q=85",
    description: "Giải pháp sinh học hỗ trợ chăm sóc cây trồng, sử dụng theo đúng hướng dẫn trên nhãn.",
  },
  {
    slug: "hat-giong-dua-luoi",
    name: "Hạt giống dưa lưới",
    category: "Hạt giống",
    price: 92000,
    unit: "gói",
    image: "https://images.unsplash.com/photo-1571575173700-afb9492e6a50?auto=format&fit=crop&w=1200&q=85",
    description: "Hạt giống chọn lọc, độ đồng đều cao, phù hợp mô hình trồng giá thể.",
  },
  {
    slug: "keo-cat-canh-chuyen-dung",
    name: "Kéo cắt cành chuyên dụng",
    category: "Dụng cụ",
    price: 238000,
    unit: "cái",
    image: "https://images.unsplash.com/photo-1416339306562-f3d12fefd36f?auto=format&fit=crop&w=1200&q=85",
    description: "Lưỡi thép sắc bén, tay cầm chắc chắn, phù hợp tỉa cành cây ăn trái.",
  },
]

export const formatMoney = (value: number) =>
  new Intl.NumberFormat("vi-VN", {
    style: "currency",
    currency: "VND",
    maximumFractionDigits: 0,
  }).format(value)
