BEGIN;

ALTER TABLE products ADD COLUMN tax_rate NUMERIC(5, 2);
ALTER TABLE products ADD CONSTRAINT ck_products_tax_rate CHECK (tax_rate IS NULL OR (tax_rate >= 0 AND tax_rate <= 100));

ALTER TABLE sales_order_items ADD COLUMN tax_rate_snapshot NUMERIC(5, 2);
ALTER TABLE sales_order_items ADD COLUMN tax_amount NUMERIC(18, 2);
ALTER TABLE sales_order_items ADD CONSTRAINT ck_sales_order_items_tax_snapshot CHECK ((tax_rate_snapshot IS NULL AND tax_amount IS NULL) OR (tax_rate_snapshot >= 0 AND tax_rate_snapshot <= 100 AND tax_amount >= 0));

COMMIT;
