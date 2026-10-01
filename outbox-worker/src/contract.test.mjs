import assert from "node:assert/strict"
import test from "node:test"
import { auditDocument, backoffSeconds, decimalId } from "./contract.mjs"

test("ID PostgreSQL vượt 2^53 vẫn giữ nguyên khi sang Mongo", () => {
  const id = "9007199254740993"
  assert.equal(decimalId(id), id)
  const document = auditDocument({
    id, aggregate_id: "9007199254740994", aggregate_type: "sales_order",
    event_type: "sale.confirmed", event_version: 1,
    created_at: "2026-09-27T00:00:00.000Z",
    payload: { actor_id: "9007199254740995", branch_id: "9007199254740996" },
  })
  assert.equal(document._id, id)
  assert.equal(document.aggregate_id, "9007199254740994")
  assert.equal(document.actor_id, "9007199254740995")
})

test("lịch retry có giới hạn", () => {
  assert.equal(backoffSeconds(1), 30)
  assert.equal(backoffSeconds(2), 60)
  assert.equal(backoffSeconds(10), 3600)
})

test("ID sai kiểu hoặc vượt PostgreSQL BIGINT bị từ chối trước khi ghi Mongo", () => {
  for (const value of [9007199254740993, 1, 1n, null, "0", "01", "9223372036854775808"]) {
    assert.throws(() => decimalId(value))
  }
  assert.equal(decimalId("9223372036854775807"), "9223372036854775807")
  assert.throws(() => auditDocument({
    id: "1", aggregate_id: "2", aggregate_type: "sale", event_type: "sale.confirmed",
    created_at: "2026-10-01T00:00:00Z", event_version: 1, payload: { actor_id: 9007199254740993 },
  }))
})
