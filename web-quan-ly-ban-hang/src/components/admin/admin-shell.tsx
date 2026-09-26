"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { AlertTriangle, ArrowLeftRight, Boxes, ClipboardList, LayoutDashboard, Menu, PackagePlus, Search, Users } from "lucide-react"
import { DesignStatus } from "@/components/design-status"

const navigation = [
  { label: "Tổng quan", href: "/admin", icon: LayoutDashboard },
  { label: "Tồn kho", href: "/admin/inventory", icon: Boxes },
  { label: "Nhập hàng", href: "#", icon: PackagePlus },
  { label: "Bán hàng", href: "#", icon: ClipboardList },
  { label: "Điều chuyển", href: "#", icon: ArrowLeftRight },
  { label: "Đối tác", href: "#", icon: Users },
  { label: "Cảnh báo", href: "#", icon: AlertTriangle },
]

export function AdminShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()

  return (
    <div className="min-h-screen bg-[#f3f1e8]">
      <DesignStatus />
      <div className="flex min-h-[calc(100vh-33px)]">
        <aside className="hidden w-72 shrink-0 flex-col bg-[#203d2e] p-4 text-white md:flex">
          <Link href="/admin" className="flex items-center gap-3 px-3 py-4">
            <span className="grid size-10 place-items-center rounded-full bg-[#e8c675] text-sm font-bold text-[#24392e]">NG</span>
            <div>
              <p className="font-semibold tracking-[-0.03em]">Nông Gia</p>
              <p className="text-xs text-white/50">Quản lý chuỗi</p>
            </div>
          </Link>
          <nav className="mt-8 space-y-1">
            {navigation.map(({ label, href, icon: Icon }) => {
              const isActive = href !== "#" && pathname === href
              return (
                <Link key={label} href={href} className={`flex h-11 items-center gap-3 rounded-xl px-3 text-sm transition ${isActive ? "bg-white text-[#203d2e]" : "text-white/65 hover:bg-white/8 hover:text-white"}`}>
                  <Icon className="size-4" />
                  {label}
                  {label === "Cảnh báo" && <span className="ml-auto rounded-full bg-[#e8c675] px-2 py-0.5 text-[10px] font-bold text-[#24392e]">5</span>}
                </Link>
              )
            })}
          </nav>
          <div className="mt-auto rounded-2xl bg-white/8 p-4">
            <p className="text-sm font-semibold">Nguyễn Văn An</p>
            <p className="mt-1 text-xs text-white/50">Quản lý chi nhánh</p>
          </div>
        </aside>
        <div className="min-w-0 flex-1">
          <header className="flex h-20 items-center justify-between border-b border-black/8 bg-[#fbfaf5] px-5 lg:px-8">
            <button aria-label="Mở menu" className="grid size-10 place-items-center md:hidden"><Menu className="size-5" /></button>
            <div className="hidden items-center gap-3 text-sm text-muted-foreground sm:flex"><Search className="size-4" /> Tìm vật tư, đơn hàng, khách hàng...</div>
            <div className="ml-auto flex items-center gap-3">
              <div className="text-right">
                <p className="text-sm font-semibold">Chi nhánh Trung tâm</p>
                <p className="text-xs text-muted-foreground">Cập nhật 08:30 hôm nay</p>
              </div>
              <span className="grid size-10 place-items-center rounded-full bg-[#d8dfc6] text-sm font-bold">NA</span>
            </div>
          </header>
          {children}
        </div>
      </div>
    </div>
  )
}
