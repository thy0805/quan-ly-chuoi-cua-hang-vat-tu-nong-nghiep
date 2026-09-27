"use client"

import { createContext, useContext, useState } from "react"
import Link from "next/link"
import { usePathname, useRouter } from "next/navigation"
import { AlertTriangle, ArrowLeftRight, BarChart3, Bell, Boxes, ClipboardList, HandCoins, LayoutDashboard, LogOut, MapPin, Menu, Package, PackagePlus, RefreshCw, Users } from "lucide-react"
import { DesignStatus } from "@/components/design-status"
import { useNotificationFeed } from "@/components/admin/notification-feed"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { logout, type Profile } from "@/lib/api"

const navigation = [
  { label: "Tổng quan", href: "/admin", icon: LayoutDashboard },
  { label: "Tồn kho", href: "/admin/inventory", icon: Boxes },
  { label: "Vật tư", href: "/admin/catalog", icon: Package },
  { label: "Tổ chức", href: "/admin/organization", icon: MapPin },
  { label: "Tài khoản", href: "/admin/users", icon: Users },
  { label: "Nhà cung cấp", href: "/admin/suppliers", icon: Users },
  { label: "Khách hàng", href: "/admin/customers", icon: Users },
  { label: "Nhập hàng", href: "/admin/purchases", icon: PackagePlus },
  { label: "Bán hàng", href: "/admin/sales", icon: ClipboardList },
  { label: "Điều chuyển", href: "/admin/transfers", icon: ArrowLeftRight },
  { label: "Công nợ", href: "/admin/debts", icon: HandCoins },
  { label: "Báo cáo", href: "/admin/reports", icon: BarChart3, reportOnly: true },
  { label: "Cảnh báo", href: "/admin/alerts", icon: AlertTriangle },
  { label: "Đồng bộ dữ liệu", href: "/admin/sync", icon: RefreshCw, ownerOnly: true },
]

const AdminProfileContext = createContext<Profile | null>(null)

export function useAdminProfile() {
  const profile = useContext(AdminProfileContext)
  if (!profile) throw new Error("Thiếu hồ sơ quản trị")
  return profile
}

export function AdminShell({ children, profile }: { children: React.ReactNode; profile: Profile }) {
  const pathname = usePathname()
  const router = useRouter()
  const [menuOpen, setMenuOpen] = useState(false)
  const [signingOut, setSigningOut] = useState(false)
  const [logoutError, setLogoutError] = useState("")
  const { result: notifications } = useNotificationFeed()
  const unreadCount = notifications?.unread_count ?? 0
  const isLiveInventory = pathname.startsWith("/admin/inventory") || pathname === "/admin/catalog" || pathname === "/admin/organization" || pathname === "/admin/users" || pathname === "/admin/suppliers" || pathname === "/admin/customers" || pathname === "/admin/purchases" || pathname.startsWith("/admin/sales") || pathname === "/admin/transfers" || pathname === "/admin/debts" || pathname === "/admin/reports" || pathname === "/admin/alerts" || pathname === "/admin/sync" || pathname === "/admin"
  const pageLabel = navigation.find((item) => item.href === pathname)?.label ?? "Quản lý"

  async function handleLogout() {
    if (signingOut) return
    setSigningOut(true)
    setLogoutError("")
    try {
      await logout()
      router.replace("/login")
      router.refresh()
    } catch (caught) {
      setLogoutError(caught instanceof Error ? caught.message : "Không đăng xuất được. Vui lòng thử lại.")
      setSigningOut(false)
    }
  }

  const sidebar = (
      <div className="flex h-full flex-col bg-[#203d2e] p-4 text-white">
        <Link href="/admin" onClick={() => setMenuOpen(false)} className="flex items-center gap-3 rounded-xl px-3 py-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#e8c675]">
          <span className="grid size-10 place-items-center rounded-full bg-[#e8c675] text-sm font-bold text-[#24392e]">NG</span>
          <span><span className="block font-semibold tracking-[-0.03em]">Nông Gia</span><span className="block text-xs text-white/60">Quản lý chuỗi</span></span>
        </Link>
        <nav aria-label="Điều hướng quản trị" className="mt-8 space-y-1">
          {navigation.filter((item) => !("ownerOnly" in item && item.ownerOnly && !profile.user.can_manage_sync) && !("reportOnly" in item && item.reportOnly && !profile.user.can_view_reports)).map(({ label, href, icon: Icon }) => {
            const content = <><Icon className="size-4 shrink-0" /><span>{label}</span>{href === "/admin/alerts" && unreadCount > 0 && <span className="ml-auto rounded-full bg-[#e8c675] px-2 py-0.5 text-xs font-bold text-[#203d2e]">{unreadCount > 99 ? "99+" : unreadCount}</span>}</>
            if (!href) return <span key={label} aria-disabled="true" title="Chức năng đang phát triển" className="flex min-h-11 items-center gap-3 rounded-xl px-3 text-sm text-white/40">{content}</span>
            return <Link key={label} href={href} onClick={() => setMenuOpen(false)} aria-current={pathname === href ? "page" : undefined} className={`flex min-h-11 items-center gap-3 rounded-xl px-3 text-sm transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#e8c675] ${pathname === href ? "bg-white text-[#203d2e]" : "text-white/75 hover:bg-white/10 hover:text-white"}`}>{content}</Link>
          })}
        </nav>
        <div className="mt-auto rounded-2xl border border-white/10 bg-white/5 p-4">
          <p className="truncate text-sm font-semibold">{profile.user.username}</p>
          <p className="mt-1 text-xs text-white/60">{profile.branches.length} chi nhánh được phân quyền</p>
          <button type="button" aria-label="Đăng xuất" onClick={handleLogout} disabled={signingOut} className="logout-control mt-4 text-sm font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#e8c675] disabled:cursor-wait disabled:opacity-60"><LogOut aria-hidden="true" className="size-4 shrink-0" /><span>{signingOut ? "Đang xử lý" : "Đăng xuất"}</span></button>
          {logoutError && <p role="alert" className="mt-3 text-xs text-[#ffe6bc]">{logoutError}</p>}
        </div>
      </div>
  )

  return (
    <AdminProfileContext.Provider value={profile}>
    <div className="min-h-screen bg-[#f3f1e8]">
      {!isLiveInventory && <DesignStatus />}
      <div className="flex min-h-screen">
        <aside className="hidden w-72 shrink-0 md:block">{sidebar}</aside>
        <Sheet open={menuOpen} onOpenChange={setMenuOpen}>
          <SheetContent side="left" className="w-[min(20rem,85vw)] border-none bg-[#203d2e] p-0 text-white md:hidden">
            <SheetTitle className="sr-only">Điều hướng quản trị</SheetTitle>
            <SheetDescription className="sr-only">Chọn trang quản trị hoặc đăng xuất.</SheetDescription>
            {sidebar}
          </SheetContent>
        </Sheet>
        <div className="min-w-0 flex-1">
          <header className="flex h-20 items-center gap-4 border-b border-black/8 bg-[#fbfaf5] px-5 lg:px-8">
            <button type="button" aria-label="Mở menu quản trị" onClick={() => setMenuOpen(true)} className="grid size-11 place-items-center rounded-xl border border-black/10 md:hidden"><Menu className="size-5" /></button>
            <div><p className="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">Nông Gia / Admin</p><p className="mt-1 text-sm font-semibold">{pageLabel}</p></div>
            <Link href="/admin/alerts" aria-label={unreadCount ? `${unreadCount} cảnh báo chưa đọc` : "Xem cảnh báo"} className="relative ml-auto inline-flex size-11 items-center justify-center rounded-xl border border-black/10 bg-white text-primary hover:bg-[#e9eadf] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#274f3a]"><Bell className="size-5" />{unreadCount > 0 && <span aria-live="polite" className="absolute -right-1 -top-1 rounded-full bg-[#b65a2f] px-1.5 text-[10px] font-bold text-white">{unreadCount > 99 ? "99+" : unreadCount}</span>}</Link>
            <div className="hidden text-right sm:block"><p className="text-sm font-semibold">{profile.user.username}</p><p className="text-xs text-muted-foreground">{profile.branches.length} chi nhánh được phân quyền</p></div>
          </header>
          {children}
        </div>
      </div>
    </div>
    </AdminProfileContext.Provider>
  )
}
