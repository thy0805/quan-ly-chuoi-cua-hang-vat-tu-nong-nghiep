<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DecimalId;
use App\Support\DecimalLimit;
use App\Support\PurchaseReceiptService;
use App\Support\ReceiptAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PurchaseReceiptController extends Controller
{
    public function index(Request $request, BranchAccess $branches, ReceiptAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'branch_id' => ['bail', 'nullable', 'string', DecimalId::rule()],
            'status' => ['nullable', 'in:draft,submitted,approved,rejected'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);
        $allowedIds = $branches->branchesFor($request->user())->pluck('id')->all();
        abort_if($allowedIds === [], 403);
        if (isset($filters['branch_id'])) abort_unless(in_array($filters['branch_id'], array_map('strval', $allowedIds), true), 403);

        $query = DB::table('purchase_receipts as receipt')
            ->join('warehouses as warehouse', 'warehouse.id', '=', 'receipt.warehouse_id')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('suppliers as supplier', 'supplier.id', '=', 'receipt.supplier_id')
            ->join('users as creator', 'creator.id', '=', 'receipt.created_by')
            ->whereIn('branch.id', $allowedIds);
        if (isset($filters['branch_id'])) $query->where('branch.id', $filters['branch_id']);
        if (isset($filters['status'])) $query->where('receipt.status', $filters['status']);
        $page = $query->select([
            'receipt.id', 'receipt.receipt_no', 'receipt.status', 'receipt.total_amount',
            'receipt.received_at', 'receipt.created_by', 'receipt.approved_by', 'receipt.rejected_by',
            'branch.id as branch_id', 'branch.chain_id', 'branch.name as branch_name',
            'warehouse.id as warehouse_id', 'warehouse.name as warehouse_name',
            'supplier.id as supplier_id', 'supplier.name as supplier_name',
            'creator.username as creator_name',
        ])->orderByDesc('receipt.id')->paginate($filters['per_page'] ?? 20);
        $page->getCollection()->transform(function ($receipt) use ($request, $access) {
            return $this->withActions($receipt, $request, $access);
        });

        return response()->json([
            'data' => $page->items(),
            'branches' => $branches->branchesFor($request->user()),
            'pagination' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
        ]);
    }

    public function options(Request $request, BranchAccess $branches, ReceiptAccess $access): JsonResponse
    {
        $allowed = $branches->branchesFor($request->user());
        abort_if($allowed->isEmpty(), 403);
        $warehouses = DB::table('warehouses as warehouse')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
            ->whereIn('warehouse.branch_id', $allowed->pluck('id')->all())
            ->where('branch.is_active', true)
            ->where('chain.is_active', true)
            ->orderBy('branch.name')->orderBy('warehouse.name')
            ->get(['warehouse.id', 'warehouse.name', 'branch.id as branch_id', 'branch.name as branch_name', 'branch.chain_id'])
            ->filter(fn ($warehouse) => $access->canCreate($request->user(), (int) $warehouse->branch_id))
            ->values();
        $suppliers = DB::table('suppliers')
            ->whereIn('chain_id', $warehouses->pluck('chain_id')->unique()->all())
            ->orderBy('name')
            ->get(['id', 'chain_id', 'name']);

        return response()->json(['warehouses' => $warehouses, 'suppliers' => $suppliers]);
    }

    public function show(Request $request, BranchAccess $branches, ReceiptAccess $access, int $id): JsonResponse
    {
        $receipt = $this->scopedReceipt($request, $branches, $id);
        $items = DB::table('purchase_receipt_items as item')
            ->join('product_lots as lot', 'lot.id', '=', 'item.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->where('item.receipt_id', $id)
            ->orderBy('item.id')
            ->get(['item.id', 'item.lot_id', 'item.quantity', 'item.unit_cost', 'item.line_total', 'lot.lot_no', 'lot.manufactured_on', 'lot.expires_on', 'product.id as product_id', 'product.code as product_code', 'product.name as product_name', 'unit.name as unit_name']);

        return response()->json(['data' => $this->withActions($receipt, $request, $access), 'items' => $items]);
    }

    public function store(Request $request, PurchaseReceiptService $service, ReceiptAccess $access): JsonResponse
    {
        $data = $this->validateDraft($request);
        $this->validateScope($request, $access, $data);
        $id = $service->saveDraft($data, (int) $request->user()->id);

        return response()->json(['id' => $id], 201);
    }

    public function update(Request $request, PurchaseReceiptService $service, ReceiptAccess $access, int $id): JsonResponse
    {
        $data = $this->validateDraft($request);
        $this->validateScope($request, $access, $data);
        $service->saveDraft($data, (int) $request->user()->id, $id);

        return response()->json(['id' => $id]);
    }

    public function submit(Request $request, BranchAccess $branches, ReceiptAccess $access, int $id): JsonResponse
    {
        $this->scopedReceipt($request, $branches, $id);
        DB::transaction(function () use ($request, $access, $id): void {
            $receipt = DB::table('purchase_receipts')->where('id', $id)->lockForUpdate()->first();
            abort_unless($receipt->status === 'draft', 409);
            abort_unless((int) $receipt->created_by === (int) $request->user()->id, 403);
            $scope = DB::table('warehouses as warehouse')
                ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
                ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
                ->where('warehouse.id', $receipt->warehouse_id)->lockForUpdate()
                ->first(['branch.id as branch_id', 'branch.is_active as branch_active', 'chain.is_active as chain_active']);
            if ($scope === null || ! $scope->branch_active || ! $scope->chain_active) {
                throw ValidationException::withMessages(['warehouse_id' => 'Chi nhánh hoặc chuỗi đã ngừng hoạt động.']);
            }
            abort_unless($access->canCreate($request->user(), (int) $scope->branch_id), 403);
            abort_if(! DB::table('purchase_receipt_items')->where('receipt_id', $id)->exists(), 422);
            DB::table('purchase_receipts')->where('id', $id)->update(['status' => 'submitted', 'submitted_at' => now()]);
        });

        return response()->json(['status' => 'submitted']);
    }

    public function approve(Request $request, BranchAccess $branches, ReceiptAccess $access, PurchaseReceiptService $service, int $id): JsonResponse
    {
        $receipt = $this->scopedReceipt($request, $branches, $id);
        abort_if((int) $receipt->created_by === (int) $request->user()->id, 403);
        abort_unless($access->canApprove($request->user(), (int) $receipt->branch_id, (int) $receipt->chain_id), 403);
        $service->approve($id, (int) $request->user()->id);

        return response()->json(['status' => 'approved']);
    }

    public function reject(Request $request, BranchAccess $branches, ReceiptAccess $access, int $id): JsonResponse
    {
        $input = $request->validate(['reason' => ['nullable', 'string', 'max:1000']]);
        $receipt = $this->scopedReceipt($request, $branches, $id);
        abort_if((int) $receipt->created_by === (int) $request->user()->id, 403);
        DB::transaction(function () use ($request, $access, $receipt, $id, $input): void {
            $current = DB::table('purchase_receipts')->where('id', $id)->lockForUpdate()->first();
            abort_unless($current->status === 'submitted', 409);
            abort_unless($access->canApprove($request->user(), (int) $receipt->branch_id, (int) $receipt->chain_id), 403);
            DB::table('purchase_receipts')->where('id', $id)->update([
                'status' => 'rejected', 'rejected_by' => $request->user()->id,
                'rejected_at' => now(), 'rejection_reason' => $input['reason'] ?? null,
            ]);
        });

        return response()->json(['status' => 'rejected']);
    }

    private function validateDraft(Request $request): array
    {
        $data = $request->validate([
            'created_by' => ['prohibited'], 'approved_by' => ['prohibited'], 'receipt_no' => ['prohibited'], 'total_amount' => ['prohibited'],
            'supplier_id' => ['bail', 'required', 'string', DecimalId::rule(), 'exists:suppliers,id'],
            'warehouse_id' => ['bail', 'required', 'string', DecimalId::rule(), 'exists:warehouses,id'],
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.product_id' => ['bail', 'required', 'string', DecimalId::rule(), 'exists:products,id'],
            'items.*.lot_no' => ['required', 'string', 'max:80'],
            'items.*.manufactured_on' => ['nullable', 'date_format:Y-m-d'],
            'items.*.expires_on' => ['nullable', 'date_format:Y-m-d'],
            'items.*.quantity' => ['required', 'numeric', 'gt:0', 'decimal:0,3', DecimalLimit::rule(15, 3)],
            'items.*.unit_cost' => ['required', 'numeric', 'min:0', 'decimal:0,2', DecimalLimit::rule(16, 2)],
            'items.*.line_total' => ['prohibited'],
        ]);
        foreach ($data['items'] as $index => $item) {
            if (! empty($item['manufactured_on']) && ! empty($item['expires_on']) && $item['expires_on'] <= $item['manufactured_on']) {
                throw ValidationException::withMessages(["items.{$index}.expires_on" => 'Hạn dùng phải sau ngày sản xuất.']);
            }
            $active = DB::table('products as product')
                ->join('product_categories as category', 'category.id', '=', 'product.category_id')
                ->join('units as unit', 'unit.id', '=', 'product.unit_id')
                ->where('product.id', $item['product_id'])
                ->where('product.is_active', true)
                ->where('category.is_active', true)
                ->where('unit.is_active', true)
                ->exists();
            if (! $active) throw ValidationException::withMessages(["items.{$index}.product_id" => 'Vật tư không còn được sử dụng.']);
        }

        return $data;
    }

    private function validateScope(Request $request, ReceiptAccess $access, array $data): void
    {
        $warehouse = DB::table('warehouses as warehouse')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
            ->where('warehouse.id', $data['warehouse_id'])
            ->first(['branch.id as branch_id', 'branch.chain_id', 'branch.is_active as branch_active', 'chain.is_active as chain_active']);
        abort_if($warehouse === null, 422);
        abort_unless($access->canCreate($request->user(), (int) $warehouse->branch_id), 403);
        if (! $warehouse->branch_active || ! $warehouse->chain_active) {
            throw ValidationException::withMessages(['warehouse_id' => 'Chi nhánh hoặc chuỗi đã ngừng hoạt động.']);
        }
        $supplierChain = DB::table('suppliers')->where('id', $data['supplier_id'])->value('chain_id');
        if ((int) $supplierChain !== (int) $warehouse->chain_id) {
            throw ValidationException::withMessages(['supplier_id' => 'Nhà cung cấp phải thuộc cùng chuỗi với kho nhập.']);
        }
    }

    private function scopedReceipt(Request $request, BranchAccess $branches, int $id): object
    {
        $allowedIds = $branches->branchesFor($request->user())->pluck('id')->all();
        $receipt = DB::table('purchase_receipts as receipt')
            ->join('warehouses as warehouse', 'warehouse.id', '=', 'receipt.warehouse_id')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('suppliers as supplier', 'supplier.id', '=', 'receipt.supplier_id')
            ->where('receipt.id', $id)->whereIn('branch.id', $allowedIds)
            ->first(['receipt.*', 'branch.id as branch_id', 'branch.chain_id', 'branch.name as branch_name', 'warehouse.name as warehouse_name', 'supplier.name as supplier_name']);
        abort_if($receipt === null, 404);

        return $receipt;
    }

    private function withActions(object $receipt, Request $request, ReceiptAccess $access): object
    {
        $isCreator = (int) $receipt->created_by === (int) $request->user()->id;
        $canEdit = $receipt->status === 'draft' && $isCreator && $access->canCreate($request->user(), (int) $receipt->branch_id);
        $canApprove = $receipt->status === 'submitted' && ! $isCreator
            && $access->canApprove($request->user(), (int) $receipt->branch_id, (int) $receipt->chain_id);
        $receipt->can_edit = $canEdit;
        $receipt->can_submit = $canEdit;
        $receipt->can_approve = $canApprove;
        $receipt->can_reject = $canApprove;

        return $receipt;
    }
}
