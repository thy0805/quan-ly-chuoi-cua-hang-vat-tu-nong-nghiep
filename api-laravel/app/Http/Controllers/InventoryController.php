<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DecimalId;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class InventoryController extends Controller
{
    public function movements(Request $request, BranchAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'branch_id' => ['nullable', 'string'],
            'search' => ['nullable', 'string', 'max:120'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);
        $branches = $access->branchesFor($request->user());
        abort_if($branches->isEmpty(), 403);
        $allowedIds = $branches->pluck('id')->map(fn ($id) => (string) $id)->all();
        if (isset($filters['branch_id'])) {
            $branchId = DecimalId::parse($filters['branch_id'], 'branch_id');
            abort_unless(in_array($branchId, $allowedIds, true), 403);
        }
        $query = DB::table('stock_movements as movement')
            ->join('warehouses as warehouse', 'warehouse.id', '=', 'movement.warehouse_id')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('product_lots as lot', 'lot.id', '=', 'movement.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->leftJoin('purchase_receipts as receipt', 'receipt.id', '=', 'movement.purchase_receipt_id')
            ->leftJoin('sales_orders as sale', 'sale.id', '=', 'movement.sales_order_id')
            ->leftJoin('stock_transfers as transfer', 'transfer.id', '=', 'movement.stock_transfer_id')
            ->whereIn('warehouse.branch_id', $allowedIds);
        if (isset($branchId)) $query->where('warehouse.branch_id', $branchId);
        if (! empty($filters['search'])) {
            $term = '%'.mb_strtolower(trim($filters['search'])).'%';
            $query->where(function ($query) use ($term): void {
                $query->whereRaw('LOWER(product.name) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(product.code) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(lot.lot_no) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(receipt.receipt_no) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(sale.order_no) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(transfer.transfer_no) LIKE ?', [$term]);
            });
        }
        $page = $query->select([
            'movement.id', 'movement.movement_type', 'movement.quantity_delta', 'movement.occurred_at',
            'movement.purchase_receipt_id', 'movement.sales_order_id', 'movement.stock_transfer_id',
            'warehouse.id as warehouse_id', 'warehouse.name as warehouse_name',
            'branch.id as branch_id', 'branch.name as branch_name',
            'lot.id as lot_id', 'lot.lot_no', 'product.code as product_code', 'product.name as product_name',
            'unit.name as unit_name', 'receipt.receipt_no', 'sale.order_no', 'transfer.transfer_no',
        ])->orderByDesc('movement.occurred_at')->orderByDesc('movement.id')
            ->paginate($filters['per_page'] ?? 20);

        return response()->json([
            'data' => $page->items(), 'branches' => $branches,
            'pagination' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
        ]);
    }

    public function index(Request $request, BranchAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'branch_id' => ['nullable', 'string'],
            'search' => ['nullable', 'string', 'max:120'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);

        $branches = $access->branchesFor($request->user());
        abort_if($branches->isEmpty(), 403);

        $allowedIds = $branches->pluck('id')->map(fn ($id) => (string) $id)->all();
        $branchId = isset($filters['branch_id']) ? DecimalId::parse($filters['branch_id'], 'branch_id') : null;
        abort_if($branchId !== null && ! in_array($branchId, $allowedIds, true), 403);

        $scope = DB::table('inventories as inventory')
            ->join('warehouses as warehouse', 'warehouse.id', '=', 'inventory.warehouse_id')
            ->whereIn('warehouse.branch_id', $allowedIds);

        if ($branchId !== null) {
            $scope->where('warehouse.branch_id', $branchId);
        }

        $today = now('Asia/Ho_Chi_Minh')->toDateString();
        $expiringLotIds = (clone $scope)
            ->join('product_lots as lot', 'lot.id', '=', 'inventory.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->where('inventory.quantity', '>', 0)
            ->whereNotNull('lot.expires_on')
            ->get(['lot.id', 'lot.expires_on', 'product.expiry_warning_days'])
            ->filter(function ($row) use ($today): bool {
                $warningDate = now('Asia/Ho_Chi_Minh')->startOfDay()->addDays($row->expiry_warning_days ?? 30)->toDateString();

                return $row->expires_on >= $today && $row->expires_on <= $warningDate;
            })->pluck('id')->unique();
        $summary = [
            'inventory_rows' => (clone $scope)->count(),
            'expiring_lots' => $expiringLotIds->count(),
            'branches_with_stock' => (clone $scope)
                ->where('inventory.quantity', '>', 0)
                ->distinct()
                ->count('warehouse.branch_id'),
        ];

        $query = (clone $scope)
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('product_lots as lot', 'lot.id', '=', 'inventory.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id');

        if (! empty($filters['search'])) {
            $term = '%'.mb_strtolower(trim($filters['search'])).'%';
            $query->where(function ($query) use ($term): void {
                $query->whereRaw('LOWER(product.code) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(product.name) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(lot.lot_no) LIKE ?', [$term]);
            });
        }

        $page = $query
            ->select([
                'inventory.id',
                'inventory.quantity',
                'product.code as product_code',
                'product.name as product_name',
                'branch.id as branch_id',
                'branch.name as branch_name',
                'warehouse.name as warehouse_name',
                'lot.lot_no',
                'lot.expires_on',
                'product.expiry_warning_days',
                'unit.name as unit_name',
            ])
            ->orderBy('product.name')
            ->orderBy('lot.lot_no')
            ->orderBy('inventory.id')
            ->paginate($filters['per_page'] ?? 20);

        $page->getCollection()->transform(function ($row) use ($today) {
            $warningDate = now('Asia/Ho_Chi_Minh')->startOfDay()->addDays($row->expiry_warning_days ?? 30)->toDateString();
            $row->status = match (true) {
                $row->expires_on === null => 'Không có hạn dùng',
                $row->expires_on < $today => 'Hết hạn',
                $row->expires_on <= $warningDate => 'Gần hết hạn',
                default => 'Bình thường',
            };

            return $row;
        });

        return response()->json([
            'data' => $page->items(),
            'summary' => $summary,
            'branches' => $branches,
            'pagination' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
            ],
        ]);
    }
}
