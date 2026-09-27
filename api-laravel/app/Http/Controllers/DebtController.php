<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DebtAccess;
use App\Support\DebtService;
use App\Support\DecimalId;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class DebtController extends Controller
{
    public function index(Request $request, BranchAccess $branches, DebtAccess $access): JsonResponse
    {
        $allowed = $branches->branchesFor($request->user());
        abort_if($allowed->isEmpty(), 403);
        $data = $request->validate([
            'type' => ['nullable', 'in:receivable,payable'],
            'branch_id' => ['nullable', 'string'],
            'status' => ['nullable', 'in:open,paid'],
            'page' => ['nullable', 'integer', 'min:1'],
        ]);
        $query = DB::table('debt_transactions as charge')
            ->join('debts as debt', 'debt.id', '=', 'charge.debt_id')
            ->join('branches as branch', 'branch.id', '=', 'charge.branch_id')
            ->leftJoin('customers as customer', 'customer.id', '=', 'debt.customer_id')
            ->leftJoin('suppliers as supplier', 'supplier.id', '=', 'debt.supplier_id')
            ->leftJoin('invoices as invoice', 'invoice.id', '=', 'charge.invoice_id')
            ->leftJoin('purchase_receipts as receipt', 'receipt.id', '=', 'charge.purchase_receipt_id')
            ->whereIn('charge.transaction_type', ['sale_charge', 'purchase_charge'])
            ->whereIn('charge.branch_id', $allowed->pluck('id')->all());
        if (isset($data['type'])) $query->where('debt.debt_type', $data['type']);
        if (isset($data['branch_id'])) {
            $branchId = DecimalId::parse($data['branch_id'], 'branch_id');
            abort_unless($allowed->pluck('id')->contains((int) $branchId), 403);
            $query->where('charge.branch_id', $branchId);
        }
        $rows = $query->orderByDesc('charge.id')->get([
            'charge.id', 'charge.debt_id', 'charge.invoice_id', 'charge.purchase_receipt_id',
            'charge.branch_id', 'charge.warehouse_id', 'charge.amount', 'charge.occurred_at', 'charge.season_label',
            'branch.chain_id', 'branch.name as branch_name', 'debt.debt_type',
            'customer.name as customer_name', 'supplier.name as supplier_name',
            'invoice.invoice_no', 'receipt.receipt_no',
        ])->filter(fn ($row) => $access->canView($request->user(), $row->debt_type, (string) $row->branch_id, (string) $row->chain_id))
            ->map(function ($row) use ($request, $access): object {
                $source = $row->invoice_id !== null ? 'invoice_id' : 'purchase_receipt_id';
                $paid = DB::table('debt_transactions')->where($source, $row->$source)
                    ->where('debt_id', $row->debt_id)->whereNotNull('payment_id')->sum('amount');
                $row->paid_amount = (string) $paid;
                $row->remaining_amount = (string) \Brick\Math\BigDecimal::of((string) $row->amount)->minus((string) $paid)->toScale(2);
                $row->can_pay = $access->canPay($request->user(), $row->debt_type, (string) $row->branch_id, (string) $row->chain_id)
                    && \Brick\Math\BigDecimal::of($row->remaining_amount)->isGreaterThan(0);
                foreach (['id', 'debt_id', 'invoice_id', 'purchase_receipt_id', 'branch_id', 'warehouse_id', 'chain_id'] as $field) {
                    if ($row->$field !== null) $row->$field = (string) $row->$field;
                }

                return $row;
            })->values();
        if (isset($data['status'])) {
            $rows = $rows->filter(fn ($row) => ($row->remaining_amount === '0.00' ? 'paid' : 'open') === $data['status'])->values();
        }
        $page = (int) ($data['page'] ?? 1);

        return response()->json(['data' => $rows->forPage($page, 20)->values(), 'total' => $rows->count(), 'page' => $page]);
    }

    public function pay(Request $request, DebtService $service, string $id): JsonResponse
    {
        $id = DecimalId::parse($id, 'id');
        $data = $request->validate([
            'amount' => ['required', 'regex:/^\d{1,16}(\.\d{1,2})?$/'],
            'method' => ['required', 'in:cash,bank_transfer'],
            'request_key' => ['required', 'string', 'min:8', 'max:80'],
            'reference_note' => ['nullable', 'string', 'max:200'],
        ]);
        if (array_diff(array_keys($request->all()), ['amount', 'method', 'request_key', 'reference_note']) !== []) {
            throw ValidationException::withMessages(['amount' => 'Chỉ nhận thông tin của lần thu hoặc chi này.']);
        }
        if (\Brick\Math\BigDecimal::of($data['amount'])->isLessThanOrEqualTo(0)) {
            throw ValidationException::withMessages(['amount' => 'Số tiền phải lớn hơn 0.']);
        }

        return response()->json($service->payCharge($id, $request->user(), $data));
    }
}
