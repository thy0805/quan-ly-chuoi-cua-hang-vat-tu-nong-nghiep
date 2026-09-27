const integerFormatter = new Intl.NumberFormat("vi-VN")

export function quantityMilli(value: string): bigint | null {
  if (!/^-?\d+(?:\.\d{0,3})?$/.test(value)) return null
  const negative = value.startsWith("-")
  const [whole, fraction = ""] = (negative ? value.slice(1) : value).split(".")
  const milli = BigInt(whole) * BigInt(1000) + BigInt(fraction.padEnd(3, "0"))
  return negative ? -milli : milli
}

export function formatQuantityMilli(milli: bigint): string {
  const absolute = milli < BigInt(0) ? -milli : milli
  const fraction = String(absolute % BigInt(1000)).padStart(3, "0").replace(/0+$/, "")
  return `${milli < BigInt(0) ? "−" : ""}${integerFormatter.format(absolute / BigInt(1000))}${fraction ? `,${fraction}` : ""}`
}

export function formatQuantity(value: string): string {
  const milli = quantityMilli(value)
  return milli === null ? "—" : formatQuantityMilli(milli)
}

export function formatQuantityDifference(left: string, right: string): string {
  const first = quantityMilli(left)
  const second = quantityMilli(right)
  return first === null || second === null ? "—" : formatQuantityMilli(first - second)
}

export function formatQuantityAbsolute(value: string): string {
  const milli = quantityMilli(value)
  return milli === null ? "—" : formatQuantityMilli(milli < BigInt(0) ? -milli : milli)
}

export function quantityIsPositive(value: string): boolean {
  const milli = quantityMilli(value)
  return milli !== null && milli > BigInt(0)
}
