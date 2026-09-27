"use client"

import { useEffect, useState } from "react"
import Image from "next/image"
import { ExternalLink, RotateCw } from "lucide-react"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { apiFetch, type CatalogProduct, type ProductContent } from "@/lib/api"

type Form = { usage_instructions: string; additional_info: string; images: string }
const empty: Form = { usage_instructions: "", additional_info: "", images: "" }

export function ProductContentSheet({ product, canManage, onClose }: { product: CatalogProduct | null; canManage: boolean; onClose: () => void }) {
  const [content, setContent] = useState<ProductContent | null>(null)
  const [form, setForm] = useState<Form>(empty)
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [reload, setReload] = useState(0)

  useEffect(() => {
    if (!product) return
    const controller = new AbortController()
    const productId = product.id
    async function load() {
      setLoading(true)
      setError("")
      setSuccess("")
      try {
        const response = await apiFetch<{ data: ProductContent | null }>(`/api/catalog/products/${productId}/content`, { signal: controller.signal })
        if (controller.signal.aborted) return
        setContent(response.data)
        setForm({
          usage_instructions: response.data?.usage_instructions ?? "",
          additional_info: response.data?.additional_info ?? "",
          images: response.data?.images.join("\n") ?? "",
        })
      } catch (caught) {
        if (!controller.signal.aborted) setError(caught instanceof Error ? caught.message : "Không tải được nội dung vật tư.")
      } finally {
        if (!controller.signal.aborted) setLoading(false)
      }
    }
    void load()
    return () => controller.abort()
  }, [product, reload])

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!product || saving) return
    setSaving(true)
    setError("")
    setSuccess("")
    try {
      const response = await apiFetch<{ data: ProductContent }>(`/api/catalog/products/${product.id}/content`, {
        method: "PUT",
        body: JSON.stringify({
          usage_instructions: form.usage_instructions.trim() || null,
          additional_info: form.additional_info.trim() || null,
          images: form.images.split("\n").map((value) => value.trim()).filter(Boolean),
        }),
      })
      setContent(response.data)
      setSuccess("Đã lưu nội dung vật tư vào MongoDB.")
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Không lưu được nội dung vật tư.")
    } finally {
      setSaving(false)
    }
  }

  const fieldClass = "mt-2 w-full rounded-xl border border-black/10 bg-white px-3 py-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"

  return (
    <Sheet open={product !== null} onOpenChange={(open) => { if (!open && !saving) onClose() }}>
      <SheetContent side="right" className="data-[side=right]:w-full data-[side=right]:sm:w-[38rem] data-[side=right]:sm:max-w-none overflow-y-auto bg-[#fbfaf5] p-6">
        <SheetTitle className="pr-8 text-2xl tracking-tight">{product?.name ?? "Nội dung vật tư"}</SheetTitle>
        <SheetDescription className="mt-2">Hướng dẫn sử dụng và thông tin mở rộng lưu tại MongoDB, liên kết với vật tư trong PostgreSQL.</SheetDescription>
        {loading && <p role="status" className="mt-8 text-sm text-muted-foreground">Đang tải nội dung…</p>}
        {error && <div role="alert" className="mt-6 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800"><p>{error}</p><button type="button" onClick={() => setReload((value) => value + 1)} className="mt-3 inline-flex items-center gap-2 font-semibold"><RotateCw className="size-4" />Thử lại</button></div>}
        {!loading && !error && !content && <p className="mt-6 rounded-xl border border-black/10 bg-white p-4 text-sm text-muted-foreground">Vật tư này chưa có nội dung mở rộng.</p>}
        {!loading && !error && content && <div className="mt-6 space-y-5">
          <section><h3 className="text-sm font-semibold">Hướng dẫn sử dụng</h3><p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-muted-foreground">{content.usage_instructions || "Chưa có hướng dẫn."}</p></section>
          <section><h3 className="text-sm font-semibold">Thông tin bổ sung</h3><p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-muted-foreground">{content.additional_info || "Chưa có thông tin bổ sung."}</p></section>
          <section><h3 className="text-sm font-semibold">Hình ảnh</h3>{content.images.length ? <div className="mt-3 grid grid-cols-2 gap-3">{content.images.map((url) => <a key={url} href={url} target="_blank" rel="noopener noreferrer" className="group relative overflow-hidden rounded-xl border border-black/10 bg-white"><Image src={url} alt={`Hình vật tư ${product?.name}`} width={480} height={320} unoptimized className="aspect-[3/2] w-full object-cover" /><span className="absolute bottom-2 right-2 rounded-full bg-white/90 p-1.5 text-foreground"><ExternalLink className="size-4" /></span></a>)}</div> : <p className="mt-2 text-sm text-muted-foreground">Chưa có hình ảnh.</p>}</section>
        </div>}
        {canManage && !loading && !error && <form onSubmit={save} className="mt-8 space-y-5 border-t border-black/10 pt-6">
          <div><h3 className="font-semibold">Chỉnh sửa nội dung</h3><p className="mt-1 text-sm text-muted-foreground">Chỉ tài khoản quản trị danh mục chung có quyền lưu.</p></div>
          <label className="block text-sm font-medium">Hướng dẫn sử dụng<textarea maxLength={10000} rows={5} value={form.usage_instructions} onChange={(event) => setForm((current) => ({ ...current, usage_instructions: event.target.value }))} className={fieldClass} /></label>
          <label className="block text-sm font-medium">Thông tin bổ sung<textarea maxLength={10000} rows={4} value={form.additional_info} onChange={(event) => setForm((current) => ({ ...current, additional_info: event.target.value }))} className={fieldClass} /></label>
          <label className="block text-sm font-medium">Liên kết hình ảnh, mỗi dòng một URL<textarea rows={4} value={form.images} onChange={(event) => setForm((current) => ({ ...current, images: event.target.value }))} placeholder="https://..." className={fieldClass} /><span className="mt-1 block text-xs font-normal text-muted-foreground">Tối đa 12 ảnh, chỉ chấp nhận liên kết HTTP hoặc HTTPS.</span></label>
          {success && <p role="status" className="text-sm text-green-800">{success}</p>}
          <button type="submit" disabled={saving} className="min-h-11 rounded-full bg-[#274f3a] px-6 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu…" : "Lưu nội dung"}</button>
        </form>}
      </SheetContent>
    </Sheet>
  )
}
