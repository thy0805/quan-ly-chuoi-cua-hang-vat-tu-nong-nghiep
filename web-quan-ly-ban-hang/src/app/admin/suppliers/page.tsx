"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Pencil, Plus, RotateCw, Search, Users } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { ApiError, apiFetch, type Supplier, type SupplierResponse } from "@/lib/api"

export default function SuppliersPage() {
  const router = useRouter()
  const [search, setSearch] = useState("")
  const [chainId, setChainId] = useState("")
  const [page, setPage] = useState(1)
  const [result, setResult] = useState<SupplierResponse | null>(null)
  const [chains, setChains] = useState<SupplierResponse["chains"]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [reload, setReload] = useState(0)
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<Supplier | null>(null)
  const [form, setForm] = useState({ chain_id: "", name: "", phone: "", address: "" })
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState("")
  const [success, setSuccess] = useState("")

  useEffect(() => {
    const controller = new AbortController()
    const timer = window.setTimeout(async () => {
      setLoading(true)
      setError("")
      const params = new URLSearchParams({ page: String(page), per_page: "20" })
      if (search.trim()) params.set("search", search.trim())
      if (chainId) params.set("chain_id", chainId)
      try {
        const data = await apiFetch<SupplierResponse>(`/api/suppliers?${params}`, { signal: controller.signal })
        if (!controller.signal.aborted) { setResult(data); setChains(data.chains) }
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setResult(null)
        setError(caught instanceof Error ? caught.message : "Không tải được nhà cung cấp.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }, search ? 250 : 0)
    return () => { window.clearTimeout(timer); controller.abort() }
  }, [chainId, page, reload, router, search])

  function begin(item: Supplier | null = null) {
    setEditing(item)
    setForm({ chain_id: String(item?.chain_id ?? chains[0]?.id ?? ""), name: item?.name ?? "", phone: item?.phone ?? "", address: item?.address ?? "" })
    setFormError("")
    setSuccess("")
    setOpen(true)
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saving) return
    setSaving(true)
    setFormError("")
    try {
      await apiFetch(`/api/suppliers${editing ? `/${editing.id}` : ""}`, {
        method: editing ? "PATCH" : "POST",
        body: JSON.stringify({ ...(!editing && { chain_id: form.chain_id }), name: form.name.trim(), phone: form.phone.trim() || null, address: form.address.trim() || null }),
      })
      setOpen(false)
      setSuccess(editing ? "Đã cập nhật nhà cung cấp." : "Đã thêm nhà cung cấp.")
      setReload((value) => value + 1)
    } catch (caught) {
      setFormError(caught instanceof Error ? caught.message : "Không lưu được nhà cung cấp.")
    } finally { setSaving(false) }
  }

  const inputClass = "mt-1 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"

  return <main className="p-5 lg:p-8">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Đối tác theo chuỗi</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Nhà cung cấp</h1><p className="mt-2 text-sm text-muted-foreground">Tra cứu nhà cung cấp trong chuỗi được phân quyền. Chỉ Chủ chuỗi được sửa dữ liệu chung.</p></div>{result?.can_manage && <button type="button" onClick={() => begin()} className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white hover:bg-[#203d2e]"><Plus className="size-4" />Thêm nhà cung cấp</button>}</div>
    {success && <p role="status" className="mt-5 rounded-xl bg-[#e1e5d3] p-3 text-sm text-[#274f3a]">{success}</p>}
    {error && <div role="alert" className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-2 rounded-lg border border-red-300 px-3 font-semibold hover:bg-red-100"><RotateCw className="size-4" />Thử lại</button></div>}
    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader className="gap-4 lg:flex-row lg:items-center lg:justify-between"><div><CardTitle className="text-lg">Danh sách nhà cung cấp</CardTitle><p className="mt-1 text-sm text-muted-foreground">Tên, số điện thoại và chuỗi sở hữu.</p></div><div className="flex flex-col gap-2 sm:flex-row"><label className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" /><input aria-label="Tìm nhà cung cấp" value={search} onChange={(event) => { setSearch(event.target.value); setPage(1); setResult(null) }} placeholder="Tên hoặc số điện thoại" className="h-11 w-full rounded-xl border border-black/10 bg-white pl-9 pr-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a] sm:w-60" /></label><select aria-label="Lọc chuỗi" value={chainId} onChange={(event) => { setChainId(event.target.value); setPage(1); setResult(null) }} className="h-11 rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"><option value="">Tất cả chuỗi được phép</option>{chains.map((chain) => <option key={chain.id} value={chain.id}>{chain.name}</option>)}</select></div></CardHeader><CardContent><div className="overflow-x-auto"><table className="w-full min-w-[650px] text-left text-sm"><thead className="border-b border-black/8 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="py-3 pr-5 font-medium">Nhà cung cấp</th><th className="py-3 pr-5 font-medium">Chuỗi</th><th className="py-3 pr-5 font-medium">Liên hệ</th><th className="py-3 font-medium">Địa chỉ</th>{result?.can_manage && <th className="py-3 font-medium">Thao tác</th>}</tr></thead><tbody>{!loading && result?.data.map((item) => <tr key={item.id} className="border-b border-black/6 last:border-0"><td className="py-4 pr-5 font-semibold">{item.name}</td><td className="py-4 pr-5">{item.chain_name}</td><td className="py-4 pr-5">{item.phone || "—"}</td><td className="py-4 pr-5">{item.address || "—"}</td>{result.can_manage && <td className="py-4"><button type="button" onClick={() => begin(item)} className="inline-flex min-h-9 items-center gap-1 rounded-lg border border-black/10 px-3 text-xs font-semibold hover:bg-[#e9eadf]"><Pencil className="size-3" />Sửa</button></td>}</tr>)}</tbody></table>{loading && <div role="status" className="space-y-3 py-6"><span className="sr-only">Đang tải nhà cung cấp</span>{[1, 2, 3].map((row) => <Skeleton key={row} className="h-12 w-full" />)}</div>}{!loading && !error && result?.data.length === 0 && <div className="py-12 text-center"><Users className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Chưa có nhà cung cấp phù hợp</p><p className="mt-1 text-sm text-muted-foreground">Chủ chuỗi có thể thêm nhà cung cấp để lập phiếu nhập.</p></div>}</div>{result && <div className="mt-5 flex flex-wrap items-center justify-between gap-3 text-sm text-muted-foreground"><span>{result.pagination.total} nhà cung cấp</span>{result.pagination.last_page > 1 && <div className="flex items-center gap-3"><button type="button" disabled={page <= 1 || loading} onClick={() => { setPage(page - 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trang trước</button><span>{result.pagination.current_page} / {result.pagination.last_page}</span><button type="button" disabled={page >= result.pagination.last_page || loading} onClick={() => { setPage(page + 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trang sau</button></div>}</div>}</CardContent></Card>
    <Sheet open={open} onOpenChange={(value) => { if (!saving) setOpen(value) }}><SheetContent side="right" className="data-[side=right]:w-full data-[side=right]:sm:w-[32rem] data-[side=right]:sm:max-w-none overflow-y-auto bg-[#fbfaf5] p-6"><SheetTitle className="text-xl">{editing ? "Sửa" : "Thêm"} nhà cung cấp</SheetTitle><SheetDescription className="mt-2">Thông tin dùng chung trong chuỗi. Không xóa đối tác đã gắn chứng từ.</SheetDescription><form onSubmit={save} className="mt-7 space-y-4">{!editing && <label className="block text-sm font-medium">Chuỗi<select required value={form.chain_id} onChange={(event) => setForm((current) => ({ ...current, chain_id: event.target.value }))} className={inputClass}>{chains.map((chain) => <option key={chain.id} value={chain.id}>{chain.name}</option>)}</select></label>}<label className="block text-sm font-medium">Tên nhà cung cấp<input required maxLength={160} value={form.name} onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))} className={inputClass} /></label><label className="block text-sm font-medium">Số điện thoại<input maxLength={30} value={form.phone} onChange={(event) => setForm((current) => ({ ...current, phone: event.target.value }))} className={inputClass} /></label><label className="block text-sm font-medium">Địa chỉ<textarea value={form.address} onChange={(event) => setForm((current) => ({ ...current, address: event.target.value }))} className="mt-1 min-h-28 w-full rounded-xl border border-black/10 bg-white p-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]" /></label>{formError && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{formError}</p>}<div className="flex justify-end gap-2"><button type="button" onClick={() => setOpen(false)} disabled={saving} className="min-h-11 rounded-full border border-black/10 px-5 text-sm font-semibold disabled:opacity-50">Hủy</button><button type="submit" disabled={saving} className="min-h-11 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu…" : editing ? "Lưu thay đổi" : "Thêm mới"}</button></div></form></SheetContent></Sheet>
  </main>
}
