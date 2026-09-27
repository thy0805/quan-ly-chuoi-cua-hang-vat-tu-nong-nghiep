"use client"

import { useState, type FormEvent } from "react"
import { useRouter } from "next/navigation"
import { ArrowRight, LockKeyhole } from "lucide-react"
import { login } from "@/lib/api"

export default function LoginPage() {
  const router = useRouter()
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [error, setError] = useState("")
  const [pending, setPending] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setPending(true)
    setError("")

    try {
      await login(username, password)
      router.replace("/admin/inventory")
      router.refresh()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Không đăng nhập được.")
    } finally {
      setPending(false)
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#f3f1e8] px-5 py-12">
      <div className="w-full max-w-md rounded-[2rem] border border-black/10 bg-[#fbfaf5] p-8 shadow-xl shadow-[#203d2e]/5 sm:p-10">
        <div className="inline-flex items-center gap-3 text-[#203d2e]">
          <span className="grid size-11 place-items-center rounded-full bg-[#e8c675] text-sm font-bold">NG</span>
          <span className="font-semibold tracking-[-0.03em]">Nông Gia</span>
        </div>
        <div className="mt-10">
          <span className="grid size-11 place-items-center rounded-2xl bg-[#dfe7d8] text-[#274f3a]"><LockKeyhole className="size-5" /></span>
          <h1 className="mt-5 text-3xl font-semibold tracking-[-0.045em]">Đăng nhập nội bộ</h1>
          <p className="mt-2 text-sm leading-6 text-muted-foreground">Dùng tài khoản được phân công để xem dữ liệu tồn kho theo chi nhánh.</p>
        </div>
        <form onSubmit={handleSubmit} className="mt-8 space-y-5">
          <label className="block text-sm font-medium">
            Tên đăng nhập
            <input value={username} onChange={(event) => setUsername(event.target.value)} autoComplete="username" required className="mt-2 h-11 w-full rounded-xl border border-black/15 bg-white px-4 outline-none focus:border-[#274f3a]" />
          </label>
          <label className="block text-sm font-medium">
            Mật khẩu
            <input value={password} onChange={(event) => setPassword(event.target.value)} type="password" autoComplete="current-password" required className="mt-2 h-11 w-full rounded-xl border border-black/15 bg-white px-4 outline-none focus:border-[#274f3a]" />
          </label>
          {error && <p role="alert" className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-800">{error}</p>}
          <button disabled={pending} className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-[#274f3a] px-5 font-semibold text-white transition hover:bg-[#203d2e] disabled:opacity-60">
            {pending ? "Đang đăng nhập..." : "Đăng nhập"}<ArrowRight className="size-4" />
          </button>
        </form>
      </div>
    </main>
  )
}
