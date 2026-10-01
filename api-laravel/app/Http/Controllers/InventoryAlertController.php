<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DecimalId;
use App\Support\DecimalLimit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class InventoryAlertController extends Controller
{
    public function index(Request $request, BranchAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'branch_id' => ['nullable', 'string'],
            'low_page' => ['nullable', 'integer', 'min:1'],
            'expiry_page' => ['nullable', 'integer', 'min:1'],
        ]);
        $allowedIds = $access->branchesFor($request->user())->pluck('id')->map(fn ($id) => (string) $id)->all();
        abort_if($allowedIds === [], 403);
        if (isset($filters['branch_id'])) {
            $branchId = DecimalId::parse($filters['branch_id'], 'branch_id');
            abort_unless(in_array($branchId, $allowedIds, true), 403);
            $allowedIds = [$branchId];
        }

        $lowQuery = DB::table('warehouse_product_settings as setting')
            ->join('warehouses as warehouse', 'warehouse.id', '=', 'setting.warehouse_id')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('products as product', 'product.id', '=', 'setting.product_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->leftJoin('product_lots as lot', 'lot.product_id', '=', 'product.id')
            ->leftJoin('inventories as inventory', function ($join): void {
                $join->on('inventory.lot_id', '=', 'lot.id')->on('inventory.warehouse_id', '=', 'warehouse.id');
            })
            ->whereIn('warehouse.branch_id', $allowedIds)
            ->groupBy('setting.id', 'setting.min_stock_quantity', 'warehouse.id', 'warehouse.name',
                'branch.id', 'branch.name', 'product.id', 'product.code', 'product.name', 'unit.name')
            ->havingRaw('COALESCE(SUM(inventory.quantity), 0) < setting.min_stock_quantity')
            ->select(['setting.id', 'setting.min_stock_quantity', 'warehouse.id as warehouse_id',
                'warehouse.name as warehouse_name', 'branch.id as branch_id', 'branch.name as branch_name',
                'product.id as product_id', 'product.code as product_code', 'product.name as product_name',
                'unit.name as unit_name'])
            ->selectRaw('COALESCE(SUM(inventory.quantity), 0) as quantity')
            ->orderBy('branch.name')->orderBy('warehouse.name')->orderBy('product.name');

        $today = now('Asia/Ho_Chi_Minh')->toDateString();
        $expiryQuery = DB::table('inventories as inventory')
            ->join('warehouses as warehouse', 'warehouse.id', '=', 'inventory.warehouse_id')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('product_lots as lot', 'lot.id', '=', 'inventory.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->whereIn('warehouse.branch_id', $allowedIds)
            ->where('inventory.quantity', '>', 0)->whereNotNull('lot.expires_on')
            ->whereRaw(DB::getDriverName() === 'pgsql'
                ? 'lot.expires_on <= (CAST(? AS DATE) + COALESCE(product.expiry_warning_days, 30))'
                : "date(lot.expires_on) <= date(?, '+' || COALESCE(product.expiry_warning_days, 30) || ' days')", [$today])
            ->select(['inventory.id', 'inventory.quantity', 'warehouse.id as warehouse_id',
                'warehouse.name as warehouse_name', 'branch.id as branch_id', 'branch.name as branch_name',
                'lot.id as lot_id', 'lot.lot_no', 'lot.expires_on', 'product.id as product_id',
                'product.code as product_code', 'product.name as product_name', 'unit.name as unit_name'])
            ->selectRaw('COALESCE(product.expiry_warning_days, 30) as warning_days')
            ->selectRaw("CASE WHEN lot.expires_on < ? THEN 'expired' ELSE 'expiring' END as status", [$today])
            ->orderBy('lot.expires_on')->orderBy('inventory.id');

        $low = $lowQuery->paginate(20, ['*'], 'low_page', $filters['low_page'] ?? 1);
        $expiry = $expiryQuery->paginate(20, ['*'], 'expiry_page', $filters['expiry_page'] ?? 1);

        return response()->json([
            'low_stock' => $low->items(), 'expiring_lots' => $expiry->items(),
            'low_pagination' => ['current_page' => $low->currentPage(), 'last_page' => $low->lastPage(), 'total' => $low->total()],
            'expiry_pagination' => ['current_page' => $expiry->currentPage(), 'last_page' => $expiry->lastPage(), 'total' => $expiry->total()],
            'branches' => $access->branchesFor($request->user()),
            'as_of_date' => $today,
        ]);
    }

    public function thresholds(Request $request, BranchAccess $access): JsonResponse
    {
        $branches = $access->branchesFor($request->user());
        abort_if($branches->isEmpty(), 403);
        $warehouses = DB::table('warehouses as warehouse')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
            ->whereIn('branch.id', $branches->pluck('id')->all())
            ->where('branch.is_active', true)->where('chain.is_active', true)
            ->orderBy('branch.name')->orderBy('warehouse.name')
            ->get(['warehouse.id', 'warehouse.name', 'branch.id as branch_id',
                'branch.name as branch_name', 'branch.chain_id']);
        $assignments = DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $request->user()->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now('Asia/Ho_Chi_Minh')->toDateString())
            ->whereIn('role.code', ['chain_owner', 'branch_manager'])
            ->get(['role.code', 'branch.id as branch_id', 'branch.chain_id']);
        $warehouses->transform(function ($warehouse) use ($assignments) {
            $warehouse->can_manage = $assignments->contains(fn ($assignment) =>
                ($assignment->code === 'branch_manager' && (string) $assignment->branch_id === (string) $warehouse->branch_id)
                || ($assignment->code === 'chain_owner' && (string) $assignment->chain_id === (string) $warehouse->chain_id));

            return $warehouse;
        });
        $settings = DB::table('warehouse_product_settings')
            ->whereIn('warehouse_id', $warehouses->pluck('id')->all())
            ->orderBy('warehouse_id')->orderBy('product_id')
            ->get(['id', 'warehouse_id', 'product_id', 'min_stock_quantity']);
        $products = DB::table('products as product')
            ->join('product_categories as category', 'category.id', '=', 'product.category_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->where('product.is_active', true)->where('category.is_active', true)->where('unit.is_active', true)
            ->orderBy('product.name')
            ->get(['product.id', 'product.code', 'product.name', 'unit.name as unit_name']);

        return response()->json(['warehouses' => $warehouses, 'settings' => $settings, 'products' => $products]);
    }

    public function setThreshold(Request $request, BranchAccess $access, string $warehouseId, string $productId): JsonResponse
    {
        $warehouseId = DecimalId::parse($warehouseId, 'warehouse_id');
        $productId = DecimalId::parse($productId, 'product_id');
        $data = $request->validate(['min_stock_quantity' => ['required', 'numeric', 'min:0', 'decimal:0,3', DecimalLimit::rule(15, 3)]]);
        $warehouse = DB::table('warehouses as warehouse')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
            ->where('warehouse.id', $warehouseId)
            ->first(['branch.id as branch_id', 'branch.chain_id', 'branch.is_active as branch_active', 'chain.is_active as chain_active']);
        abort_if($warehouse === null, 404);
        $allowed = $access->branchesFor($request->user())->pluck('id')->map(fn ($id) => (string) $id)->all();
        abort_unless(in_array((string) $warehouse->branch_id, $allowed, true), 403);
        $canManage = DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $request->user()->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now('Asia/Ho_Chi_Minh')->toDateString())
            ->where(function ($query) use ($warehouse): void {
                $query->where(function ($query) use ($warehouse): void {
                    $query->where('role.code', 'branch_manager')->where('assignment.branch_id', $warehouse->branch_id);
                })->orWhere(function ($query) use ($warehouse): void {
                    $query->where('role.code', 'chain_owner')->where('branch.chain_id', $warehouse->chain_id);
                });
            })->exists();
        abort_unless($canManage, 403);
        if (! $warehouse->branch_active || ! $warehouse->chain_active) {
            throw ValidationException::withMessages(['warehouse_id' => 'Kho thuộc chi nhánh hoặc chuỗi đã ngừng hoạt động.']);
        }
        $productActive = DB::table('products as product')
            ->join('product_categories as category', 'category.id', '=', 'product.category_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->where('product.id', $productId)
            ->where('product.is_active', true)->where('category.is_active', true)->where('unit.is_active', true)
            ->exists();
        if (! $productActive) throw ValidationException::withMessages(['product_id' => 'Vật tư không còn được sử dụng.']);
        DB::table('warehouse_product_settings')->upsert([[
            'warehouse_id' => $warehouseId, 'product_id' => $productId,
            'min_stock_quantity' => $data['min_stock_quantity'],
        ]], ['warehouse_id', 'product_id'], ['min_stock_quantity']);

        return response()->json(['warehouse_id' => $warehouseId, 'product_id' => $productId,
            'min_stock_quantity' => $data['min_stock_quantity']]);
    }
}
