<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DecimalId;
use App\Support\DecimalLimit;
use App\Support\OutboxService;
use App\Support\StockTransferService;
use App\Support\TransferAccess;
use Brick\Math\BigDecimal;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class StockTransferController extends Controller
{
    public function index(Request $request, BranchAccess $branches): JsonResponse
    {
        $filters = $request->validate([
            'status' => ['nullable', 'in:requested,approved,rejected,dispatched,received,discrepancy,reconciled'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);
        $allowedIds = $branches->branchesFor($request->user())->pluck('id')->all();
        abort_if($allowedIds === [], 403);
        $query = $this->transferQuery()->where(function ($query) use ($allowedIds): void {
            $query->whereIn('source.branch_id', $allowedIds)->orWhereIn('target.branch_id', $allowedIds);
        });
        if (isset($filters['status'])) $query->where('transfer.status', $filters['status']);
        $page = $query->select([
            'transfer.id', 'transfer.transfer_no', 'transfer.status', 'transfer.requested_at',
            'transfer.requested_by', 'transfer.approved_by',
            'source.id as from_warehouse_id', 'source.name as from_warehouse_name',
            'source.branch_id as from_branch_id', 'source_branch.name as from_branch_name',
            'target.id as to_warehouse_id', 'target.name as to_warehouse_name',
            'target.branch_id as to_branch_id', 'target_branch.name as to_branch_name',
            'requester.username as requester_name',
        ])->orderByDesc('transfer.id')->paginate($filters['per_page'] ?? 20);

        return response()->json(['data' => $page->items(), 'pagination' => [
            'current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total(),
        ]]);
    }

    public function options(Request $request, BranchAccess $branches, TransferAccess $access): JsonResponse
    {
        $allowed = $branches->branchesFor($request->user());
        abort_if($allowed->isEmpty(), 403);
        $sources = DB::table('warehouses as warehouse')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
            ->whereIn('branch.id', $allowed->pluck('id')->all())
            ->where('branch.is_active', true)->where('chain.is_active', true)
            ->orderBy('branch.name')->orderBy('warehouse.name')
            ->get(['warehouse.id', 'warehouse.name', 'branch.id as branch_id', 'branch.name as branch_name', 'branch.chain_id'])
            ->filter(fn ($warehouse) => $access->canRequest($request->user(), (string) $warehouse->branch_id))->values();
        $destinations = DB::table('warehouses as warehouse')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
            ->whereIn('branch.chain_id', $sources->pluck('chain_id')->unique()->all())
            ->where('branch.is_active', true)->where('chain.is_active', true)
            ->orderBy('branch.name')->orderBy('warehouse.name')
            ->get(['warehouse.id', 'warehouse.name', 'branch.id as branch_id', 'branch.name as branch_name', 'branch.chain_id']);
        $lots = DB::table('inventories as inventory')
            ->join('product_lots as lot', 'lot.id', '=', 'inventory.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->join('product_categories as category', 'category.id', '=', 'product.category_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->whereIn('inventory.warehouse_id', $sources->pluck('id')->all())
            ->where('inventory.quantity', '>', 0)
            ->where('product.is_active', true)->where('category.is_active', true)->where('unit.is_active', true)
            ->orderBy('product.name')->orderBy('lot.lot_no')
            ->get(['inventory.warehouse_id', 'inventory.lot_id', 'inventory.quantity',
                'lot.lot_no', 'product.code as product_code', 'product.name as product_name', 'unit.name as unit_name']);

        return response()->json(['sources' => $sources, 'destinations' => $destinations, 'lots' => $lots]);
    }

    public function show(Request $request, BranchAccess $branches, TransferAccess $access, string $id): JsonResponse
    {
        $id = DecimalId::parse($id, 'id');
        $allowedIds = $branches->branchesFor($request->user())->pluck('id')->all();
        $transfer = $this->transferQuery()->where('transfer.id', $id)
            ->where(function ($query) use ($allowedIds): void {
                $query->whereIn('source.branch_id', $allowedIds)->orWhereIn('target.branch_id', $allowedIds);
            })->first(['transfer.*', 'source.name as from_warehouse_name', 'source.branch_id as from_branch_id',
                'source_branch.name as from_branch_name', 'source_branch.chain_id',
                'target.name as to_warehouse_name', 'target.branch_id as to_branch_id',
                'target_branch.name as to_branch_name', 'requester.username as requester_name']);
        abort_if($transfer === null, 404);
        $approver = $transfer->status === 'requested'
            && (string) $transfer->requested_by !== (string) $request->user()->id
            && $access->canApprove($request->user(), (string) $transfer->from_branch_id, (string) $transfer->chain_id);
        $transfer->can_approve = $approver;
        $transfer->can_reject = $approver;
        $transfer->can_dispatch = $transfer->status === 'approved'
            && $access->canRequest($request->user(), (string) $transfer->from_branch_id);
        $transfer->can_receive = $transfer->status === 'dispatched'
            && $access->canReceive($request->user(), (string) $transfer->to_branch_id);
        $transfer->can_reconcile = $transfer->status === 'discrepancy'
            && $access->canReconcile($request->user(), (string) $transfer->from_branch_id,
                (string) $transfer->to_branch_id, (string) $transfer->chain_id);
        $items = DB::table('stock_transfer_items as item')
            ->join('product_lots as lot', 'lot.id', '=', 'item.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->where('item.transfer_id', $id)->orderBy('item.id')
            ->get(['item.id', 'item.lot_id', 'item.requested_quantity', 'item.dispatched_quantity',
                'item.received_quantity', 'item.supplemental_received_quantity', 'item.returned_quantity',
                'item.lost_quantity', 'lot.lot_no', 'product.code as product_code',
                'product.name as product_name', 'unit.name as unit_name']);

        return response()->json(['data' => $transfer, 'items' => $items]);
    }

    public function store(Request $request, TransferAccess $access): JsonResponse
    {
        $data = $request->validate([
            'requested_by' => ['prohibited'], 'approved_by' => ['prohibited'],
            'transfer_no' => ['prohibited'], 'status' => ['prohibited'],
            'from_warehouse_id' => ['required', 'string'],
            'to_warehouse_id' => ['required', 'string'],
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.lot_id' => ['required', 'string'],
            'items.*.requested_quantity' => ['required', 'numeric', 'gt:0', 'decimal:0,3', DecimalLimit::rule(15, 3)],
            'items.*.dispatched_quantity' => ['prohibited'], 'items.*.received_quantity' => ['prohibited'],
        ]);
        $fromId = DecimalId::parse($data['from_warehouse_id'], 'from_warehouse_id');
        $toId = DecimalId::parse($data['to_warehouse_id'], 'to_warehouse_id');
        if ($fromId === $toId) throw ValidationException::withMessages(['to_warehouse_id' => 'Kho nguồn và kho đích phải khác nhau.']);
        foreach ($data['items'] as $index => $item) DecimalId::parse($item['lot_id'], "items.{$index}.lot_id");

        $id = DB::transaction(function () use ($request, $access, $data, $fromId, $toId): int {
            $warehouses = DB::table('warehouses as warehouse')
                ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
                ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
                ->whereIn('warehouse.id', [$fromId, $toId])->orderBy('warehouse.id')->lockForUpdate()
                ->get(['warehouse.id', 'branch.id as branch_id', 'branch.chain_id',
                    'branch.is_active as branch_active', 'chain.is_active as chain_active'])->keyBy('id');
            $source = $warehouses->get($fromId);
            $target = $warehouses->get($toId);
            if (! $source || ! $target) throw ValidationException::withMessages(['to_warehouse_id' => 'Kho nguồn hoặc kho đích không tồn tại.']);
            abort_unless($access->canRequest($request->user(), (string) $source->branch_id), 403);
            if ((string) $source->chain_id !== (string) $target->chain_id) {
                throw ValidationException::withMessages(['to_warehouse_id' => 'Chỉ điều chuyển giữa các kho cùng chuỗi.']);
            }
            if (! $source->branch_active || ! $target->branch_active || ! $source->chain_active || ! $target->chain_active) {
                throw ValidationException::withMessages(['to_warehouse_id' => 'Chi nhánh hoặc chuỗi đã ngừng hoạt động.']);
            }
            $seen = [];
            $lines = [];
            foreach ($data['items'] as $index => $item) {
                $lotId = $item['lot_id'];
                if (isset($seen[$lotId])) throw ValidationException::withMessages(['items' => 'Một lô chỉ được chọn một lần.']);
                $seen[$lotId] = true;
                $inventory = DB::table('inventories as inventory')
                    ->join('product_lots as lot', 'lot.id', '=', 'inventory.lot_id')
                    ->join('products as product', 'product.id', '=', 'lot.product_id')
                    ->join('product_categories as category', 'category.id', '=', 'product.category_id')
                    ->join('units as unit', 'unit.id', '=', 'product.unit_id')
                    ->where('inventory.warehouse_id', $fromId)->where('inventory.lot_id', $lotId)
                    ->where('product.is_active', true)->where('category.is_active', true)->where('unit.is_active', true)
                    ->first(['inventory.quantity']);
                if (! $inventory || BigDecimal::of((string) $inventory->quantity)->isLessThan((string) $item['requested_quantity'])) {
                    throw ValidationException::withMessages(["items.{$index}.requested_quantity" => 'Kho nguồn không đủ tồn hoạt động cho lô này.']);
                }
                $lines[] = ['lot_id' => $lotId, 'requested_quantity' => (string) BigDecimal::of((string) $item['requested_quantity'])->toScale(3)];
            }
            $transferId = DB::table('stock_transfers')->insertGetId([
                'from_warehouse_id' => $fromId, 'to_warehouse_id' => $toId,
                'requested_by' => $request->user()->id, 'transfer_no' => 'DC-'.Str::ulid(), 'status' => 'requested',
            ]);
            DB::table('stock_transfer_items')->insert(array_map(fn ($line) => ['transfer_id' => $transferId] + $line, $lines));
            app(OutboxService::class)->record('stock_transfer', (string) $transferId, 'transfer.requested', [
                'actor_id' => (string) $request->user()->id,
                'from_branch_id' => (string) $source->branch_id,
                'to_branch_id' => (string) $target->branch_id,
                'from_warehouse_id' => $fromId, 'to_warehouse_id' => $toId,
                'items' => $lines,
            ]);

            return $transferId;
        });

        return response()->json(['id' => $id], 201);
    }

    public function approve(Request $request, TransferAccess $access, StockTransferService $service, string $id): JsonResponse
    {
        $service->approve(DecimalId::parse($id, 'id'), $request->user(), $access);

        return response()->json(['status' => 'approved']);
    }

    public function reject(Request $request, TransferAccess $access, StockTransferService $service, string $id): JsonResponse
    {
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:1000']]);
        $service->reject(DecimalId::parse($id, 'id'), $request->user(), $access, $data['reason'] ?? null);

        return response()->json(['status' => 'rejected']);
    }

    public function dispatch(Request $request, TransferAccess $access, StockTransferService $service, string $id): JsonResponse
    {
        $service->dispatch(DecimalId::parse($id, 'id'), $request->user(), $access, $this->quantities($request, 'dispatched_quantity'));

        return response()->json(['status' => 'dispatched']);
    }

    public function receive(Request $request, TransferAccess $access, StockTransferService $service, string $id): JsonResponse
    {
        $status = $service->receive(DecimalId::parse($id, 'id'), $request->user(), $access, $this->quantities($request, 'received_quantity'));

        return response()->json(['status' => $status]);
    }

    public function reconcile(Request $request, TransferAccess $access, StockTransferService $service, string $id): JsonResponse
    {
        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:1000'],
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.lot_id' => ['required', 'string'],
            'items.*.supplemental_received_quantity' => ['required', 'numeric', 'min:0', 'decimal:0,3', DecimalLimit::rule(15, 3)],
            'items.*.returned_quantity' => ['required', 'numeric', 'min:0', 'decimal:0,3', DecimalLimit::rule(15, 3)],
            'items.*.lost_quantity' => ['required', 'numeric', 'min:0', 'decimal:0,3', DecimalLimit::rule(15, 3)],
        ]);
        if (mb_strlen(trim($data['reason'])) < 3) {
            throw ValidationException::withMessages(['reason' => 'Lý do đối soát cần ít nhất 3 ký tự.']);
        }
        $quantities = [];
        foreach ($data['items'] as $index => $item) {
            $lotId = DecimalId::parse($item['lot_id'], "items.{$index}.lot_id");
            if (array_key_exists($lotId, $quantities)) throw ValidationException::withMessages(['items' => 'Một lô chỉ được gửi một lần.']);
            $quantities[$lotId] = [
                'supplemental_received_quantity' => (string) $item['supplemental_received_quantity'],
                'returned_quantity' => (string) $item['returned_quantity'],
                'lost_quantity' => (string) $item['lost_quantity'],
            ];
        }
        $service->reconcile(DecimalId::parse($id, 'id'), $request->user(), $access, $quantities, trim($data['reason']));

        return response()->json(['status' => 'reconciled']);
    }

    private function quantities(Request $request, string $field): array
    {
        $data = $request->validate([
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.lot_id' => ['required', 'string'],
            "items.*.{$field}" => ['required', 'numeric', 'min:0', 'decimal:0,3', DecimalLimit::rule(15, 3)],
        ]);
        $quantities = [];
        foreach ($data['items'] as $index => $item) {
            $lotId = DecimalId::parse($item['lot_id'], "items.{$index}.lot_id");
            if (array_key_exists($lotId, $quantities)) {
                throw ValidationException::withMessages(['items' => 'Một lô chỉ được gửi một lần.']);
            }
            $quantities[$lotId] = (string) $item[$field];
        }

        return $quantities;
    }

    private function transferQuery()
    {
        return DB::table('stock_transfers as transfer')
            ->join('warehouses as source', 'source.id', '=', 'transfer.from_warehouse_id')
            ->join('branches as source_branch', 'source_branch.id', '=', 'source.branch_id')
            ->join('warehouses as target', 'target.id', '=', 'transfer.to_warehouse_id')
            ->join('branches as target_branch', 'target_branch.id', '=', 'target.branch_id')
            ->join('users as requester', 'requester.id', '=', 'transfer.requested_by');
    }
}
