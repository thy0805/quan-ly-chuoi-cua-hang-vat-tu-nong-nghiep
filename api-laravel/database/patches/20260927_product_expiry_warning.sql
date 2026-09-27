BEGIN;

ALTER TABLE products ADD COLUMN expiry_warning_days INTEGER;
ALTER TABLE products ADD CONSTRAINT ck_products_expiry_warning_days CHECK (expiry_warning_days IS NULL OR (expiry_warning_days >= 0 AND expiry_warning_days <= 3650));

COMMIT;
