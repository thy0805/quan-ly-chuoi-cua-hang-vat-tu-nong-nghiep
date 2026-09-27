import { decimalId } from "./contract.mjs"

const timezone = "Asia/Ho_Chi_Minh"

function cents(value) {
  const text = String(value ?? "0")
  if (!/^-?\d+(\.\d{1,2})?$/.test(text)) throw new Error(`Số tiền snapshot không hợp lệ: ${text}`)
  const negative = text.startsWith("-")
  const [whole, fraction = ""] = (negative ? text.slice(1) : text).split(".")
  const amount = BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0"))
  return negative ? -amount : amount
}

function money(value) {
  const sign = value < 0n ? "-" : ""
  const positive = value < 0n ? -value : value
  return `${sign}${positive / 100n}.${String(positive % 100n).padStart(2, "0")}`
}

export function metricsFromTotals(row) {
  const gross = cents(row.gross_sales)
  const discount = cents(row.total_discount)
  const tax = cents(row.total_tax)
  const cost = cents(row.cogs)
  const collected = cents(row.amount_collected)
  const net = gross - discount
  const invoice = net + tax
  const costMissing = Number(row.incomplete_cost_count) > 0
  const taxMissing = Number(row.incomplete_tax_count) > 0
  return {
    invoice_count: Number(row.invoice_count), gross_sales: money(gross), total_discount: money(discount),
    net_sales: money(net), total_tax: taxMissing ? null : money(tax),
    invoice_total: taxMissing ? null : money(invoice),
    cogs: costMissing ? null : money(cost), gross_profit: costMissing ? null : money(net - cost),
    amount_collected: money(collected), receivable_remaining: taxMissing ? null : money(invoice - collected),
    incomplete_cost_count: Number(row.incomplete_cost_count),
    incomplete_tax_count: Number(row.incomplete_tax_count),
    invoice_mismatch_count: Number(row.invoice_mismatch_count),
  }
}

function windowBounds(period, start) {
  const [year, month, day] = start.split("-").map(Number)
  const next = new Date(Date.UTC(year, month - 1, day))
  if (period === "day") next.setUTCDate(next.getUTCDate() + 1)
  if (period === "month") next.setUTCMonth(next.getUTCMonth() + 1)
  if (period === "year") next.setUTCFullYear(next.getUTCFullYear() + 1)
  const end = next.toISOString().slice(0, 10)
  return [new Date(`${start}T00:00:00+07:00`), new Date(`${end}T00:00:00+07:00`)]
}

async function sourceTotals(client, chainId, branchId, period, start) {
  const [from, to] = windowBounds(period, start)
  const result = await client.query(`
    SELECT COUNT(*)::text AS invoice_count,
      COALESCE(SUM(item.gross_sales), 0)::text AS gross_sales,
      COALESCE(SUM(item.total_discount), 0)::text AS total_discount,
      COALESCE(SUM(item.total_tax), 0)::text AS total_tax,
      COALESCE(SUM(item.cogs), 0)::text AS cogs,
      COALESCE(SUM(payment.amount_collected), 0)::text AS amount_collected,
      COALESCE(SUM(CASE WHEN item.incomplete_cost_items > 0 THEN 1 ELSE 0 END), 0)::text AS incomplete_cost_count,
      COALESCE(SUM(CASE WHEN item.incomplete_tax_items > 0 THEN 1 ELSE 0 END), 0)::text AS incomplete_tax_count,
      COALESCE(SUM(CASE WHEN invoice.total_amount <> item.gross_sales - item.total_discount + COALESCE(item.total_tax, 0) THEN 1 ELSE 0 END), 0)::text AS invoice_mismatch_count
    FROM sales_orders AS sale
    JOIN branches AS branch ON branch.id = sale.branch_id
    JOIN invoices AS invoice ON invoice.sales_order_id = sale.id
    JOIN LATERAL (
      SELECT COUNT(*) AS item_count, SUM(ROUND(quantity * unit_price, 2)) AS gross_sales,
        SUM(discount_amount) AS total_discount, SUM(tax_amount) AS total_tax,
        SUM(ROUND(quantity * unit_cost_snapshot, 2)) AS cogs,
        SUM(CASE WHEN unit_cost_snapshot IS NULL THEN 1 ELSE 0 END) AS incomplete_cost_items,
        SUM(CASE WHEN tax_rate_snapshot IS NULL OR tax_amount IS NULL THEN 1 ELSE 0 END) AS incomplete_tax_items
      FROM sales_order_items WHERE order_id = sale.id
    ) AS item ON item.item_count > 0
    LEFT JOIN LATERAL (
      SELECT SUM(amount) AS amount_collected FROM payments
      WHERE invoice_id = invoice.id AND status = 'completed'
    ) AS payment ON TRUE
    WHERE sale.status = 'confirmed' AND branch.chain_id = $1
      AND ($2::bigint IS NULL OR sale.branch_id = $2)
      AND sale.sold_at >= $3 AND sale.sold_at < $4`,
  [chainId, branchId, from, to])
  return metricsFromTotals(result.rows[0])
}

async function rebuildWindow(pool, database, chainId, branchId, period, start, sourceEventId) {
  const key = `${chainId}:${branchId ?? "all"}:${period}:${start}`
  const client = await pool.connect()
  try {
    await client.query("SELECT pg_advisory_lock(hashtext($1))", [key])
    const metrics = await sourceTotals(client, chainId, branchId, period, start)
    await database.collection("dashboard_snapshots").replaceOne({ _id: key }, {
      _id: key, chain_id: chainId, branch_id: branchId, period,
      period_start: start, metrics, source_event_id: sourceEventId, updated_at: new Date(),
    }, { upsert: true })
  } finally {
    try { await client.query("SELECT pg_advisory_unlock(hashtext($1))", [key]) }
    finally { client.release() }
  }
}

export async function rebuildForOrder(pool, database, orderId, sourceEventId = null, visited = new Set()) {
  const result = await pool.query(`SELECT sale.branch_id::text, branch.chain_id::text,
      to_char(sale.sold_at AT TIME ZONE '${timezone}', 'YYYY-MM-DD') AS day,
      to_char(sale.sold_at AT TIME ZONE '${timezone}', 'YYYY-MM-01') AS month,
      to_char(sale.sold_at AT TIME ZONE '${timezone}', 'YYYY-01-01') AS year
    FROM sales_orders AS sale JOIN branches AS branch ON branch.id = sale.branch_id WHERE sale.id = $1`, [decimalId(orderId)])
  const row = result.rows[0]
  if (!row) throw new Error("Đơn bán của snapshot không còn tồn tại")
  for (const [period, start] of [["day", row.day], ["month", row.month], ["year", row.year]]) {
    for (const branchId of [row.branch_id, null]) {
      const key = `${row.chain_id}:${branchId ?? "all"}:${period}:${start}`
      if (visited.has(key)) continue
      await rebuildWindow(pool, database, row.chain_id, branchId, period, start, sourceEventId)
      visited.add(key)
    }
  }
}

export async function rebuildForEvent(pool, database, event) {
  let orderId = null
  if (event.event_type === "sale.confirmed") orderId = decimalId(event.aggregate_id)
  if (event.event_type === "debt.payment_recorded") {
    const payload = typeof event.payload === "string" ? JSON.parse(event.payload) : event.payload
    if (payload.source_type !== "invoice") return
    const invoice = await pool.query("SELECT sales_order_id::text FROM invoices WHERE id = $1", [decimalId(payload.source_id)])
    if (!invoice.rows[0]) throw new Error("Hóa đơn của snapshot không còn tồn tại")
    orderId = invoice.rows[0].sales_order_id
  }
  if (orderId !== null) await rebuildForOrder(pool, database, orderId, decimalId(event.id))
}

export async function rebuildAll(pool, database) {
  const result = await pool.query("SELECT id::text FROM sales_orders WHERE status = 'confirmed' ORDER BY id")
  const visited = new Set()
  for (const row of result.rows) await rebuildForOrder(pool, database, row.id, null, visited)
  return visited.size
}
