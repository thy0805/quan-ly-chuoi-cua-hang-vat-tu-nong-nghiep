<?php

namespace App\Support;

use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class PurchaseReceiptService
{
    public function saveDraft(array $data, int $creatorId, ?int $receiptId = null): int
    {
        try {
            return DB::transaction(function () use ($data, $creatorId, $receiptId): int {
                $receipt = null;
                if ($receiptId !== null) {
                    $receipt = DB::table('purchase_receipts')->where('id', $receiptId)->lockForUpdate()->first();
                    abort_if($receipt === null, 404);
                    abort_unless($receipt->status === 'draft' && (int) $receipt->created_by === $creatorId, 403);
                    abort_unless((int) $receipt->warehouse_id === (int) $data['warehouse_id'], 422);
                } else {
                    $receiptId = DB::table('purchase_receipts')->insertGetId([
                        'supplier_id' => $data['supplier_id'],
                        'warehouse_id' => $data['warehouse_id'],
                        'created_by' => $creatorId,
                        'receipt_no' => 'PN-'.Str::ulid(),
                        'status' => 'draft',
                        'total_amount' => 0,
                    ]);
                }

                $total = BigDecimal::zero();
                $lines = [];
                $seen = [];
                foreach ($data['items'] as $item) {
                    $lotId = $this->findOrCreateLot($item);
                    if (isset($seen[$lotId])) {
                        throw ValidationException::withMessages(['items' => 'Một lô chỉ xuất hiện một lần trong phiếu.']);
                    }
                    $seen[$lotId] = true;
                    $lineTotal = BigDecimal::of((string) $item['quantity'])
                        ->multipliedBy((string) $item['unit_cost'])
                        ->toScale(2, RoundingMode::HalfUp);
                    DecimalLimit::assertFits($lineTotal, 16, 2, 'items');
                    $total = $total->plus($lineTotal);
                    $lines[] = [
                        'receipt_id' => $receiptId,
                        'lot_id' => $lotId,
                        'quantity' => (string) BigDecimal::of((string) $item['quantity'])->toScale(3),
                        'unit_cost' => (string) BigDecimal::of((string) $item['unit_cost'])->toScale(2),
                        'line_total' => (string) $lineTotal,
                    ];
                }

                DecimalLimit::assertFits($total, 16, 2, 'items');
                $invoiceNo = isset($data['supplier_invoice_no']) ? trim($data['supplier_invoice_no']) : null;
                if ($invoiceNo === '') $invoiceNo = null;
                if ($invoiceNo !== null) {
                    $duplicate = DB::table('purchase_receipts')
                        ->where('supplier_id', $data['supplier_id'])
                        ->whereRaw('lower(trim(supplier_invoice_no)) = lower(?)', [$invoiceNo]);
                    if ($receiptId !== null) $duplicate->where('id', '<>', $receiptId);
                    if ($duplicate->exists()) {
                        throw ValidationException::withMessages(['supplier_invoice_no' => 'Số hóa đơn này đã được ghi nhận cho nhà cung cấp.']);
                    }
                }
                if ($receipt !== null) {
                    DB::table('purchase_receipt_items')->where('receipt_id', $receiptId)->delete();
                }
                DB::table('purchase_receipt_items')->insert($lines);
                DB::table('purchase_receipts')->where('id', $receiptId)->update([
                    'supplier_id' => $data['supplier_id'],
                    'total_amount' => (string) $total->toScale(2),
                    'supplier_invoice_no' => $invoiceNo,
                    'supplier_invoice_date' => $data['supplier_invoice_date'] ?? null,
                    'supplier_invoice_total' => $data['supplier_invoice_total'] ?? null,
                ]);

                return $receiptId;
            });
        } catch (QueryException $exception) {
            if (str_contains($exception->getMessage(), 'uq_purchase_receipts_supplier_invoice')) {
                throw ValidationException::withMessages(['supplier_invoice_no' => 'Số hóa đơn này đã được ghi nhận cho nhà cung cấp.']);
            }
            throw $exception;
        }
    }

    public function approve(int $receiptId, int $approverId): void
    {
        DB::transaction(function () use ($receiptId, $approverId): void {
            $receipt = DB::table('purchase_receipts')->where('id', $receiptId)->lockForUpdate()->first();
            abort_if($receipt === null, 404);
            abort_unless($receipt->status === 'submitted', 409);
            abort_if((int) $receipt->created_by === $approverId, 403);
            $this->assertInvoiceComplete($receipt);

            $scope = DB::table('warehouses as warehouse')
                ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
                ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
                ->where('warehouse.id', $receipt->warehouse_id)->lockForUpdate()
                ->first(['branch.is_active as branch_active', 'chain.is_active as chain_active']);
            if ($scope === null || ! $scope->branch_active || ! $scope->chain_active) {
                throw ValidationException::withMessages(['warehouse_id' => 'Chi nhánh hoặc chuỗi đã ngừng hoạt động.']);
            }
            DB::table('warehouses')->where('id', $receipt->warehouse_id)->lockForUpdate()->first();
            $items = DB::table('purchase_receipt_items')->where('receipt_id', $receiptId)->orderBy('lot_id')->get();
            abort_if($items->isEmpty(), 422);

            foreach ($items as $item) {
                $inventory = DB::table('inventories')
                    ->where('warehouse_id', $receipt->warehouse_id)
                    ->where('lot_id', $item->lot_id)
                    ->lockForUpdate()->first();
                $oldQuantity = BigDecimal::of((string) ($inventory?->quantity ?? '0'));
                if ($oldQuantity->isGreaterThan(0) && $inventory->average_unit_cost === null) {
                    throw ValidationException::withMessages(['items' => 'Tồn cũ của lô chưa có giá vốn gốc; cần xác minh trước khi nhập thêm.']);
                }
                $addedQuantity = BigDecimal::of((string) $item->quantity);
                $newQuantity = $oldQuantity->plus($addedQuantity);
                DecimalLimit::assertFits($newQuantity->toScale(3), 15, 3, 'items');
                $oldValue = $oldQuantity->isZero() ? BigDecimal::zero() : $oldQuantity->multipliedBy((string) $inventory->average_unit_cost);
                $addedValue = $addedQuantity->multipliedBy((string) $item->unit_cost);
                $averageCost = $oldValue->plus($addedValue)->dividedBy($newQuantity, 6, RoundingMode::HalfUp);
                DecimalLimit::assertFits($averageCost, 12, 6, 'items');
                $values = [
                    'quantity' => (string) $newQuantity->toScale(3),
                    'average_unit_cost' => (string) $averageCost,
                    'updated_at' => now(),
                ];
                if ($inventory) {
                    DB::table('inventories')->where('id', $inventory->id)->update($values);
                } else {
                    DB::table('inventories')->insert(['warehouse_id' => $receipt->warehouse_id, 'lot_id' => $item->lot_id] + $values);
                }
                DB::table('stock_movements')->insert([
                    'warehouse_id' => $receipt->warehouse_id,
                    'lot_id' => $item->lot_id,
                    'purchase_receipt_id' => $receiptId,
                    'movement_type' => 'purchase_in',
                    'quantity_delta' => (string) $addedQuantity->toScale(3),
                ]);
            }

            DB::table('purchase_receipts')->where('id', $receiptId)->update([
                'status' => 'approved',
                'approved_by' => $approverId,
                'approved_at' => now(),
            ]);
            app(DebtService::class)->recordPayable((string) $receiptId, $receipt, (string) $approverId);
            app(OutboxService::class)->record('purchase_receipt', (string) $receiptId, 'purchase.approved', [
                'actor_id' => (string) $approverId,
                'branch_id' => (string) DB::table('warehouses')->where('id', $receipt->warehouse_id)->value('branch_id'),
                'warehouse_id' => (string) $receipt->warehouse_id,
                'supplier_id' => (string) $receipt->supplier_id, 'total_amount' => (string) $receipt->total_amount,
                'supplier_invoice_no' => $receipt->supplier_invoice_no,
                'supplier_invoice_date' => $receipt->supplier_invoice_date,
                'supplier_invoice_total' => (string) $receipt->supplier_invoice_total,
            ]);
        });
    }

    public function assertInvoiceComplete(object $receipt): void
    {
        if ($receipt->supplier_invoice_no === null || trim($receipt->supplier_invoice_no) === '' || $receipt->supplier_invoice_date === null || $receipt->supplier_invoice_total === null) {
            throw ValidationException::withMessages(['supplier_invoice_no' => 'Cần đủ số, ngày và tổng hóa đơn nhà cung cấp trước khi gửi duyệt.']);
        }
        if (! BigDecimal::of((string) $receipt->supplier_invoice_total)->isEqualTo((string) $receipt->total_amount)) {
            throw ValidationException::withMessages(['supplier_invoice_total' => 'Tổng hóa đơn nhà cung cấp phải khớp tổng phiếu nhập trước khi gửi duyệt.']);
        }
    }

    private function findOrCreateLot(array $item): int
    {
        $lotNo = trim($item['lot_no']);
        $lot = DB::table('product_lots')->where('product_id', $item['product_id'])->where('lot_no', $lotNo)->first();
        if ($lot === null) {
            DB::table('product_lots')->insertOrIgnore([
                'product_id' => $item['product_id'],
                'lot_no' => $lotNo,
                'manufactured_on' => $item['manufactured_on'] ?? null,
                'expires_on' => $item['expires_on'] ?? null,
            ]);
            $lot = DB::table('product_lots')->where('product_id', $item['product_id'])->where('lot_no', $lotNo)->first();
        }
        if ($lot === null) {
            throw ValidationException::withMessages(['items' => 'Không tạo được lô vật tư hợp lệ.']);
        }
        foreach (['manufactured_on', 'expires_on'] as $field) {
            if (! empty($item[$field]) && $item[$field] !== $lot->$field) {
                throw ValidationException::withMessages(['items' => 'Ngày của lô đã tồn tại không khớp dữ liệu nhập.']);
            }
        }

        return (int) $lot->id;
    }
}
