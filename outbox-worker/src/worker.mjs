import { MongoClient } from "mongodb"
import pg from "pg"
import { auditDocument, backoffSeconds, safeError } from "./contract.mjs"
import { syncNotifications } from "./notifications.mjs"
import { ensureCollections } from "./schema.mjs"
import { rebuildForEvent } from "./snapshots.mjs"

const required = ["DB_HOST", "DB_PORT", "DB_DATABASE", "DB_USERNAME"]
for (const key of required) if (!process.env[key]) throw new Error(`Thiếu cấu hình ${key}`)
const mongoUri = process.env.MONGODB_URI ?? (process.env.DB_DATABASE === "klcn186_dev" ? "mongodb://127.0.0.1:27017" : null)
const mongoDatabase = process.env.MONGODB_DATABASE ?? (process.env.DB_DATABASE === "klcn186_dev" ? "klcn186_dev" : null)
if (!mongoUri || !mongoDatabase) throw new Error("Thiếu MONGODB_URI hoặc MONGODB_DATABASE")

const pool = new pg.Pool({
  host: process.env.DB_HOST, port: Number(process.env.DB_PORT), database: process.env.DB_DATABASE,
  user: process.env.DB_USERNAME, password: process.env.DB_PASSWORD ?? "", max: 2,
})
const mongo = new MongoClient(mongoUri, { serverSelectionTimeoutMS: 2500 })
const database = mongo.db(mongoDatabase)
let schemaReady = false
let stopping = false
process.on("SIGINT", () => { stopping = true })
process.on("SIGTERM", () => { stopping = true })

async function claimOne() {
  const client = await pool.connect()
  try {
    await client.query("BEGIN")
    await client.query(`UPDATE outbox_events SET status = 'failed', locked_at = NULL,
      last_error = 'Worker interrupted after final attempt'
      WHERE status = 'processing' AND attempt_count >= 5
        AND locked_at < now() - interval '2 minutes'`)
    const result = await client.query(`
      WITH candidate AS (
        SELECT id FROM outbox_events
        WHERE (status IN ('pending', 'retry') AND next_attempt_at <= now())
           OR (status = 'processing' AND attempt_count < 5 AND locked_at < now() - interval '2 minutes')
        ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED
      )
      UPDATE outbox_events AS event SET status = 'processing', locked_at = now(),
          attempt_count = event.attempt_count + 1
      FROM candidate WHERE event.id = candidate.id
      RETURNING event.*`)
    await client.query("COMMIT")
    return result.rows[0] ?? null
  } catch (error) {
    await client.query("ROLLBACK")
    throw error
  } finally { client.release() }
}

async function deliver(event) {
  try {
    if (!schemaReady) {
      await mongo.connect()
      await ensureCollections(database)
      schemaReady = true
    }
    await database.collection("audit_logs").replaceOne({ _id: String(event.id) }, auditDocument(event), { upsert: true })
    await syncNotifications(pool, database, event)
    await rebuildForEvent(pool, database, event)
    const result = await pool.query(`UPDATE outbox_events SET status = 'published', published_at = now(),
      locked_at = NULL, last_error = NULL WHERE id = $1 AND status = 'processing' AND attempt_count = $2`,
    [event.id, event.attempt_count])
    if (result.rowCount !== 1) throw new Error("Trạng thái outbox đã thay đổi trong lúc xử lý")
    process.stdout.write(JSON.stringify({ event_id: String(event.id), status: "published" }) + "\n")
    return true
  } catch (error) {
    const failed = Number(event.attempt_count) >= 5
    await pool.query(`UPDATE outbox_events SET status = $3, locked_at = NULL, last_error = $4,
      next_attempt_at = now() + ($5 * interval '1 second')
      WHERE id = $1 AND status = 'processing' AND attempt_count = $2`,
    [event.id, event.attempt_count, failed ? "failed" : "retry", safeError(error, mongoUri), backoffSeconds(Number(event.attempt_count))])
    process.stderr.write(JSON.stringify({ event_id: String(event.id), status: failed ? "failed" : "retry" }) + "\n")
    return false
  }
}

async function main() {
  let processed = 0
  let errors = 0
  const once = process.argv.includes("--once")
  try {
    while (!stopping) {
      const event = await claimOne()
      if (event) {
        processed += 1
        if (!await deliver(event)) errors += 1
        if (once && processed >= 100) break
      } else if (once) break
      else await new Promise((resolve) => setTimeout(resolve, 5000))
    }
  } finally {
    await mongo.close()
    await pool.end()
  }
  process.stdout.write(JSON.stringify({ processed, errors }) + "\n")
  if (errors > 0) process.exitCode = 1
}

await main()
