<?php

namespace App\Support;

use App\Models\User;
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class DebtService
{
    public function recordReceivable(string $invoiceId, object $order, string $amount, string $actorId): ?string
    {
        if ($order->customer_id === null || BigDecimal::of($amount)->isZero()) return null;

        return $this->recordCharge('customer_id', (string) $order->customer_id, 'sale_charge',
            'invoice_id', $invoiceId, (string) $order->branch_id,
            (string) $order->warehouse_id, $amount, $actorId, $order->season_label);
    }

    public function recordPayable(string $receiptId, object $receipt, string $actorId): ?string
    {
        if (BigDecimal::of((string) $receipt->total_amount)->isZero()) return null;
        $branchId = DB::table('warehouses')->where('id', $receipt->warehouse_id)->value('branch_id');

        return $this->recordCharge('supplier_id', (string) $receipt->supplier_id, 'purchase_charge',
            'purchase_receipt_id', $receiptId, (string) $branchId,
            (string) $receipt->warehouse_id, (string) $receipt->total_amount, $actorId);
    }

    public function payCharge(string $chargeId, User $actor, array $data): array
    {
        return DB::transaction(function () use ($chargeId, $actor, $data): array {
            $charge = DB::table('debt_transactions')->where('id', $chargeId)
                ->whereIn('transaction_type', ['sale_charge', 'purchase_charge'])->first();
            abort_if($charge === null, 404);
            $debt = DB::table('debts')->where('id', $charge->debt_id)->lockForUpdate()->first();
            abort_if($debt === null, 404);
            $charge = DB::table('debt_transactions')->where('id', $chargeId)->first();
            $chainId = DB::table('branches')->where('id', $charge->branch_id)->value('chain_id');
            abort_unless(app(DebtAccess::class)->canPay($actor, $debt->debt_type, (string) $charge->branch_id, (string) $chainId), 403);
            $sourceField = $charge->invoice_id !== null ? 'invoice_id' : 'purchase_receipt_id';
            $existing = DB::table('payments')->where('request_key', $data['request_key'])->first();
            if ($existing !== null) {
                $same = (string) $existing->$sourceField === (string) $charge->$sourceField
                    && (string) $existing->created_by === (string) $actor->id
                    && $existing->method === $data['method']
                    && BigDecimal::of((string) $existing->amount)->isEqualTo($data['amount']);
                abort_unless($same, 409);

                return ['id' => (string) $existing->id, 'status' => 'completed', 'replayed' => true];
            }
            $paid = DB::table('debt_transactions')->where('debt_id', $debt->id)
                ->where($sourceField, $charge->$sourceField)->whereNotNull('payment_id')->sum('amount');
            $remaining = BigDecimal::of((string) $charge->amount)->minus((string) $paid)->toScale(2);
            $amount = BigDecimal::of($data['amount'])->toScale(2, RoundingMode::HalfUp);
            if ($amount->isGreaterThan($remaining)) {
                throw ValidationException::withMessages(['amount' => 'Số tiền vượt dư nợ còn lại của chứng từ.']);
            }
            $paymentId = DB::table('payments')->insertGetId([
                $sourceField => $charge->$sourceField,
                'method' => $data['method'],
                'amount' => (string) $amount,
                'status' => 'completed',
                'created_by' => $actor->id,
                'request_key' => $data['request_key'],
                'reference_note' => $data['reference_note'] ?? null,
            ]);
            DB::table('debt_transactions')->insert([
                'debt_id' => $debt->id,
                'payment_id' => $paymentId,
                $sourceField => $charge->$sourceField,
                'branch_id' => $charge->branch_id,
                'warehouse_id' => $charge->warehouse_id,
                'created_by' => $actor->id,
                'transaction_type' => $debt->debt_type === 'receivable' ? 'customer_payment' : 'supplier_payment',
                'amount' => (string) $amount,
            ]);
            if ($sourceField === 'invoice_id' && $amount->isEqualTo($remaining)) {
                DB::table('invoices')->where('id', $charge->invoice_id)->update(['status' => 'paid']);
            }
            $allCharges = DB::table('debt_transactions')->where('debt_id', $debt->id)
                ->whereIn('transaction_type', ['sale_charge', 'purchase_charge'])->sum('amount');
            $allPayments = DB::table('debt_transactions')->where('debt_id', $debt->id)
                ->whereNotNull('payment_id')->sum('amount');
            $balance = BigDecimal::of((string) $debt->opening_balance)->plus((string) $allCharges)->minus((string) $allPayments);
            DB::table('debts')->where('id', $debt->id)->update(['status' => $balance->isZero() ? 'closed' : 'open']);
            app(OutboxService::class)->record('payment', (string) $paymentId, 'debt.payment_recorded', [
                'actor_id' => (string) $actor->id, 'debt_id' => (string) $debt->id,
                'charge_id' => $chargeId, 'branch_id' => (string) $charge->branch_id,
                'source_type' => $sourceField === 'invoice_id' ? 'invoice' : 'purchase_receipt',
                'source_id' => (string) $charge->$sourceField,
                'method' => $data['method'], 'amount' => (string) $amount,
            ]);

            return ['id' => (string) $paymentId, 'status' => 'completed', 'remaining_amount' => (string) $remaining->minus($amount), 'replayed' => false];
        });
    }

    private function recordCharge(string $partnerField, string $partnerId, string $type,
        string $sourceField, string $sourceId, string $branchId, string $warehouseId,
        string $amount, string $actorId, ?string $seasonLabel = null): string
    {
        DB::table('debts')->insertOrIgnore([
            $partnerField => $partnerId,
            'debt_type' => $partnerField === 'customer_id' ? 'receivable' : 'payable',
            'opening_balance' => '0.00',
            'status' => 'open',
        ]);
        $debtId = DB::table('debts')->where($partnerField, $partnerId)->value('id');
        DB::table('debts')->where('id', $debtId)->lockForUpdate()->first();
        DB::table('debt_transactions')->insert([
            'debt_id' => $debtId, $sourceField => $sourceId,
            'branch_id' => $branchId, 'warehouse_id' => $warehouseId,
            'created_by' => $actorId, 'transaction_type' => $type,
            'amount' => $amount,
            'season_label' => $seasonLabel,
        ]);
        DB::table('debts')->where('id', $debtId)->update(['status' => 'open']);

        return (string) $debtId;
    }
}
