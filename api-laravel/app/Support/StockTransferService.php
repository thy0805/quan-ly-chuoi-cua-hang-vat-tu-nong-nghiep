<?php

namespace App\Support;

use App\Models\User;
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class StockTransferService
{
    public function approve(string $id, User $user, TransferAccess $access): void
    {
        DB::transaction(function () use ($id, $user, $access): void {
            $transfer = $this->lockTransfer($id);
            abort_unless($transfer->status === 'requested', 409);
            $this->assertActiveBranches($transfer);
            abort_if((string) $transfer->requested_by === (string) $user->id, 403);
            abort_unless($access->canApprove($user, (string) $transfer->from_branch_id, (string) $transfer->chain_id), 403);
            DB::table('stock_transfers')->where('id', $id)->update([
                'status' => 'approved', 'approved_by' => $user->id, 'approved_at' => now(),
            ]);
            $this->recordEvent($id, 'transfer.approved', $user, $transfer);
        });
    }

    public function reject(string $id, User $user, TransferAccess $access, ?string $reason): void
    {
        DB::transaction(function () use ($id, $user, $access, $reason): void {
            $transfer = $this->lockTransfer($id);
            abort_unless($transfer->status === 'requested', 409);
            abort_if((string) $transfer->requested_by === (string) $user->id, 403);
            abort_unless($access->canApprove($user, (string) $transfer->from_branch_id, (string) $transfer->chain_id), 403);
            DB::table('stock_transfers')->where('id', $id)->update([
                'status' => 'rejected', 'rejected_by' => $user->id,
                'rejected_at' => now(), 'rejection_reason' => $reason,
            ]);
            $this->recordEvent($id, 'transfer.rejected', $user, $transfer, ['reason' => $reason]);
        });
    }

    public function dispatch(string $id, User $user, TransferAccess $access, array $quantities): void
    {
        DB::transaction(function () use ($id, $user, $access, $quantities): void {
            $transfer = $this->lockTransfer($id);
            abort_unless($transfer->status === 'approved', 409);
            abort_unless($access->canRequest($user, (string) $transfer->from_branch_id), 403);
            $this->assertActiveBranches($transfer);
            DB::table('warehouses')->where('id', $transfer->from_warehouse_id)->lockForUpdate()->first();
            $items = DB::table('stock_transfer_items')->where('transfer_id', $id)->orderBy('lot_id')->get();
            $this->assertMatchingItems($items, $quantities, 'dispatched_quantity');
            foreach ($items as $item) {
                $amount = BigDecimal::of((string) $quantities[(string) $item->lot_id]);
                if ($amount->isLessThanOrEqualTo(0) || $amount->isGreaterThan((string) $item->requested_quantity)) {
                    throw ValidationException::withMessages(['items' => 'Số xuất phải lớn hơn 0 và không vượt số lượng yêu cầu.']);
                }
                $inventory = DB::table('inventories')
                    ->where('warehouse_id', $transfer->from_warehouse_id)
                    ->where('lot_id', $item->lot_id)->lockForUpdate()->first();
                if (! $inventory || BigDecimal::of((string) $inventory->quantity)->isLessThan($amount)) {
                    throw ValidationException::withMessages(['items' => 'Kho nguồn không đủ tồn khi ghi xuất.']);
                }
                if ($inventory->average_unit_cost === null) {
                    throw ValidationException::withMessages(['items' => 'Lô tại kho nguồn chưa có giá vốn; cần xác minh trước khi xuất.']);
                }
                DB::table('inventories')->where('id', $inventory->id)->update([
                    'quantity' => (string) BigDecimal::of((string) $inventory->quantity)->minus($amount)->toScale(3),
                    'updated_at' => now(),
                ]);
                DB::table('stock_transfer_items')->where('id', $item->id)->update([
                    'dispatched_quantity' => (string) $amount->toScale(3),
                    'transfer_unit_cost' => $inventory->average_unit_cost,
                ]);
                DB::table('stock_movements')->insert([
                    'warehouse_id' => $transfer->from_warehouse_id, 'lot_id' => $item->lot_id,
                    'stock_transfer_id' => $id, 'movement_type' => 'transfer_out',
                    'quantity_delta' => (string) $amount->negated()->toScale(3),
                ]);
            }
            DB::table('stock_transfers')->where('id', $id)->update([
                'status' => 'dispatched', 'dispatched_by' => $user->id, 'dispatched_at' => now(),
            ]);
            $this->recordEvent($id, 'transfer.dispatched', $user, $transfer, ['quantities' => $quantities]);
        });
    }

    public function receive(string $id, User $user, TransferAccess $access, array $quantities): string
    {
        return DB::transaction(function () use ($id, $user, $access, $quantities): string {
            $transfer = $this->lockTransfer($id);
            abort_unless($transfer->status === 'dispatched', 409);
            abort_unless($access->canReceive($user, (string) $transfer->to_branch_id), 403);
            $this->assertActiveBranches($transfer);
            DB::table('warehouses')->where('id', $transfer->to_warehouse_id)->lockForUpdate()->first();
            $items = DB::table('stock_transfer_items')->where('transfer_id', $id)->orderBy('lot_id')->get();
            $this->assertMatchingItems($items, $quantities, 'received_quantity');
            $discrepancy = false;
            foreach ($items as $item) {
                $amount = BigDecimal::of((string) $quantities[(string) $item->lot_id]);
                $dispatched = BigDecimal::of((string) $item->dispatched_quantity);
                if ($amount->isLessThan(0) || $amount->isGreaterThan($dispatched)) {
                    throw ValidationException::withMessages(['items' => 'Số nhận phải từ 0 đến số đã xuất.']);
                }
                if ($amount->isLessThan($dispatched)) $discrepancy = true;
                if ($item->transfer_unit_cost === null) {
                    throw ValidationException::withMessages(['items' => 'Phiếu xuất chưa lưu giá vốn chuyển kho.']);
                }
                if ($amount->isGreaterThan(0)) {
                    $this->addToInventory((string) $transfer->to_warehouse_id, (string) $item->lot_id,
                        $amount, (string) $item->transfer_unit_cost, $id, 'transfer_in');
                }
                DB::table('stock_transfer_items')->where('id', $item->id)->update(['received_quantity' => (string) $amount->toScale(3)]);
            }
            $status = $discrepancy ? 'discrepancy' : 'received';
            DB::table('stock_transfers')->where('id', $id)->update([
                'status' => $status, 'received_by' => $user->id, 'received_at' => now(),
            ]);
            $this->recordEvent($id, 'transfer.received', $user, $transfer, ['quantities' => $quantities, 'status' => $status]);

            return $status;
        });
    }

    public function reconcile(string $id, User $user, TransferAccess $access, array $quantities, string $reason): void
    {
        DB::transaction(function () use ($id, $user, $access, $quantities, $reason): void {
            $transfer = $this->lockTransfer($id);
            abort_unless($transfer->status === 'discrepancy', 409);
            abort_unless($access->canReconcile($user, (string) $transfer->from_branch_id,
                (string) $transfer->to_branch_id, (string) $transfer->chain_id), 403);
            $warehouseIds = array_unique([(string) $transfer->from_warehouse_id, (string) $transfer->to_warehouse_id]);
            sort($warehouseIds, SORT_STRING);
            foreach ($warehouseIds as $warehouseId) {
                DB::table('warehouses')->where('id', $warehouseId)->lockForUpdate()->first();
            }
            $items = DB::table('stock_transfer_items')->where('transfer_id', $id)->orderBy('lot_id')->get();
            $this->assertMatchingItems($items, $quantities, 'reconciliation');
            foreach ($items as $item) {
                $line = $quantities[(string) $item->lot_id];
                $supplemental = BigDecimal::of($line['supplemental_received_quantity']);
                $returned = BigDecimal::of($line['returned_quantity']);
                $lost = BigDecimal::of($line['lost_quantity']);
                $shortage = BigDecimal::of((string) $item->dispatched_quantity)->minus((string) $item->received_quantity);
                if (! $supplemental->plus($returned)->plus($lost)->isEqualTo($shortage)) {
                    throw ValidationException::withMessages(['items' => 'Tổng nhận bổ sung, hoàn nguồn và hao hụt phải đúng bằng phần thiếu của từng lô.']);
                }
                if ($item->transfer_unit_cost === null) {
                    throw ValidationException::withMessages(['items' => 'Thiếu giá vốn đã chụp lúc xuất.']);
                }
                if ($supplemental->isGreaterThan(0)) {
                    $this->addToInventory((string) $transfer->to_warehouse_id, (string) $item->lot_id,
                        $supplemental, (string) $item->transfer_unit_cost, $id, 'transfer_supplemental_in');
                }
                if ($returned->isGreaterThan(0)) {
                    $this->addToInventory((string) $transfer->from_warehouse_id, (string) $item->lot_id,
                        $returned, (string) $item->transfer_unit_cost, $id, 'transfer_return_in');
                }
                DB::table('stock_transfer_items')->where('id', $item->id)->update([
                    'supplemental_received_quantity' => (string) $supplemental->toScale(3),
                    'returned_quantity' => (string) $returned->toScale(3),
                    'lost_quantity' => (string) $lost->toScale(3),
                ]);
            }
            DB::table('stock_transfers')->where('id', $id)->update([
                'status' => 'reconciled', 'reconciled_by' => $user->id,
                'reconciled_at' => now(), 'reconciliation_reason' => trim($reason),
            ]);
            $this->recordEvent($id, 'transfer.reconciled', $user, $transfer, ['quantities' => $quantities, 'reason' => trim($reason)]);
        });
    }

    private function recordEvent(string $id, string $event, User $user, object $transfer, array $details = []): void
    {
        app(OutboxService::class)->record('stock_transfer', $id, $event, [
            'actor_id' => (string) $user->id,
            'from_warehouse_id' => (string) $transfer->from_warehouse_id,
            'to_warehouse_id' => (string) $transfer->to_warehouse_id,
            'from_branch_id' => (string) $transfer->from_branch_id,
            'to_branch_id' => (string) $transfer->to_branch_id,
        ] + $details);
    }

    private function addToInventory(string $warehouseId, string $lotId, BigDecimal $amount,
        string $unitCost, string $transferId, string $movementType): void
    {
        $inventory = DB::table('inventories')
            ->where('warehouse_id', $warehouseId)->where('lot_id', $lotId)->lockForUpdate()->first();
        $oldQuantity = BigDecimal::of((string) ($inventory?->quantity ?? '0'));
        if ($oldQuantity->isGreaterThan(0) && $inventory->average_unit_cost === null) {
            throw ValidationException::withMessages(['items' => 'Tồn cũ của kho nhận chưa có giá vốn; cần xác minh trước khi cộng.']);
        }
        $newQuantity = $oldQuantity->plus($amount);
        $oldValue = $oldQuantity->isZero() ? BigDecimal::zero() : $oldQuantity->multipliedBy((string) $inventory->average_unit_cost);
        $incomingValue = $amount->multipliedBy($unitCost);
        $averageCost = $oldValue->plus($incomingValue)->dividedBy($newQuantity, 6, RoundingMode::HalfUp);
        $values = ['quantity' => (string) $newQuantity->toScale(3),
            'average_unit_cost' => (string) $averageCost, 'updated_at' => now()];
        if ($inventory) DB::table('inventories')->where('id', $inventory->id)->update($values);
        else DB::table('inventories')->insert(['warehouse_id' => $warehouseId, 'lot_id' => $lotId] + $values);
        DB::table('stock_movements')->insert([
            'warehouse_id' => $warehouseId, 'lot_id' => $lotId,
            'stock_transfer_id' => $transferId, 'movement_type' => $movementType,
            'quantity_delta' => (string) $amount->toScale(3),
        ]);
    }

    private function lockTransfer(string $id): object
    {
        $transfer = DB::table('stock_transfers')->where('id', $id)->lockForUpdate()->first();
        abort_if($transfer === null, 404);
        $scope = DB::table('warehouses as source')
            ->join('branches as source_branch', 'source_branch.id', '=', 'source.branch_id')
            ->join('chains as chain', 'chain.id', '=', 'source_branch.chain_id')
            ->crossJoin('warehouses as target')
            ->join('branches as target_branch', 'target_branch.id', '=', 'target.branch_id')
            ->where('source.id', $transfer->from_warehouse_id)
            ->where('target.id', $transfer->to_warehouse_id)
            ->whereColumn('source_branch.chain_id', 'target_branch.chain_id')
            ->first(['source.branch_id as from_branch_id', 'target.branch_id as to_branch_id',
                'source_branch.chain_id', 'source_branch.is_active as source_active',
                'target_branch.is_active as target_active', 'chain.is_active as chain_active']);
        abort_if($scope === null, 409);
        foreach ($scope as $field => $value) $transfer->$field = $value;

        return $transfer;
    }

    private function assertActiveBranches(object $transfer): void
    {
        if (! $transfer->source_active || ! $transfer->target_active || ! $transfer->chain_active) {
            throw ValidationException::withMessages(['status' => 'Chuỗi hoặc chi nhánh nguồn/đích đã ngừng hoạt động.']);
        }
    }

    private function assertMatchingItems($items, array $quantities, string $field): void
    {
        if ($items->isEmpty() || count($quantities) !== $items->count()) {
            throw ValidationException::withMessages(['items' => 'Phải khai đủ số lượng thực tế cho mọi lô.']);
        }
        foreach ($items as $item) {
            if (! array_key_exists((string) $item->lot_id, $quantities)) {
                throw ValidationException::withMessages(['items' => "Thiếu {$field} của một lô."]);
            }
        }
    }
}
