"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { LockKeyhole, Plus, RotateCw, Search, ShieldCheck, UserRound } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { ApiError, apiFetch, type ManagedUser, type UserManagementResponse } from "@/lib/api"

const roleNames: Record<string, string> = { chain_owner: "Chủ chuỗi", branch_manager: "Quản lý chi nhánh", sales_staff: "Nhân viên bán hàng" }

export default function UsersPage() {
  const router = useRouter()
  const [result, setResult] = useState<UserManagementResponse | null>(null)
  const [search, setSearch] = useState("")
  const [page, setPage] = useState(1)
  const [reload, setReload] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [open, setOpen] = useState(false)
  const [mode, setMode] = useState<"create" | "grant">("create")
  const [selected, setSelected] = useState<ManagedUser | null>(null)
  const [form, setForm] = useState({ username: "", password: "", branch_id: "", role_code: "sales_staff" })
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState("")
  const [busyUser, setBusyUser] = useState<string | null>(null)

  useEffect(() => {
    const controller = new AbortController()
    const timer = window.setTimeout(async () => {
      setLoading(true)
      setError("")
      const params = new URLSearchParams({ page: String(page), per_page: "20" })
      if (search.trim()) params.set("search", search.trim())
      try {
        const data = await apiFetch<UserManagementResponse>(`/api/users?${params}`, { signal: controller.signal })
        if (!controller.signal.aborted) setResult(data)
      } catch (caught) {
        if (controller.signal.aborted) return
        if (caught instanceof ApiError && caught.status === 401) { router.replace("/login"); return }
        setResult(null)
        setError(caught instanceof Error ? caught.message : "Không tải được tài khoản.")
      } finally { if (!controller.signal.aborted) setLoading(false) }
    }, search ? 250 : 0)
    return () => { window.clearTimeout(timer); controller.abort() }
  }, [page, reload, router, search])

  function begin(nextMode: "create" | "grant", user: ManagedUser | null = null) {
    setMode(nextMode)
    setSelected(user)
    setForm({ username: "", password: "", branch_id: String(result?.branches[0]?.id ?? ""), role_code: "sales_staff" })
    setFormError("")
    setOpen(true)
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saving) return
    setSaving(true)
    setFormError("")
    try {
      const body = { branch_id: form.branch_id, role_code: form.role_code, ...(mode === "create" && { username: form.username.trim(), password: form.password }) }
      await apiFetch(mode === "create" ? "/api/users" : `/api/users/${selected?.id}/assignments`, { method: "POST", body: JSON.stringify(body) })
      setOpen(false)
      setForm({ username: "", password: "", branch_id: "", role_code: "sales_staff" })
      setSuccess(mode === "create" ? "Đã tạo tài khoản và phân quyền." : "Đã cấp quyền cho tài khoản.")
      setReload((value) => value + 1)
    } catch (caught) { setFormError(caught instanceof Error ? caught.message : "Không lưu được tài khoản.") }
    finally { setSaving(false) }
  }

  async function changeActive(user: ManagedUser) {
    if (busyUser !== null) return
    setBusyUser(user.id)
    setError("")
    try {
      await apiFetch(`/api/users/${user.id}/active`, { method: "PATCH", body: JSON.stringify({ is_active: !user.is_active }) })
      setSuccess(user.is_active ? "Đã khóa tài khoản." : "Đã mở lại tài khoản.")
      setReload((value) => value + 1)
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Không đổi được trạng thái tài khoản.") }
    finally { setBusyUser(null) }
  }

  async function revoke(assignmentId: string) {
    if (busyUser !== null) return
    setBusyUser(assignmentId)
    setError("")
    try {
      await apiFetch(`/api/assignments/${assignmentId}/revoke`, { method: "POST" })
      setSuccess("Đã thu quyền. Lịch sử phân công vẫn được giữ.")
      setReload((value) => value + 1)
    } catch (caught) { setError(caught instanceof Error ? caught.message : "Không thu được quyền.") }
    finally { setBusyUser(null) }
  }

  const inputClass = "mt-1 h-11 w-full rounded-xl border border-black/10 bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[#274f3a]"

  return <main className="p-5 lg:p-8"><div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-medium text-primary">Truy cập nội bộ</p><h1 className="mt-2 text-3xl font-semibold tracking-[-0.045em]">Tài khoản và phân quyền</h1><p className="mt-2 text-sm text-muted-foreground">Quản lý người dùng trong chuỗi của bạn. Mỗi chuỗi luôn cần ít nhất một Chủ chuỗi hoạt động.</p></div>{result && <button type="button" onClick={() => begin("create")} className="inline-flex min-h-11 items-center gap-2 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white"><Plus className="size-4" />Tạo tài khoản</button>}</div>
    {success && <p role="status" className="mt-5 rounded-xl bg-[#e1e5d3] p-3 text-sm text-[#274f3a]">{success}</p>}
    {error && <div role="alert" className="mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span>{error}</span><button type="button" onClick={() => setReload((value) => value + 1)} className="inline-flex min-h-10 items-center gap-2 rounded-lg border border-red-300 px-3 font-semibold"><RotateCw className="size-4" />Thử lại</button></div>}
    <Card className="mt-7 border-black/8 bg-[#fbfaf5] shadow-none"><CardHeader className="gap-4 sm:flex-row sm:items-center sm:justify-between"><div><CardTitle className="text-lg">Người dùng trong phạm vi</CardTitle><p className="mt-1 text-sm text-muted-foreground">Quyền danh mục chung được chỉ định riêng, không cấp tại màn này.</p></div><label className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" /><input aria-label="Tìm tài khoản" value={search} onChange={(event) => { setSearch(event.target.value); setPage(1); setResult(null) }} placeholder="Tìm username" className="h-11 w-full rounded-xl border border-black/10 bg-white pl-9 pr-3 text-sm sm:w-64" /></label></CardHeader><CardContent><div className="space-y-3">{loading && <div role="status" className="space-y-3"><span className="sr-only">Đang tải tài khoản</span>{[1, 2, 3].map((item) => <Skeleton key={item} className="h-32 w-full rounded-xl" />)}</div>}{!loading && !error && result?.data.length === 0 && <div className="py-12 text-center"><UserRound className="mx-auto size-9 text-muted-foreground" /><p className="mt-3 font-medium">Chưa có tài khoản phù hợp</p></div>}{!loading && result?.data.map((user) => <div key={user.id} className="rounded-xl border border-black/8 bg-white p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div className="flex items-start gap-3"><div className="grid size-10 shrink-0 place-items-center rounded-full bg-[#e1e5d3] text-[#274f3a]"><UserRound className="size-5" /></div><div><p className="font-semibold">{user.username}</p><div className="mt-1 flex flex-wrap gap-2 text-xs"><span className={`rounded-full px-2 py-1 ${user.is_active ? "bg-[#e1e5d3] text-[#274f3a]" : "bg-red-100 text-red-800"}`}>{user.is_active ? "Đang hoạt động" : "Đã khóa"}</span>{user.is_catalog_admin && <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-amber-900"><ShieldCheck className="size-3" />Quản trị danh mục chung</span>}</div></div></div><div className="flex flex-wrap gap-2"><button type="button" onClick={() => begin("grant", user)} className="min-h-9 rounded-lg border border-black/10 px-3 text-xs font-semibold hover:bg-[#f3f1e8]">Cấp quyền</button><button type="button" disabled={!user.can_toggle_active || busyUser !== null} onClick={() => changeActive(user)} title={user.lock_reason ?? undefined} className="inline-flex min-h-9 items-center gap-1 rounded-lg border border-black/10 px-3 text-xs font-semibold hover:bg-[#f3f1e8] disabled:opacity-40"><LockKeyhole className="size-3" />{user.is_active ? "Khóa" : "Mở khóa"}</button></div></div><div className="mt-4 flex flex-wrap gap-2">{user.assignments.map((assignment) => <div key={assignment.id} className={`inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-xs ${assignment.status === "active" ? "border-[#cad7c5] bg-[#f4f7ef]" : "border-black/8 bg-[#f7f6f1] text-muted-foreground"}`}><span>{roleNames[assignment.role_code] ?? assignment.role_code} · {assignment.branch_name}</span>{assignment.status === "active" ? <button type="button" disabled={busyUser !== null || !assignment.can_revoke} title={!assignment.can_revoke ? "Chuỗi phải còn Chủ chuỗi hoạt động" : undefined} onClick={() => revoke(assignment.id)} className="font-semibold text-red-700 underline-offset-2 hover:underline disabled:opacity-40">Thu quyền</button> : <span>Đã thu</span>}</div>)}</div></div>)}</div>{result && result.pagination.last_page > 1 && <div className="mt-5 flex items-center justify-end gap-3 text-sm"><button type="button" disabled={page <= 1 || loading} onClick={() => { setPage(page - 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trang trước</button><span>{result.pagination.current_page} / {result.pagination.last_page}</span><button type="button" disabled={page >= result.pagination.last_page || loading} onClick={() => { setPage(page + 1); setResult(null) }} className="min-h-10 rounded-lg border border-black/10 px-3 disabled:opacity-40">Trang sau</button></div>}</CardContent></Card>
    <Sheet open={open} onOpenChange={(value) => { if (!saving) setOpen(value) }}><SheetContent side="right" className="data-[side=right]:w-full data-[side=right]:sm:w-[32rem] data-[side=right]:sm:max-w-none overflow-y-auto bg-[#fbfaf5] p-6"><SheetTitle className="text-xl">{mode === "create" ? "Tạo tài khoản" : `Cấp quyền cho ${selected?.username}`}</SheetTitle><SheetDescription className="mt-2">{mode === "create" ? "Mật khẩu chỉ dùng để tạo tài khoản và không hiển thị lại." : "Chọn vai trò và chi nhánh thuộc chuỗi bạn quản lý."}</SheetDescription><form onSubmit={save} className="mt-7 space-y-4">{mode === "create" && <><label className="block text-sm font-medium">Username<input required minLength={3} maxLength={80} autoComplete="off" value={form.username} onChange={(event) => setForm({ ...form, username: event.target.value })} className={inputClass} /></label><label className="block text-sm font-medium">Mật khẩu ban đầu<input type="password" required minLength={10} maxLength={255} autoComplete="new-password" value={form.password} onChange={(event) => setForm({ ...form, password: event.target.value })} className={inputClass} /></label></>}<label className="block text-sm font-medium">Vai trò<select value={form.role_code} onChange={(event) => setForm({ ...form, role_code: event.target.value })} className={inputClass}>{result?.roles.map((role) => <option key={role.code} value={role.code}>{roleNames[role.code] ?? role.name}</option>)}</select></label><label className="block text-sm font-medium">Chi nhánh<select required value={form.branch_id} onChange={(event) => setForm({ ...form, branch_id: event.target.value })} className={inputClass}>{result?.branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name} · {branch.code}</option>)}</select></label>{formError && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{formError}</p>}<div className="flex justify-end gap-2"><button type="button" onClick={() => setOpen(false)} disabled={saving} className="min-h-11 rounded-full border border-black/10 px-5 text-sm font-semibold disabled:opacity-50">Hủy</button><button type="submit" disabled={saving} className="min-h-11 rounded-full bg-[#274f3a] px-5 text-sm font-semibold text-white disabled:opacity-50">{saving ? "Đang lưu…" : mode === "create" ? "Tạo tài khoản" : "Cấp quyền"}</button></div></form></SheetContent></Sheet>
  </main>
}
