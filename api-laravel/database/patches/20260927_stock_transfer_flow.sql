ALTER TABLE stock_transfers
    ADD COLUMN IF NOT EXISTS rejected_by BIGINT REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS dispatched_by BIGINT REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS dispatched_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS received_by BIGINT REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;

ALTER TABLE stock_transfer_items
    ADD COLUMN IF NOT EXISTS transfer_unit_cost NUMERIC(18, 6);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_stock_transfers_separate_approver') THEN
        ALTER TABLE stock_transfers ADD CONSTRAINT ck_stock_transfers_separate_approver
            CHECK (approved_by IS NULL OR approved_by <> requested_by);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_stock_transfers_separate_rejecter') THEN
        ALTER TABLE stock_transfers ADD CONSTRAINT ck_stock_transfers_separate_rejecter
            CHECK (rejected_by IS NULL OR rejected_by <> requested_by);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_stock_transfer_items_flow_quantities') THEN
        ALTER TABLE stock_transfer_items ADD CONSTRAINT ck_stock_transfer_items_flow_quantities
            CHECK (dispatched_quantity <= requested_quantity AND received_quantity <= dispatched_quantity);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_stock_transfer_items_cost') THEN
        ALTER TABLE stock_transfer_items ADD CONSTRAINT ck_stock_transfer_items_cost
            CHECK (transfer_unit_cost IS NULL OR transfer_unit_cost >= 0);
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movements_transfer_out
    ON stock_movements (stock_transfer_id, warehouse_id, lot_id)
    WHERE stock_transfer_id IS NOT NULL AND movement_type = 'transfer_out';

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movements_transfer_in
    ON stock_movements (stock_transfer_id, warehouse_id, lot_id)
    WHERE stock_transfer_id IS NOT NULL AND movement_type = 'transfer_in';
