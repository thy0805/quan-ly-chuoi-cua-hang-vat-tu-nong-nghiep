import { cookies } from "next/headers"
import { redirect } from "next/navigation"
import type { Profile } from "@/lib/api"

export default async function ReportsLayout({ children }: { children: React.ReactNode }) {
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
    return <p role="alert" className="p-8 text-sm text-red-800">Không kết nối được máy chủ xác thực.</p>
  }
  if (response.status === 401) redirect("/login")
  if (!response.ok) return <p role="alert" className="p-8 text-sm text-red-800">Không xác minh được quyền xem báo cáo.</p>
  const profile = await response.json() as Profile
  if (!profile.user.can_view_reports) redirect("/admin")
  return children
}
