const id = { bsonType: "string", pattern: "^[1-9][0-9]*$" }
const date = { bsonType: "date" }

const definitions = {
  product_contents: {
    required: ["_id", "product_id", "updated_at"],
    properties: {
      _id: id, product_id: id, usage_instructions: { bsonType: ["string", "null"] },
      additional_info: { bsonType: ["string", "null"] },
      images: { bsonType: "array", items: { bsonType: "string" } }, updated_at: date,
    },
    indexes: [[{ product_id: 1 }, { unique: true }]],
  },
  notifications: {
    required: ["_id", "event_id", "user_id", "branch_id", "incident_id", "kind", "status", "message", "created_at"],
    properties: {
      _id: { bsonType: "string" }, event_id: id, user_id: id, branch_id: id, incident_id: id,
      kind: { bsonType: "string" }, status: { enum: ["unread", "read"] },
      message: { bsonType: "string" }, created_at: date,
      read_at: { bsonType: ["date", "null"] }, resolved_at: { bsonType: ["date", "null"] },
    },
    indexes: [[{ event_id: 1, user_id: 1 }, { unique: true }], [{ user_id: 1, status: 1, created_at: -1 }, {}], [{ incident_id: 1 }, {}]],
  },
  audit_logs: {
    required: ["_id", "event_id", "aggregate_type", "aggregate_id", "event_type", "event_version", "occurred_at", "payload", "synced_at"],
    properties: {
      _id: id, event_id: id, aggregate_type: { bsonType: "string" }, aggregate_id: id,
      event_type: { bsonType: "string" }, event_version: { bsonType: "int" },
      actor_id: { bsonType: ["string", "null"] }, branch_id: { bsonType: ["string", "null"] },
      occurred_at: date, payload: { bsonType: "object" }, synced_at: date,
    },
    indexes: [[{ event_id: 1 }, { unique: true }], [{ aggregate_type: 1, aggregate_id: 1, occurred_at: -1 }, {}], [{ branch_id: 1, occurred_at: -1 }, {}]],
  },
  dashboard_snapshots: {
    required: ["_id", "chain_id", "period", "period_start", "metrics", "updated_at"],
    properties: {
      _id: { bsonType: "string" }, chain_id: id, branch_id: { bsonType: ["string", "null"] },
      period: { enum: ["day", "month", "year"] }, period_start: { bsonType: "string" },
      metrics: { bsonType: "object" }, source_event_id: { bsonType: ["string", "null"] }, updated_at: date,
    },
    indexes: [[{ chain_id: 1, branch_id: 1, period: 1, period_start: 1 }, { unique: true }]],
  },
}

export async function ensureCollections(database) {
  const existing = new Set((await database.listCollections({}, { nameOnly: true }).toArray()).map((item) => item.name))
  for (const [name, definition] of Object.entries(definitions)) {
    if (!existing.has(name)) {
      await database.createCollection(name, {
        validator: { $jsonSchema: { bsonType: "object", required: definition.required, properties: definition.properties } },
        validationLevel: "strict",
        validationAction: "error",
      })
    }
    for (const [keys, options] of definition.indexes) await database.collection(name).createIndex(keys, options)
  }
}
