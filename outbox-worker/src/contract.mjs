export function decimalId(value) {
  const text = String(value)
  if (!/^[1-9]\d*$/.test(text)) throw new Error("ID phải là chuỗi thập phân dương")
  return text
}

export function backoffSeconds(attempt) {
  return Math.min(3600, 30 * 2 ** Math.max(0, attempt - 1))
}

export function auditDocument(event) {
  const payload = typeof event.payload === "string" ? JSON.parse(event.payload) : event.payload
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw new Error("Payload sự kiện không hợp lệ")
  const eventId = decimalId(event.id)
  return {
    _id: eventId,
    event_id: eventId,
    aggregate_type: event.aggregate_type,
    aggregate_id: decimalId(event.aggregate_id),
    event_type: event.event_type,
    event_version: Number(event.event_version),
    actor_id: payload.actor_id === undefined || payload.actor_id === null ? null : decimalId(payload.actor_id),
    branch_id: payload.branch_id === undefined || payload.branch_id === null
      ? payload.from_branch_id === undefined || payload.from_branch_id === null ? null : decimalId(payload.from_branch_id)
      : decimalId(payload.branch_id),
    occurred_at: new Date(event.created_at),
    payload,
    synced_at: new Date(),
  }
}

export function safeError(error, uri) {
  const name = String(error?.name ?? "Error").slice(0, 80)
  const message = String(error?.message ?? "Unknown failure").replaceAll(uri, "[redacted]").slice(0, 420)
  return `${name}: ${message}`
}
