"use client"

import { useGSAP } from "@gsap/react"
import gsap from "gsap"
import { useRef } from "react"

export function StorefrontMotion({ children }: { children: React.ReactNode }) {
  const scope = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
      gsap.from("[data-reveal]", {
        opacity: 0,
        y: 28,
        duration: 0.85,
        stagger: 0.08,
        ease: "power3.out",
      })
      gsap.from("[data-visual]", {
        opacity: 0,
        scale: 1.04,
        duration: 1.15,
        ease: "power3.out",
      })
    },
    { scope }
  )

  return <div ref={scope}>{children}</div>
}
