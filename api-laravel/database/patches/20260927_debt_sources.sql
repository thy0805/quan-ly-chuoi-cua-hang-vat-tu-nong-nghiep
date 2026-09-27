CREATE UNIQUE INDEX IF NOT EXISTS uq_debts_customer
    ON debts (customer_id) WHERE customer_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_debts_supplier
    ON debts (supplier_id) WHERE supplier_id IS NOT NULL;

ALTER TABLE debt_transactions
    ADD COLUMN IF NOT EXISTS invoice_id BIGINT REFERENCES invoices(id),
    ADD COLUMN IF NOT EXISTS purchase_receipt_id BIGINT REFERENCES purchase_receipts(id),
    ADD COLUMN IF NOT EXISTS branch_id BIGINT REFERENCES branches(id),
    ADD COLUMN IF NOT EXISTS warehouse_id BIGINT REFERENCES warehouses(id),
    ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS season_label VARCHAR(120);

ALTER TABLE payments
    ALTER COLUMN invoice_id DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS purchase_receipt_id BIGINT REFERENCES purchase_receipts(id),
    ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users(id),
    ADD COLUMN IF NOT EXISTS request_key VARCHAR(80),
    ADD COLUMN IF NOT EXISTS reference_note VARCHAR(200);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_debt_transactions_one_source') THEN
        ALTER TABLE debt_transactions ADD CONSTRAINT ck_debt_transactions_one_source
            CHECK (num_nonnulls(invoice_id, purchase_receipt_id) = 1);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_payments_one_source') THEN
        ALTER TABLE payments ADD CONSTRAINT ck_payments_one_source
            CHECK (num_nonnulls(invoice_id, purchase_receipt_id) = 1);
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_debt_transactions_sale_charge
    ON debt_transactions (invoice_id) WHERE transaction_type = 'sale_charge';

CREATE UNIQUE INDEX IF NOT EXISTS uq_debt_transactions_purchase_charge
    ON debt_transactions (purchase_receipt_id) WHERE transaction_type = 'purchase_charge';

CREATE UNIQUE INDEX IF NOT EXISTS uq_debt_transactions_payment
    ON debt_transactions (payment_id) WHERE payment_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_request_key
    ON payments (request_key) WHERE request_key IS NOT NULL;
