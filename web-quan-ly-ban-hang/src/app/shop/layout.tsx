import { DesignStatus } from "@/components/design-status"
import { CartProvider } from "@/components/shop/cart-context"
import { ShopFooter } from "@/components/shop/shop-footer"
import { ShopHeader } from "@/components/shop/shop-header"

export default function ShopLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-[#f7f3e8]">
      <DesignStatus />
      <CartProvider>
        <ShopHeader />
        {children}
        <ShopFooter />
      </CartProvider>
    </div>
  )
}
