"use client"

import { useState } from "react"
import { Pencil, Plus } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { apiFetch, type OrganizationResponse } from "@/lib/api"

type Kind = "chain" | "branch" | "warehouse"
type Form = { chain_id: string; branch_id: string; name: string; code: string; address: string; warehouse_type: string; first_branch_code: string; first_branch_name: string; first_branch_address: string; default_sales_warehouse_id: string; is_active: boolean }
const emptyForm = (): Form => ({ chain_id: "", branch_id: "", name: "", code: "", address: "", warehouse_type: "sales", first_branch_code: "", first_branch_name: "", first_branch_address: "", default_sales_warehouse_id: "", is_active: false })
const names = { chain: "chuỗi", branch: "chi nhánh", warehouse: "kho" }

export function OrganizationManager({ data, onSaved }: { data: OrganizationResponse; onSaved: () => void }) {
  const manageable = data.chains.filter((chain) => data.manageable_chain_ids.includes(chain.id))
  const branches = data.branches.filter((branch) => data.manageable_chain_ids.includes(branch.chain_id))
  const warehouses = data.warehouses.filter((warehouse) => branches.some((branch) => branch.id === warehouse.branch_id))
  const [open, setOpen] = useState(false)
  const [kind, setKind] = useState<Kind>("chain")
  const [targetId, setTargetId] = useState<string | null>(null)
  const [form, setForm] = useState<Form>(emptyForm)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")

  if (manageable.length === 0) return null

  function create(nextKind: Kind) {
    setKind(nextKind)
    setTargetId(null)
    setForm({ ...emptyForm(), chain_id: String(manageable[0]?.id ?? ""), branch_id: String(branches[0]?.id ?? "") })
    setError("")
    setOpen(true)
  }

  function edit(nextKind: Kind, id: string) {
    const next = emptyForm()
    if (nextKind === "chain") {
      const chain = data.chains.find((item) => item.id === id)
      if (!chain) return
      next.name = chain.name
      next.is_active = chain.is_active
    } else if (nextKind === "branch") {
      const branch = data.branches.find((item) => item.id === id)
      if (!branch) return
      next.chain_id = String(branch.chain_id)
      next.name = branch.name
      next.code = branch.code
      next.address = branch.address ?? ""
      next.default_sales_warehouse_id = String(branch.default_sales_warehouse_id ?? "")
      next.is_active = branch.is_active
    } else {
      const warehouse = data.warehouses.find((item) => item.id === id)
      if (!warehouse) return
      next.branch_id = String(warehouse.branch_id)
      next.name = warehouse.name
      next.code = warehouse.code
      next.warehouse_type = warehouse.warehouse_type
    }
    setKind(nextKind)
    setTargetId(id)
    setForm(next)
    setError("")
    setOpen(true)
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saving) return
    setSaving(true)
    setError("")
    try {
      const base = `/api/organization/${kind === "chain" ? "chains" : kind === "branch" ? "branches" : "warehouses"}`
      let body: object
      if (kind === "chain") {
        body = targetId ? { name: form.name.trim(), is_active: form.is_active } : { name: form.name.trim(), first_branch_code: form.first_branch_code.trim(), first_branch_name: form.first_branch_name.trim(), first_branch_address: form.first_branch_address.trim() || null }
      } else if (kind === "branch") {
        body = targetId ? { code: form.code.trim(), name: form.name.trim(), address: form.address.trim() || null, default_sales_warehouse_id: form.default_sales_warehouse_id || null, is_active: form.is_active } : { chain_id: form.chain_id, code: form.code.trim(), name: form.name.trim(), address: form.address.trim() || null }
      } else {
        body = { ...(!targetId && { branch_id: form.branch_id }), code: form.code.trim(), name: form.name.trim(), warehouse_type: form.warehouse_type.trim() }
      }
      await apiFetch(`${base}${targetId ? `/${targetId}` : ""}`, { method: targetId ? "PATCH" : "POST", body: JSON.stringify(body) })
      setOpen(false)
      setSuccess(`Đã ${targetId ? "cập nhật" : "tạo"} ${names[kind]}.`)
      onSaved()
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Không lưu được tổ chức.") }
    finally { setSaving(false) }
  }

  const inputClass = "mt-1 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"
  const availableWarehouses = data.warehouses.filter((warehouse) => String(warehouse.branch_id) === (targetId && kind === "branch" ? String(targetId) : form.branch_id))

  return <>
    {success && <p role="status" className="mt-5 rounded-xl bg-[#e1e5d3] p-3 text-sm text-[#274f3a]">{success}</p>}
    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader><CardTitle className="text-lg">Quản lý tổ chức</CardTitle><p className="text-sm text-muted-foreground">Tạo chuỗi cùng chi nhánh đầu tiên, sau đó tạo kho và chọn kho bán mặc định để kích hoạt chi nhánh.</p></CardHeader><CardContent className="space-y-5"><div className="flex flex-wrap gap-2"><button type="button" onClick={() => create("chain")} className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#274f3a] px-4 text-sm font-semibold text-white"><Plus className="size-4" />Tạo chuỗi</button><button type="button" onClick={() => create("branch")} className="inline-flex min-h-11 items-center gap-2 rounded-full border border-black/10 px-4 text-sm font-semibold"><Plus className="size-4" />Thêm chi nhánh</button><button type="button" onClick={() => create("warehouse")} className="inline-flex min-h-11 items-center gap-2 rounded-full border border-black/10 px-4 text-sm font-semibold"><Plus className="size-4" />Thêm kho</button></div><div className="grid gap-4 lg:grid-cols-3">{[["Chuỗi", manageable.map((item) => ({ id: item.id, label: item.name })), "chain"], ["Chi nhánh", branches.map((item) => ({ id: item.id, label: item.name })), "branch"], ["Kho", warehouses.map((item) => ({ id: item.id, label: item.name })), "warehouse"]].map(([title, items, editKind]) => <div key={title as string} className="rounded-xl border border-black/8 bg-white p-4"><p className="text-sm font-semibold">{title as string}</p><div className="mt-3 max-h-44 space-y-1 overflow-auto">{(items as { id: string; label: string }[]).map((item) => <button key={item.id} type="button" onClick={() => edit(editKind as Kind, item.id)} className="flex min-h-9 w-full items-center justify-between gap-2 rounded-lg px-2 text-left text-sm hover:bg-[#f3f1e8]"><span className="truncate">{item.label}</span><Pencil className="size-3.5 shrink-0" /></button>)}</div></div>)}</div></CardContent></Card>
    <Sheet open={open} onOpenChange={(value) => { if (!saving) setOpen(value) }}><SheetContent side="right" className="data-[side=right]:w-full data-[side=right]:sm:w-[32rem] data-[side=right]:sm:max-w-none overflow-y-auto bg-[#fbfaf5] p-6"><SheetTitle className="text-xl">{targetId ? "Sửa" : "Tạo"} {names[kind]}</SheetTitle><SheetDescription className="mt-2">{kind === "chain" && !targetId ? "Chi nhánh đầu tiên được tạo ở trạng thái ngừng hoạt động và bạn tự được gán quyền Chủ chuỗi." : kind === "branch" ? "Chi nhánh mới cần có kho bán mặc định trước khi kích hoạt." : "Dữ liệu tổ chức chỉ thay đổi trong phạm vi chuỗi được phân quyền."}</SheetDescription><form onSubmit={save} className="mt-7 space-y-4">
      {kind === "branch" && !targetId && <label className="block text-sm font-medium">Chuỗi<select required value={form.chain_id} onChange={(event) => setForm({ ...form, chain_id: event.target.value })} className={inputClass}>{manageable.map((chain) => <option key={chain.id} value={chain.id}>{chain.name}</option>)}</select></label>}
      {kind === "warehouse" && !targetId && <label className="block text-sm font-medium">Chi nhánh<select required value={form.branch_id} onChange={(event) => setForm({ ...form, branch_id: event.target.value })} className={inputClass}>{branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></label>}
      <label className="block text-sm font-medium">{kind === "chain" ? "Tên chuỗi" : kind === "branch" ? "Tên chi nhánh" : "Tên kho"}<input required maxLength={160} value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} className={inputClass} /></label>
      {kind === "chain" && !targetId && <><label className="block text-sm font-medium">Mã chi nhánh đầu tiên<input required maxLength={40} value={form.first_branch_code} onChange={(event) => setForm({ ...form, first_branch_code: event.target.value })} className={inputClass} /></label><label className="block text-sm font-medium">Tên chi nhánh đầu tiên<input required maxLength={160} value={form.first_branch_name} onChange={(event) => setForm({ ...form, first_branch_name: event.target.value })} className={inputClass} /></label><label className="block text-sm font-medium">Địa chỉ chi nhánh<textarea value={form.first_branch_address} onChange={(event) => setForm({ ...form, first_branch_address: event.target.value })} className="mt-1 min-h-24 w-full rounded-xl border border-black/10 bg-white p-3 text-sm" /></label></>}
      {kind !== "chain" && <label className="block text-sm font-medium">Mã {names[kind]}<input required maxLength={40} value={form.code} onChange={(event) => setForm({ ...form, code: event.target.value })} className={inputClass} /></label>}
      {kind === "branch" && <><label className="block text-sm font-medium">Địa chỉ<textarea value={form.address} onChange={(event) => setForm({ ...form, address: event.target.value })} className="mt-1 min-h-24 w-full rounded-xl border border-black/10 bg-white p-3 text-sm" /></label>{targetId && <label className="block text-sm font-medium">Kho bán mặc định<select value={form.default_sales_warehouse_id} onChange={(event) => setForm({ ...form, default_sales_warehouse_id: event.target.value })} className={inputClass}><option value="">Chưa chọn</option>{availableWarehouses.map((warehouse) => <option key={warehouse.id} value={warehouse.id}>{warehouse.name}</option>)}</select></label>}</>}
      {kind === "warehouse" && <label className="block text-sm font-medium">Mã loại kho<input required maxLength={40} value={form.warehouse_type} onChange={(event) => setForm({ ...form, warehouse_type: event.target.value })} className={inputClass} /></label>}
      {targetId && kind !== "warehouse" && <label className="flex items-center gap-3 rounded-xl border border-black/10 bg-white p-3 text-sm font-medium"><input type="checkbox" checked={form.is_active} onChange={(event) => setForm({ ...form, is_active: event.target.checked })} className="size-4 accent-[#274f3a]" />Đang hoạt động</label>}
      {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{error}</p>}
      <div className="flex justify-end gap-2"><button type="button" onClick={() => setOpen(false)} disabled={saving} className="min-h-11 rounded-full border border-black/10 px-5 text-sm font-semibold disabled:opacity-50">Hủy</button><button type="submit" disabled={saving} className="min-h-11 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu…" : targetId ? "Lưu thay đổi" : "Tạo mới"}</button></div>
    </form></SheetContent></Sheet>
  </>
}
