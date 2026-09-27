ALTER TABLE stock_transfers
    ADD COLUMN IF NOT EXISTS reconciled_by BIGINT REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS reconciled_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reconciliation_reason TEXT;

ALTER TABLE stock_transfer_items
    ADD COLUMN IF NOT EXISTS supplemental_received_quantity NUMERIC(18, 3) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS returned_quantity NUMERIC(18, 3) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS lost_quantity NUMERIC(18, 3) NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_stock_transfer_items_reconciled_quantities') THEN
        ALTER TABLE stock_transfer_items ADD CONSTRAINT ck_stock_transfer_items_reconciled_quantities
            CHECK (supplemental_received_quantity >= 0 AND returned_quantity >= 0 AND lost_quantity >= 0
                AND supplemental_received_quantity + returned_quantity + lost_quantity <= dispatched_quantity - received_quantity);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_stock_transfers_reconciliation_metadata') THEN
        ALTER TABLE stock_transfers ADD CONSTRAINT ck_stock_transfers_reconciliation_metadata
            CHECK (status <> 'reconciled' OR (reconciled_by IS NOT NULL AND reconciled_at IS NOT NULL
                AND reconciliation_reason IS NOT NULL AND length(trim(reconciliation_reason)) > 0));
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movements_transfer_supplemental
    ON stock_movements (stock_transfer_id, warehouse_id, lot_id)
    WHERE stock_transfer_id IS NOT NULL AND movement_type = 'transfer_supplemental_in';

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movements_transfer_return
    ON stock_movements (stock_transfer_id, warehouse_id, lot_id)
    WHERE stock_transfer_id IS NOT NULL AND movement_type = 'transfer_return_in';
