export const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:8000"

export class ApiError extends Error {
  constructor(message: string, public status: number) {
    super(message)
  }
}

function xsrfToken() {
  const cookie = document.cookie.split("; ").find((part) => part.startsWith("XSRF-TOKEN="))
  return cookie ? decodeURIComponent(cookie.slice("XSRF-TOKEN=".length)) : null
}

export async function apiFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  headers.set("Accept", "application/json")

  if (init.body) headers.set("Content-Type", "application/json")
  if (init.method && init.method !== "GET") {
    const token = xsrfToken()
    if (token) headers.set("X-XSRF-TOKEN", token)
  }

  let response: Response

  try {
    response = await fetch(`${apiUrl}${path}`, { ...init, headers, credentials: "include" })
  } catch {
    throw new ApiError("Không kết nối được Laravel API.", 0)
  }

  const body = await response.json().catch(() => null)
  if (!response.ok) {
    const message = response.status >= 500
      ? "Máy chủ đang gặp lỗi. Vui lòng thử lại sau."
      : response.status === 419
        ? "Phiên đăng nhập đã hết hạn. Vui lòng thử lại."
        : body?.message ?? `Yêu cầu thất bại (${response.status}).`
    throw new ApiError(message, response.status)
  }

  return body as T
}

export async function login(username: string, password: string) {
  const response = await fetch(`${apiUrl}/sanctum/csrf-cookie`, {
    credentials: "include",
    headers: { Accept: "application/json" },
  }).catch(() => null)

  if (!response?.ok) throw new ApiError("Không khởi tạo được phiên đăng nhập.", response?.status ?? 0)

  return apiFetch<{ user: { id: string; username: string } }>("/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  })
}

export async function logout() {
  return apiFetch<{ message: string }>("/logout", { method: "POST" })
}

export type Branch = {
  id: string
  chain_id: string
  code: string
  name: string
}

export type Profile = {
  user: { id: string; username: string; can_manage_catalog: boolean }
  branches: Branch[]
}

export type InventoryItem = {
  id: string
  quantity: string
  product_code: string
  product_name: string
  branch_id: string
  branch_name: string
  warehouse_name: string
  lot_no: string
  expires_on: string | null
  unit_name: string
  status: string
}

export type InventoryResponse = {
  data: InventoryItem[]
  summary: {
    inventory_rows: number
    expiring_lots: number
    branches_with_stock: number
  }
  branches: Branch[]
  pagination: {
    current_page: number
    last_page: number
    total: number
  }
}

export type CatalogProduct = {
  id: string
  code: string
  name: string
  active_ingredient: string | null
  sale_price: string
  tax_rate: string | null
  expiry_warning_days: number | null
  is_active: boolean
  category_id: string
  category_name: string
  category_is_active: boolean
  unit_id: string
  unit_code: string
  unit_name: string
  unit_is_active: boolean
}

export type CatalogCategory = {
  id: string
  parent_id: string | null
  code: string
  name: string
  is_active: boolean
}

export type CatalogResponse = {
  data: CatalogProduct[]
  categories: CatalogCategory[]
  units: { id: string; code: string; name: string; is_active: boolean }[]
  pagination: { current_page: number; last_page: number; total: number }
}

export type OrganizationResponse = {
  chains: { id: string; name: string; is_active: boolean }[]
  branches: { id: string; chain_id: string; code: string; name: string; address: string | null; default_sales_warehouse_id: string | null; is_active: boolean }[]
  warehouses: { id: string; branch_id: string; code: string; name: string; warehouse_type: string }[]
  manageable_chain_ids: string[]
}

export type Supplier = { id: string; chain_id: string; chain_name: string; name: string; phone: string | null; address: string | null }
export type SupplierResponse = {
  data: Supplier[]
  chains: { id: string; name: string }[]
  can_manage: boolean
  pagination: { current_page: number; last_page: number; total: number }
}

export type Customer = { id: string; chain_id: string; chain_name: string; name: string; customer_type: string; phone: string | null; address: string | null }
export type CustomerResponse = {
  data: Customer[]
  chains: { id: string; name: string }[]
  can_manage: boolean
  pagination: { current_page: number; last_page: number; total: number }
}

export type ManagedAssignment = { id: string; user_id: string; branch_id: string; branch_name: string; chain_id: string; role_code: string; status: string; starts_on: string; can_revoke: boolean }
export type ManagedUser = { id: string; username: string; is_active: boolean; is_catalog_admin: boolean; can_toggle_active: boolean; lock_reason: string | null; assignments: ManagedAssignment[] }
export type UserManagementResponse = {
  data: ManagedUser[]
  branches: { id: string; chain_id: string; name: string; code: string }[]
  chains: { id: string; name: string }[]
  roles: { code: string; name: string }[]
  pagination: { current_page: number; last_page: number; total: number }
}

export type PurchaseReceipt = {
  id: string
  receipt_no: string
  status: "draft" | "submitted" | "approved" | "rejected"
  total_amount: string
  received_at: string
  created_by: string
  approved_by: string | null
  rejected_by: string | null
  branch_id: string
  chain_id: string
  branch_name: string
  warehouse_id: string
  warehouse_name: string
  supplier_id: string
  supplier_name: string
  creator_name?: string
  rejection_reason?: string | null
  can_edit: boolean
  can_submit: boolean
  can_approve: boolean
  can_reject: boolean
}

export type PurchaseReceiptItem = {
  id: string
  lot_id: string
  quantity: string
  unit_cost: string
  line_total: string
  lot_no: string
  manufactured_on: string | null
  expires_on: string | null
  product_id: string
  product_code: string
  product_name: string
  unit_name: string
}

export type PurchaseReceiptResponse = {
  data: PurchaseReceipt[]
  branches: Branch[]
  pagination: { current_page: number; last_page: number; total: number }
}

export type PurchaseReceiptDetail = { data: PurchaseReceipt; items: PurchaseReceiptItem[] }

export type PurchaseReceiptOptions = {
  warehouses: { id: string; name: string; branch_id: string; branch_name: string; chain_id: string }[]
  suppliers: { id: string; chain_id: string; name: string }[]
}
