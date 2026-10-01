import assert from "node:assert/strict"
import test from "node:test"
import { syncNotifications } from "./notifications.mjs"

test("mở và giải quyết cùng sự cố đồng thời không để lại thông báo chưa giải quyết", async () => {
  const documents = new Map()
  let resolvedAt = null
  let tail = Promise.resolve()
  let insertStarted
  const started = new Promise((resolve) => { insertStarted = resolve })
  let allowInsert
  const insertGate = new Promise((resolve) => { allowInsert = resolve })
  const pool = {
    async query() { return { rows: [{ status: resolvedAt ? "resolved" : "open", resolved_at: resolvedAt }] } },
    async connect() {
      let releaseLock = () => {}
      return {
        async query(sql) {
          if (sql.includes("pg_advisory_unlock")) { releaseLock(); return { rows: [] } }
          if (sql.includes("pg_advisory_lock")) {
            const previous = tail
            tail = new Promise((resolve) => { releaseLock = resolve })
            await previous
            return { rows: [] }
          }
          return pool.query()
        },
        release() {},
      }
    },
  }
  const database = { collection: () => ({
    async updateOne(filter, update) {
      insertStarted()
      await insertGate
      const document = documents.get(filter._id) ?? { ...update.$setOnInsert }
      documents.set(filter._id, { ...document, ...update.$set })
    },
    async updateMany(filter, update) {
      for (const [id, document] of documents) {
        if (document.incident_id === filter.incident_id) documents.set(id, { ...document, ...update.$set })
      }
    },
  }) }
  const opened = {
    id: "1", aggregate_id: "10", event_type: "inventory.alert_opened", created_at: "2026-10-01T00:00:00Z",
    payload: { recipient_user_ids: ["2"], branch_id: "3", kind: "low_stock", message: "Tồn thấp" },
  }
  const opening = syncNotifications(pool, database, opened)
  await started
  resolvedAt = new Date("2026-10-01T00:01:00Z")
  const resolving = syncNotifications(pool, database, { id: "4", aggregate_id: "10", event_type: "inventory.alert_resolved" })
  await new Promise((resolve) => setImmediate(resolve))
  allowInsert()
  await Promise.all([opening, resolving])
  assert.deepEqual(documents.get("1:2").resolved_at, resolvedAt)
  documents.get("1:2").status = "read"
  await syncNotifications(pool, database, opened)
  assert.equal(documents.size, 1)
  assert.equal(documents.get("1:2").status, "read")
  assert.deepEqual(documents.get("1:2").resolved_at, resolvedAt)
})
