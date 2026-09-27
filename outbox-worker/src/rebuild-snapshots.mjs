import { MongoClient } from "mongodb"
import pg from "pg"
import { ensureCollections } from "./schema.mjs"
import { rebuildAll } from "./snapshots.mjs"

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
try {
  await mongo.connect()
  const database = mongo.db(mongoDatabase)
  await ensureCollections(database)
  const snapshots = await rebuildAll(pool, database)
  process.stdout.write(JSON.stringify({ database: mongoDatabase, snapshots_rebuilt: snapshots }) + "\n")
} finally {
  await mongo.close()
  await pool.end()
}
