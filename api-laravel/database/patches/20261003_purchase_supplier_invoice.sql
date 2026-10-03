BEGIN;

ALTER TABLE purchase_receipts
    ADD COLUMN IF NOT EXISTS supplier_invoice_no VARCHAR(60),
    ADD COLUMN IF NOT EXISTS supplier_invoice_date DATE,
    ADD COLUMN IF NOT EXISTS supplier_invoice_total NUMERIC(18, 2);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_purchase_receipts_supplier_invoice_total') THEN
        ALTER TABLE purchase_receipts
            ADD CONSTRAINT ck_purchase_receipts_supplier_invoice_total
            CHECK (supplier_invoice_total IS NULL OR supplier_invoice_total >= 0);
    END IF;
END $$;

DROP INDEX IF EXISTS uq_purchase_receipts_supplier_invoice;

CREATE UNIQUE INDEX uq_purchase_receipts_supplier_invoice
    ON purchase_receipts (supplier_id, lower(trim(supplier_invoice_no)))
    WHERE supplier_invoice_no IS NOT NULL;

COMMIT;
