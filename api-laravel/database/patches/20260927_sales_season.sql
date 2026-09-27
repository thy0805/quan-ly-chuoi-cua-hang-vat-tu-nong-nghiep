ALTER TABLE sales_orders
    ADD COLUMN IF NOT EXISTS season_label VARCHAR(120);
