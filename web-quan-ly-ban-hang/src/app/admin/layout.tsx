import { cookies } from "next/headers"
import { redirect } from "next/navigation"
import { AdminShell } from "@/components/admin/admin-shell"
import type { Profile } from "@/lib/api"

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const session = (await cookies()).get("klcn186_api_session")
  if (!session) redirect("/login")

  let response: Response

  try {
    response = await fetch(`${process.env.API_URL ?? "http://127.0.0.1:8000"}/api/me`, {
      headers: {
        Accept: "application/json",
        Origin: "http://127.0.0.1:3210",
        Cookie: `klcn186_api_session=${encodeURIComponent(session.value)}`,
      },
      cache: "no-store",
    })
  } catch {
    return <main className="grid min-h-screen place-items-center bg-[#f3f1e8] px-5 text-center text-sm text-red-800">Không kết nối được máy chủ xác thực. Vui lòng thử lại sau.</main>
  }

  if (response.status === 401) redirect("/login")
  if (!response.ok) return <main className="grid min-h-screen place-items-center bg-[#f3f1e8] px-5 text-center text-sm text-red-800">Không xác minh được phiên đăng nhập. Vui lòng thử lại sau.</main>

  const profile = await response.json() as Profile
  return <AdminShell profile={profile}>{children}</AdminShell>
}
