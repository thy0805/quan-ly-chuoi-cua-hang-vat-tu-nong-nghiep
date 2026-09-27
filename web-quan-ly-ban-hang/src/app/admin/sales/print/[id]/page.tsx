"use client"

import { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { Printer, RotateCw } from "lucide-react"
import { ApiError, apiFetch } from "@/lib/api"
import { formatVnd } from "@/lib/money"

type Detail = {
  data: { id: string; order_no: string; status: string; sold_at: string; branch_name: string; branch_address: string | null; customer_name: string | null; customer_phone: string | null; customer_address: string | null; invoice_no: string | null; issued_at: string | null; subtotal: string | null; invoice_discount_amount: string | null; invoice_tax_amount: string | null; total_amount: string; paid_amount: string | null; remaining_amount: string | null }
  items: { id: string; product_name: string; product_code: string; lot_no: string; quantity: string; unit_price: string; discount_amount: string; line_total: string; tax_rate_snapshot: string; tax_amount: string }[]
}


export default function PrintInvoicePage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const [detail, setDetail] = useState<Detail | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [reload, setReload] = useState(0)

  useEffect(() => {
    const controller = new AbortController()
    apiFetch<Detail>(`/api/sales-orders/${params.id}`, { signal: controller.signal })
      .then((body) => { if (!controller.signal.aborted) { setDetail(body); setError("") } })
      .catch((caught) => {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setError(caught instanceof Error ? caught.message : "Không tải được hóa đơn.")
      })
      .finally(() => { if (!controller.signal.aborted) setLoading(false) })
    return () => controller.abort()
  }, [params.id, reload, router])

  if (loading) return <main className="p-8" role="status">Đang tải hóa đơn…</main>
  if (error) return <main className="p-8"><p role="alert" className="text-red-800">{error}</p><button type="button" onClick={() => { setLoading(true); setReload((value) => value + 1) }} className="mt-4 inline-flex items-center gap-2 font-semibold"><RotateCw className="size-4" />Thử lại</button></main>
  if (!detail || detail.data.status !== "confirmed" || !detail.data.invoice_no) return <main className="p-8" role="alert">Đơn này chưa có hóa đơn đã phát hành.</main>
  const invoice = detail.data

  return <main className="invoice-page mx-auto max-w-4xl p-5 lg:p-8"><div className="mb-6 flex justify-end print:hidden"><button type="button" onClick={() => window.print()} className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white"><Printer className="size-4" />In hóa đơn</button></div><article className="rounded-2xl bg-white p-6 text-[#26362d] shadow-sm sm:p-10 print:rounded-none print:p-0 print:shadow-none"><div className="flex flex-wrap justify-between gap-8 border-b border-black/15 pb-7"><div><p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#53745d]">Nông Gia · {invoice.branch_name}</p><h1 className="mt-3 text-3xl font-semibold tracking-[-0.04em]">Hóa đơn bán hàng</h1><p className="mt-2 text-sm text-muted-foreground">Chứng từ bán hàng nội bộ</p>{invoice.branch_address && <p className="mt-3 max-w-sm text-sm">{invoice.branch_address}</p>}</div><div className="text-sm"><p className="text-xs uppercase tracking-wide text-muted-foreground">Số hóa đơn</p><p className="mt-1 font-semibold">{invoice.invoice_no}</p><p className="mt-3 text-xs uppercase tracking-wide text-muted-foreground">Ngày phát hành</p><p className="mt-1 font-medium">{invoice.issued_at ? new Intl.DateTimeFormat("vi-VN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(invoice.issued_at)) : "—"}</p><p className="mt-3 text-xs uppercase tracking-wide text-muted-foreground">Đơn bán</p><p className="mt-1 font-medium">{invoice.order_no}</p></div></div><div className="grid gap-5 border-b border-black/10 py-6 text-sm sm:grid-cols-2"><div><p className="text-xs uppercase tracking-wide text-muted-foreground">Khách hàng</p><p className="mt-1 font-semibold">{invoice.customer_name ?? "Khách lẻ"}</p>{invoice.customer_phone && <p className="mt-1">{invoice.customer_phone}</p>}{invoice.customer_address && <p className="mt-1">{invoice.customer_address}</p>}</div><div><p className="text-xs uppercase tracking-wide text-muted-foreground">Chi nhánh bán</p><p className="mt-1 font-semibold">{invoice.branch_name}</p></div></div><div className="overflow-x-auto py-6"><table className="w-full min-w-[600px] text-left text-sm"><thead className="border-b border-black/20 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3 pr-4">Vật tư / lô</th><th className="py-3 pr-4 text-right">SL</th><th className="py-3 pr-4 text-right">Đơn giá</th><th className="py-3 pr-4 text-right">Giảm</th><th className="py-3 pr-4 text-right">Thuế</th><th className="py-3 text-right">Trước thuế</th></tr></thead><tbody>{detail.items.map((item) => <tr key={item.id} className="border-b border-black/10"><td className="py-4 pr-4"><span className="font-semibold">{item.product_name}</span><span className="mt-1 block text-xs text-muted-foreground">{item.product_code} · lô {item.lot_no}</span></td><td className="py-4 pr-4 text-right tabular-nums">{item.quantity}</td><td className="py-4 pr-4 text-right tabular-nums">{formatVnd(item.unit_price)}</td><td className="py-4 pr-4 text-right tabular-nums">{formatVnd(item.discount_amount)}</td><td className="py-4 pr-4 text-right tabular-nums">{item.tax_rate_snapshot}%<span className="block text-xs">{formatVnd(item.tax_amount)}</span></td><td className="py-4 text-right font-semibold tabular-nums">{formatVnd(item.line_total)}</td></tr>)}</tbody></table></div><div className="ml-auto max-w-sm border-t border-black/15 pt-5 text-sm"><div className="flex justify-between gap-8 py-1"><span>Tiền hàng</span><strong>{formatVnd(invoice.subtotal)}</strong></div><div className="flex justify-between gap-8 py-1"><span>Chiết khấu</span><strong>−{formatVnd(invoice.invoice_discount_amount)}</strong></div><div className="flex justify-between gap-8 py-1"><span>Thuế</span><strong>+{formatVnd(invoice.invoice_tax_amount)}</strong></div><div className="mt-3 flex justify-between gap-8 border-t border-black/15 pt-4 text-lg"><span>Thành tiền</span><strong>{formatVnd(invoice.total_amount)}</strong></div><div className="mt-3 flex justify-between gap-8 py-1"><span>Đã thanh toán</span><strong>{formatVnd(invoice.paid_amount ?? 0)}</strong></div><div className="flex justify-between gap-8 py-1"><span>Còn phải thu</span><strong>{formatVnd(invoice.remaining_amount ?? 0)}</strong></div></div><p className="mt-10 border-t border-black/10 pt-5 text-xs text-muted-foreground">Thanh toán và công nợ được theo dõi trong nghiệp vụ riêng. Hóa đơn này không phải hóa đơn điện tử.</p></article></main>
}
