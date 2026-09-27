<?php

namespace App\Support;

use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class SaleService
{
    public function createDraft(array $data, string $creatorId): string
    {
        return DB::transaction(function () use ($data, $creatorId): string {
            $orderId = DB::table('sales_orders')->insertGetId([
                'branch_id' => $data['branch_id'],
                'warehouse_id' => $data['warehouse_id'],
                'customer_id' => $data['customer_id'] ?? null,
                'created_by' => $creatorId,
                'order_no' => 'BH-'.Str::ulid(),
                'status' => 'draft',
                'total_amount' => '0.00',
            ]);

            $seen = [];
            foreach ($data['items'] as $index => $item) {
                $lotId = $item['lot_id'];
                if (isset($seen[$lotId])) {
                    throw ValidationException::withMessages(["items.{$index}.lot_id" => 'Mỗi lô chỉ được chọn một lần.']);
                }
                $seen[$lotId] = true;
                $product = DB::table('product_lots as lot')
                    ->join('products as product', 'product.id', '=', 'lot.product_id')
                    ->join('product_categories as category', 'category.id', '=', 'product.category_id')
                    ->join('units as unit', 'unit.id', '=', 'product.unit_id')
                    ->where('lot.id', $lotId)
                    ->where('product.is_active', true)
                    ->where('category.is_active', true)
                    ->where('unit.is_active', true)
                    ->first(['product.sale_price', 'product.tax_rate', 'lot.expires_on']);
                if ($product === null || ($product->expires_on !== null && $product->expires_on < now('Asia/Ho_Chi_Minh')->toDateString())) {
                    throw ValidationException::withMessages(["items.{$index}.lot_id" => 'Lô không còn hợp lệ để bán.']);
                }
                if ($product->tax_rate === null) {
                    throw ValidationException::withMessages(["items.{$index}.lot_id" => 'Vật tư chưa được cấu hình thuế suất.']);
                }
                $gross = BigDecimal::of((string) $product->sale_price)->multipliedBy((string) $item['quantity'])->toScale(2, RoundingMode::HalfUp);
                $discount = BigDecimal::of((string) ($item['discount_amount'] ?? '0'));
                if ($discount->isGreaterThan($gross)) {
                    throw ValidationException::withMessages(["items.{$index}.discount_amount" => 'Chiết khấu vượt tiền dòng.']);
                }
                DB::table('sales_order_items')->insert([
                    'order_id' => $orderId,
                    'lot_id' => $lotId,
                    'quantity' => (string) BigDecimal::of((string) $item['quantity'])->toScale(3),
                    'unit_price' => (string) $product->sale_price,
                    'discount_amount' => (string) $discount->toScale(2),
                    'line_total' => (string) $gross->minus($discount),
                    'tax_rate_snapshot' => (string) $product->tax_rate,
                    'tax_amount' => (string) $gross->minus($discount)->multipliedBy((string) $product->tax_rate)->dividedBy('100', 2, RoundingMode::HalfUp),
                ]);
            }

            return (string) $orderId;
        });
    }

    public function confirm(string $orderId): void
    {
        DB::transaction(function () use ($orderId): void {
            $order = DB::table('sales_orders')->where('id', $orderId)->lockForUpdate()->first();
            abort_if($order === null, 404);
            abort_unless($order->status === 'draft', 409);
            DB::table('warehouses')->where('id', $order->warehouse_id)->lockForUpdate()->first();
            $items = DB::table('sales_order_items')->where('order_id', $orderId)->orderBy('lot_id')->get();
            abort_if($items->isEmpty(), 422);
            $subtotal = BigDecimal::zero();
            $discountTotal = BigDecimal::zero();
            $taxTotal = BigDecimal::zero();
            foreach ($items as $item) {
                $inventory = DB::table('inventories')->where('warehouse_id', $order->warehouse_id)
                    ->where('lot_id', $item->lot_id)->lockForUpdate()->first();
                $lot = DB::table('product_lots as lot')
                    ->join('products as product', 'product.id', '=', 'lot.product_id')
                    ->join('product_categories as category', 'category.id', '=', 'product.category_id')
                    ->join('units as unit', 'unit.id', '=', 'product.unit_id')
                    ->where('lot.id', $item->lot_id)
                    ->lockForUpdate()
                    ->first(['lot.expires_on', 'product.sale_price', 'product.tax_rate', 'product.is_active as product_active', 'category.is_active as category_active', 'unit.is_active as unit_active']);
                if ($lot === null || ! $lot->product_active || ! $lot->category_active || ! $lot->unit_active
                    || ($lot->expires_on !== null && $lot->expires_on < now('Asia/Ho_Chi_Minh')->toDateString())) {
                    throw ValidationException::withMessages(['items' => 'Lô hoặc vật tư không còn hợp lệ.']);
                }
                if ($lot->tax_rate === null || BigDecimal::of((string) $lot->sale_price)->compareTo((string) $item->unit_price) !== 0
                    || BigDecimal::of((string) $lot->tax_rate)->compareTo((string) $item->tax_rate_snapshot) !== 0) {
                    throw ValidationException::withMessages(['items' => 'Giá hoặc thuế suất đã thay đổi; cần lập lại đơn trước khi xác nhận.']);
                }
                $quantity = BigDecimal::of((string) $item->quantity);
                if ($inventory === null || BigDecimal::of((string) $inventory->quantity)->isLessThan($quantity)) {
                    throw ValidationException::withMessages(['items' => 'Tồn kho không đủ cho lô đã chọn.']);
                }
                if ($inventory->average_unit_cost === null) {
                    throw ValidationException::withMessages(['items' => 'Lô chưa có giá vốn đã xác minh.']);
                }
                $costTotal = $quantity->multipliedBy((string) $inventory->average_unit_cost)->toScale(2, RoundingMode::HalfUp);
                DB::table('sales_order_items')->where('id', $item->id)->update([
                    'unit_cost_snapshot' => $inventory->average_unit_cost,
                    'cost_total' => (string) $costTotal,
                ]);
                DB::table('inventories')->where('id', $inventory->id)->update([
                    'quantity' => (string) BigDecimal::of((string) $inventory->quantity)->minus($quantity)->toScale(3),
                    'updated_at' => now(),
                ]);
                DB::table('stock_movements')->insert([
                    'warehouse_id' => $order->warehouse_id,
                    'lot_id' => $item->lot_id,
                    'sales_order_id' => $orderId,
                    'movement_type' => 'sale_out',
                    'quantity_delta' => (string) $quantity->negated()->toScale(3),
                ]);
                $subtotal = $subtotal->plus(BigDecimal::of((string) $item->unit_price)->multipliedBy((string) $item->quantity)->toScale(2, RoundingMode::HalfUp));
                $discountTotal = $discountTotal->plus((string) $item->discount_amount);
                $taxTotal = $taxTotal->plus((string) $item->tax_amount);
            }
            $total = $subtotal->minus($discountTotal)->plus($taxTotal)->toScale(2);
            DB::table('sales_orders')->where('id', $orderId)->update(['status' => 'confirmed', 'sold_at' => now(), 'total_amount' => (string) $total]);
            DB::table('invoices')->insert([
                'sales_order_id' => $orderId,
                'invoice_no' => 'HD-'.Str::ulid(),
                'subtotal' => (string) $subtotal->toScale(2),
                'discount_amount' => (string) $discountTotal->toScale(2),
                'tax_amount' => (string) $taxTotal->toScale(2),
                'total_amount' => (string) $total,
                'status' => 'issued',
            ]);
        });
    }
}
