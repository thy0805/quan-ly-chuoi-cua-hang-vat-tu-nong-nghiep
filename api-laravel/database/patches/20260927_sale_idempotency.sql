CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_movements_sale_lot ON stock_movements (sales_order_id, warehouse_id, lot_id) WHERE sales_order_id IS NOT NULL;
