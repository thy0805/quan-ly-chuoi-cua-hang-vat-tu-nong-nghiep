BEGIN;

ALTER TABLE inventories ADD COLUMN IF NOT EXISTS average_unit_cost NUMERIC(18, 6);
ALTER TABLE inventories ADD CONSTRAINT ck_inventories_average_cost CHECK (average_unit_cost IS NULL OR average_unit_cost >= 0);

ALTER TABLE purchase_receipts ADD COLUMN IF NOT EXISTS created_by BIGINT;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM purchase_receipts WHERE created_by IS NULL) THEN
        RAISE EXCEPTION 'Existing purchase receipts require verified creator backfill before NOT NULL';
    END IF;
END
$$;
ALTER TABLE purchase_receipts ALTER COLUMN created_by SET NOT NULL;
ALTER TABLE purchase_receipts ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ;
ALTER TABLE purchase_receipts ADD COLUMN IF NOT EXISTS rejected_by BIGINT;
ALTER TABLE purchase_receipts ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;
ALTER TABLE purchase_receipts ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE purchase_receipts ADD CONSTRAINT fk_purchase_receipts_creator FOREIGN KEY (created_by) REFERENCES users(id);
ALTER TABLE purchase_receipts ADD CONSTRAINT fk_purchase_receipts_rejecter FOREIGN KEY (rejected_by) REFERENCES users(id);
ALTER TABLE purchase_receipts ADD CONSTRAINT ck_purchase_receipts_status CHECK (status IN ('draft', 'submitted', 'approved', 'rejected'));
ALTER TABLE purchase_receipts ADD CONSTRAINT ck_purchase_receipts_different_approver CHECK ((approved_by IS NULL OR approved_by <> created_by) AND (rejected_by IS NULL OR rejected_by <> created_by));

ALTER TABLE sales_order_items ADD COLUMN IF NOT EXISTS unit_cost_snapshot NUMERIC(18, 6);
ALTER TABLE sales_order_items ADD COLUMN IF NOT EXISTS cost_total NUMERIC(18, 2);
ALTER TABLE sales_order_items ADD CONSTRAINT ck_sales_order_items_cost_snapshot CHECK ((unit_cost_snapshot IS NULL AND cost_total IS NULL) OR (unit_cost_snapshot >= 0 AND cost_total >= 0));

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movements_purchase_lot ON stock_movements (purchase_receipt_id, warehouse_id, lot_id) WHERE purchase_receipt_id IS NOT NULL;

COMMIT;
