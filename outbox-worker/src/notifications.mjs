import { decimalId } from "./contract.mjs"

export async function syncNotifications(pool, database, event) {
  if (!["inventory.alert_opened", "inventory.alert_resolved"].includes(event.event_type)) return
  const incidentId = decimalId(event.aggregate_id)
  const client = await pool.connect()
  try {
    await client.query("SELECT pg_advisory_lock(18602703, hashtext($1))", [incidentId])
    try {
      await writeNotifications(client, database, event, incidentId)
    } finally {
      await client.query("SELECT pg_advisory_unlock(18602703, hashtext($1))", [incidentId])
    }
  } finally { client.release() }
}

async function writeNotifications(client, database, event, incidentId) {
  const incident = await client.query("SELECT status, resolved_at FROM inventory_alert_incidents WHERE id = $1", [incidentId])
  if (!incident.rows[0]) throw new Error("Sự cố cảnh báo không còn tồn tại")
  const resolvedAt = incident.rows[0].resolved_at ? new Date(incident.rows[0].resolved_at) : null
  if (event.event_type === "inventory.alert_opened") {
    const payload = typeof event.payload === "string" ? JSON.parse(event.payload) : event.payload
    const users = [...new Set(payload.recipient_user_ids.map(decimalId))]
    for (const userId of users) {
      await database.collection("notifications").updateOne({ _id: `${event.id}:${userId}` }, {
        $setOnInsert: {
          event_id: decimalId(event.id), user_id: userId, branch_id: decimalId(payload.branch_id),
          incident_id: incidentId, kind: payload.kind, status: "unread", message: payload.message,
          created_at: new Date(event.created_at), read_at: null,
        },
        $set: { resolved_at: resolvedAt },
      }, { upsert: true })
    }
  } else {
    if (!resolvedAt) throw new Error("Sự cố cảnh báo chưa được giải quyết")
    await database.collection("notifications").updateMany({ incident_id: incidentId }, {
      $set: { resolved_at: resolvedAt },
    })
  }
}
