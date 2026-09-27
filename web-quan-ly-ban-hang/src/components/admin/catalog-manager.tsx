"use client"

import { useState } from "react"
import { Pencil, Plus } from "lucide-react"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { apiFetch, type CatalogCategory, type CatalogProduct, type CatalogResponse } from "@/lib/api"

type Kind = "category" | "unit" | "product"
type Unit = CatalogResponse["units"][number]
type RecordItem = CatalogCategory | Unit | CatalogProduct
type FormState = { code: string; name: string; parent_id: string; category_id: string; unit_id: string; active_ingredient: string; sale_price: string; tax_rate: string; expiry_warning_days: string; is_active: boolean }

const labels: Record<Kind, string> = { category: "nhóm vật tư", unit: "đơn vị tính", product: "vật tư" }
const paths: Record<Kind, string> = { category: "categories", unit: "units", product: "products" }
const blank: FormState = { code: "", name: "", parent_id: "", category_id: "", unit_id: "", active_ingredient: "", sale_price: "0", tax_rate: "", expiry_warning_days: "", is_active: true }

function fieldsFor(kind: Kind, item: RecordItem | null): FormState {
  if (!item) return { ...blank }
  if (kind === "product") {
    const product = item as CatalogProduct
    return { ...blank, code: product.code, name: product.name, category_id: String(product.category_id), unit_id: String(product.unit_id), active_ingredient: product.active_ingredient ?? "", sale_price: product.sale_price, tax_rate: product.tax_rate ?? "", expiry_warning_days: product.expiry_warning_days === null ? "" : String(product.expiry_warning_days), is_active: Boolean(product.is_active) }
  }
  if (kind === "category") {
    const category = item as CatalogCategory
    return { ...blank, code: category.code, name: category.name, parent_id: category.parent_id === null ? "" : String(category.parent_id), is_active: Boolean(category.is_active) }
  }
  return { ...blank, code: item.code, name: item.name, is_active: Boolean(item.is_active) }
}

export function CatalogManager({ source, onSaved }: { source: CatalogResponse; onSaved: () => void }) {
  const [open, setOpen] = useState(false)
  const [kind, setKind] = useState<Kind>("product")
  const [editing, setEditing] = useState<RecordItem | null>(null)
  const [form, setForm] = useState<FormState>(blank)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")

  function begin(nextKind: Kind, item: RecordItem | null = null) {
    setKind(nextKind)
    setEditing(item)
    setForm(fieldsFor(nextKind, item))
    setError("")
    setSuccess("")
    setOpen(true)
  }

  function setField<Key extends keyof FormState>(key: Key, value: FormState[Key]) {
    setForm((current) => ({ ...current, [key]: value }))
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saving) return
    setSaving(true)
    setError("")
    setSuccess("")

    const values: Record<string, string | number | boolean | null> = {
      code: form.code.trim(), name: form.name.trim(), is_active: form.is_active,
    }
    if (kind === "category") values.parent_id = form.parent_id || null
    if (kind === "product") {
      values.category_id = form.category_id
      values.unit_id = form.unit_id
      values.active_ingredient = form.active_ingredient.trim() || null
      values.sale_price = form.sale_price
      values.tax_rate = form.tax_rate === "" ? null : form.tax_rate
      values.expiry_warning_days = form.expiry_warning_days === "" ? null : form.expiry_warning_days
    }

    if (editing) {
      const previous = fieldsFor(kind, editing)
      const oldValues: Record<string, string | number | boolean | null> = { code: previous.code, name: previous.name, is_active: previous.is_active }
      if (kind === "category") oldValues.parent_id = previous.parent_id || null
      if (kind === "product") {
        oldValues.category_id = previous.category_id
        oldValues.unit_id = previous.unit_id
        oldValues.active_ingredient = previous.active_ingredient.trim() || null
        oldValues.sale_price = previous.sale_price
        oldValues.tax_rate = previous.tax_rate === "" ? null : previous.tax_rate
        oldValues.expiry_warning_days = previous.expiry_warning_days === "" ? null : previous.expiry_warning_days
      }
      for (const key of Object.keys(values)) if (values[key] === oldValues[key]) delete values[key]
    }

    try {
      if (Object.keys(values).length > 0) {
        await apiFetch(`/api/catalog/${paths[kind]}${editing ? `/${editing.id}` : ""}`, {
          method: editing ? "PATCH" : "POST",
          body: JSON.stringify(values),
        })
      }
      setSuccess(editing ? "Đã cập nhật dữ liệu." : "Đã thêm dữ liệu.")
      onSaved()
      setOpen(false)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Không lưu được dữ liệu.")
    } finally {
      setSaving(false)
    }
  }

  const inputClass = "mt-1 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"
  const activeCategories = source.categories.filter((category) => category.is_active || (kind === "product" && category.id === (editing as CatalogProduct | null)?.category_id))
  const activeUnits = source.units.filter((unit) => unit.is_active || (kind === "product" && unit.id === (editing as CatalogProduct | null)?.unit_id))

  return (
    <>
      <section className="mt-6 rounded-2xl border border-black/8 bg-[#fbfaf5] p-5">
        <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Quản lý danh mục chung</h2><p className="mt-1 text-sm text-muted-foreground">Chỉ tài khoản Chủ chuỗi được chỉ định mới thay đổi dữ liệu này.</p></div><div className="flex flex-wrap gap-2">{(["category", "unit", "product"] as Kind[]).map((value) => <button key={value} type="button" onClick={() => begin(value)} className="inline-flex min-h-10 items-center gap-2 rounded-full border border-black/10 bg-white px-4 text-sm font-semibold hover:bg-[#e9eadf]"><Plus className="size-4" />Thêm {labels[value]}</button>)}</div></div>
        <div className="mt-5 grid gap-4 lg:grid-cols-2">
          <div><h3 className="text-sm font-semibold">Nhóm vật tư</h3><div className="mt-2 flex flex-wrap gap-2">{source.categories.map((category) => <button key={category.id} type="button" onClick={() => begin("category", category)} className="inline-flex min-h-9 items-center gap-2 rounded-full border border-black/10 bg-white px-3 text-xs hover:bg-[#e9eadf]"><Pencil className="size-3" />{category.name}{!category.is_active && <span className="text-red-700">Đã ngừng</span>}</button>)}</div></div>
          <div><h3 className="text-sm font-semibold">Đơn vị tính</h3><div className="mt-2 flex flex-wrap gap-2">{source.units.map((unit) => <button key={unit.id} type="button" onClick={() => begin("unit", unit)} className="inline-flex min-h-9 items-center gap-2 rounded-full border border-black/10 bg-white px-3 text-xs hover:bg-[#e9eadf]"><Pencil className="size-3" />{unit.name}{!unit.is_active && <span className="text-red-700">Đã ngừng</span>}</button>)}</div></div>
        </div>
        <div className="mt-4"><h3 className="text-sm font-semibold">Vật tư trên trang hiện tại</h3><div className="mt-2 flex flex-wrap gap-2">{source.data.map((product) => <button key={product.id} type="button" onClick={() => begin("product", product)} className="inline-flex min-h-9 items-center gap-2 rounded-full border border-black/10 bg-white px-3 text-xs hover:bg-[#e9eadf]"><Pencil className="size-3" />{product.name}{!product.is_active && <span className="text-red-700">Đã ngừng</span>}</button>)}</div></div>
        {success && <p role="status" className="mt-3 text-sm text-green-800">{success}</p>}
      </section>

      <Sheet open={open} onOpenChange={(value) => { if (!saving) setOpen(value) }}>
        <SheetContent side="right" className="data-[side=right]:w-full data-[side=right]:sm:w-[32rem] data-[side=right]:sm:max-w-none overflow-y-auto bg-[#fbfaf5] p-6">
          <SheetTitle className="text-xl">{editing ? "Sửa" : "Thêm"} {labels[kind]}</SheetTitle>
          <SheetDescription className="mt-2">Dữ liệu dùng chung cho mọi chuỗi. Ngừng dùng giữ lại bản ghi lịch sử.</SheetDescription>
          <form onSubmit={save} className="mt-7 space-y-4">
            <label className="block text-sm font-medium">Mã<input required maxLength={kind === "product" ? 60 : 40} value={form.code} onChange={(event) => setField("code", event.target.value)} className={inputClass} /></label>
            <label className="block text-sm font-medium">Tên<input required maxLength={kind === "product" ? 200 : kind === "category" ? 160 : 100} value={form.name} onChange={(event) => setField("name", event.target.value)} className={inputClass} /></label>
            {kind === "category" && <label className="block text-sm font-medium">Nhóm cha<select value={form.parent_id} onChange={(event) => setField("parent_id", event.target.value)} className={inputClass}><option value="">Không có</option>{activeCategories.filter((item) => item.id !== editing?.id).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>}
            {kind === "product" && <><label className="block text-sm font-medium">Nhóm vật tư<select required value={form.category_id} onChange={(event) => setField("category_id", event.target.value)} className={inputClass}><option value="">Chọn nhóm</option>{activeCategories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="block text-sm font-medium">Đơn vị tính<select required value={form.unit_id} onChange={(event) => setField("unit_id", event.target.value)} className={inputClass}><option value="">Chọn đơn vị</option>{activeUnits.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="block text-sm font-medium">Hoạt chất<input maxLength={200} value={form.active_ingredient} onChange={(event) => setField("active_ingredient", event.target.value)} className={inputClass} /></label><label className="block text-sm font-medium">Giá bán cơ sở (VND)<input type="number" min="0" step="0.01" required value={form.sale_price} onChange={(event) => setField("sale_price", event.target.value)} className={inputClass} /></label><label className="block text-sm font-medium">Thuế suất (%)<input type="number" min="0" max="100" step="0.01" value={form.tax_rate} onChange={(event) => setField("tax_rate", event.target.value)} placeholder="Chưa cấu hình" className={inputClass} /><span className="mt-1 block text-xs font-normal text-muted-foreground">Cần cấu hình trước khi bán. Để trống chưa được tính là 0%.</span></label><label className="block text-sm font-medium">Báo cận hạn trước (ngày)<input type="number" min="0" max="3650" step="1" value={form.expiry_warning_days} onChange={(event) => setField("expiry_warning_days", event.target.value)} placeholder="Mặc định 30 ngày" className={inputClass} /><span className="mt-1 block text-xs font-normal text-muted-foreground">Để trống dùng mặc định 30 ngày tại mọi kho.</span></label></>}
            <label className="flex items-start gap-3 rounded-xl border border-black/10 bg-white p-3 text-sm"><input type="checkbox" checked={form.is_active} onChange={(event) => setField("is_active", event.target.checked)} className="mt-1 size-4 accent-[#274f3a]" /><span><span className="block font-semibold">Còn sử dụng</span><span className="text-muted-foreground">Tắt để không cho chọn trong nghiệp vụ mới. Lịch sử vẫn được giữ.</span></span></label>
            {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{error}</p>}
            <div className="flex justify-end gap-2"><button type="button" onClick={() => setOpen(false)} disabled={saving} className="min-h-11 rounded-full border border-black/10 px-5 text-sm font-semibold disabled:opacity-50">Hủy</button><button type="submit" disabled={saving} className="min-h-11 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu…" : editing ? "Lưu thay đổi" : "Thêm mới"}</button></div>
          </form>
        </SheetContent>
      </Sheet>
    </>
  )
}
