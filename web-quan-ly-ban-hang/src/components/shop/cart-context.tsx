"use client"

import { createContext, useContext, useEffect, useState } from "react"
import { products } from "@/lib/mock-data"

type CartItem = { slug: string; quantity: number }
type CartContextValue = {
  items: CartItem[]
  ready: boolean
  add: (slug: string, quantity: number) => void
  update: (slug: string, quantity: number) => void
  remove: (slug: string) => void
}

const storageKey = "klcn186-demo-cart-v1"
const CartContext = createContext<CartContextValue | null>(null)

function validItems(value: unknown): CartItem[] {
  if (!Array.isArray(value)) return []
  return value.filter((item): item is CartItem =>
    typeof item?.slug === "string" &&
    products.some((product) => product.slug === item.slug) &&
    Number.isInteger(item.quantity) && item.quantity > 0 && item.quantity <= 99,
  )
}

export function CartProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<CartItem[]>([])
  const [ready, setReady] = useState(false)

  useEffect(() => {
    const read = () => {
      try { setItems(validItems(JSON.parse(localStorage.getItem(storageKey) ?? "[]"))) }
      catch { setItems([]) }
      setReady(true)
    }
    queueMicrotask(read)
    window.addEventListener("storage", read)
    return () => window.removeEventListener("storage", read)
  }, [])

  useEffect(() => {
    if (ready) localStorage.setItem(storageKey, JSON.stringify(items))
  }, [items, ready])

  function update(slug: string, quantity: number) {
    const product = products.find((entry) => entry.slug === slug)
    if (!product) return
    setItems((current) => {
      const rest = current.filter((item) => item.slug !== slug)
      if (quantity <= 0) return rest
      return [...rest, { slug, quantity: Math.min(product.stock, 99, Math.max(1, Math.floor(quantity))) }]
    })
  }

  function add(slug: string, quantity: number) {
    const product = products.find((entry) => entry.slug === slug)
    if (!product || quantity <= 0 || product.stock <= 0) return
    setItems((current) => {
      const previous = current.find((item) => item.slug === slug)?.quantity ?? 0
      return [...current.filter((item) => item.slug !== slug), { slug, quantity: Math.min(product.stock, 99, previous + Math.floor(quantity)) }]
    })
  }

  return <CartContext.Provider value={{ items, ready, add, update, remove: (slug) => update(slug, 0) }}>{children}</CartContext.Provider>
}

export function useCart() {
  const cart = useContext(CartContext)
  if (!cart) throw new Error("CartProvider chưa được khởi tạo")
  return cart
}
