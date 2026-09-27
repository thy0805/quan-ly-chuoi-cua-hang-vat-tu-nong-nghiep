ALTER TABLE outbox_events
    ADD COLUMN IF NOT EXISTS event_version INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_error TEXT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_outbox_delivery_status') THEN
        ALTER TABLE outbox_events ADD CONSTRAINT ck_outbox_delivery_status
            CHECK (status IN ('pending', 'processing', 'retry', 'failed', 'published'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_outbox_delivery_attempts') THEN
        ALTER TABLE outbox_events ADD CONSTRAINT ck_outbox_delivery_attempts
            CHECK (event_version > 0 AND attempt_count >= 0);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_outbox_delivery_due
    ON outbox_events (next_attempt_at, id)
    WHERE status IN ('pending', 'retry', 'processing');
