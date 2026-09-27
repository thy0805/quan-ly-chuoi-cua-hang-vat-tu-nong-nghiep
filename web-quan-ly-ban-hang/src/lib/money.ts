const integerFormatter = new Intl.NumberFormat("vi-VN")

export function moneyCents(value: string | number): bigint | null {
  const source = typeof value === "number" ? Number.isFinite(value) && Math.abs(value) <= Number.MAX_SAFE_INTEGER / 100 ? value.toFixed(2) : "" : value.trim()
  if (!/^-?\d+(?:\.\d{0,2})?$/.test(source)) return null
  const negative = source.startsWith("-")
  const [whole, fraction = ""] = (negative ? source.slice(1) : source).split(".")
  const cents = BigInt(whole) * BigInt(100) + BigInt(fraction.padEnd(2, "0"))
  return negative ? -cents : cents
}

export function moneyFromCents(cents: bigint): string {
  const negative = cents < BigInt(0)
  const absolute = negative ? -cents : cents
  return `${negative ? "-" : ""}${absolute / BigInt(100)}.${String(absolute % BigInt(100)).padStart(2, "0")}`
}

export function formatVnd(value: string | number | null | undefined): string {
  if (value === null || value === undefined) return "0 ₫"
  const cents = moneyCents(value)
  if (cents === null) return "—"
  const negative = cents < BigInt(0)
  const absolute = negative ? -cents : cents
  const fraction = String(absolute % BigInt(100)).padStart(2, "0").replace(/0+$/, "")
  return `${negative ? "-" : ""}${integerFormatter.format(absolute / BigInt(100))}${fraction ? `,${fraction}` : ""} ₫`
}
