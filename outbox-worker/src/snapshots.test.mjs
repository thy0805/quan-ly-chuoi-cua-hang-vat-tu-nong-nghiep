import assert from "node:assert/strict"
import test from "node:test"
import { metricsFromTotals, rebuildForEvent } from "./snapshots.mjs"

test("snapshot dùng đúng doanh thu trước thuế và giá vốn đã chụp", () => {
  const result = metricsFromTotals({
    invoice_count: "1", gross_sales: "200.00", total_discount: "20.00",
    total_tax: "9.00", cogs: "120.00", amount_collected: "100.00",
    incomplete_cost_count: "0", incomplete_tax_count: "0", invoice_mismatch_count: "0",
  })
  assert.deepEqual(result, {
    invoice_count: 1, gross_sales: "200.00", total_discount: "20.00", net_sales: "180.00",
    total_tax: "9.00", invoice_total: "189.00", cogs: "120.00", gross_profit: "60.00",
    amount_collected: "100.00", receivable_remaining: "89.00",
    incomplete_cost_count: 0, incomplete_tax_count: 0, invoice_mismatch_count: 0,
  })
})

test("snapshot giữ tiền chính xác trên giới hạn Number an toàn", () => {
  const result = metricsFromTotals({
    invoice_count: "1", gross_sales: "9007199254740993.00", total_discount: "1.00",
    total_tax: "0.00", cogs: "2.00", amount_collected: "0.00",
    incomplete_cost_count: "0", incomplete_tax_count: "0", invoice_mismatch_count: "0",
  })
  assert.equal(result.net_sales, "9007199254740992.00")
  assert.equal(result.gross_profit, "9007199254740990.00")
})

test("snapshot không hiển thị lợi nhuận khi thiếu giá vốn", () => {
  const result = metricsFromTotals({
    invoice_count: "1", gross_sales: "100.00", total_discount: "0.00",
    total_tax: "0.00", cogs: "0.00", amount_collected: "0.00",
    incomplete_cost_count: "1", incomplete_tax_count: "0", invoice_mismatch_count: "0",
  })
  assert.equal(result.cogs, null)
  assert.equal(result.gross_profit, null)
})

test("sự kiện thu nợ dựng lại cùng sáu snapshot, chạy lại không nhân đôi", async () => {
  const documents = new Map()
  let collected = "100.00"
  const totals = () => ({
    invoice_count: "1", gross_sales: "200.00", total_discount: "20.00",
    total_tax: "9.00", cogs: "120.00", amount_collected: collected,
    incomplete_cost_count: "0", incomplete_tax_count: "0", invoice_mismatch_count: "0",
  })
  const client = {
    async query(sql) {
      if (sql.includes("pg_advisory_")) return { rows: [] }
      return { rows: [totals()] }
    },
    release() {},
  }
  const pool = {
    async query(sql) {
      if (sql.includes("FROM invoices")) return { rows: [{ sales_order_id: "9007199254740993" }] }
      return { rows: [{ branch_id: "7", chain_id: "2", day: "2026-09-27", month: "2026-09-01", year: "2026-01-01" }] }
    },
    async connect() { return client },
  }
  const database = {
    collection() {
      return {
        async replaceOne(filter, value, options) {
          assert.equal(options.upsert, true)
          documents.set(filter._id, value)
        },
      }
    },
  }
  const event = { id: "9007199254740997", event_type: "debt.payment_recorded", payload: {
    source_type: "invoice", source_id: "9007199254740994",
  } }
  await rebuildForEvent(pool, database, event)
  assert.equal(documents.size, 6)
  assert.equal(documents.get("2:7:day:2026-09-27").metrics.receivable_remaining, "89.00")
  collected = "189.00"
  await rebuildForEvent(pool, database, event)
  assert.equal(documents.size, 6)
  assert.equal(documents.get("2:7:day:2026-09-27").metrics.receivable_remaining, "0.00")
  assert.equal(documents.get("2:all:day:2026-09-27").source_event_id, event.id)
})
