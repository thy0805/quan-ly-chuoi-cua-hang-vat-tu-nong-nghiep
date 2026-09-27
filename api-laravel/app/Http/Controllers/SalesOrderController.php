<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DecimalId;
use App\Support\SaleService;
use App\Support\SalesAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class SalesOrderController extends Controller
{
    public function options(Request $request, BranchAccess $branches, SalesAccess $access): JsonResponse
    {
        $allowed = $branches->branchesFor($request->user());
        abort_if($allowed->isEmpty(), 403);
        $warehouses = DB::table('warehouses as warehouse')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
            ->whereIn('branch.id', $allowed->pluck('id')->all())
            ->where('branch.is_active', true)->where('chain.is_active', true)
            ->get(['warehouse.id', 'warehouse.name', 'branch.id as branch_id', 'branch.chain_id', 'branch.name as branch_name'])
            ->filter(fn ($row) => $access->canSell($request->user(), (string) $row->branch_id, (string) $row->chain_id))
            ->values();
        $chainIds = $warehouses->pluck('chain_id')->unique()->all();
        $customers = DB::table('customers')->whereIn('chain_id', $chainIds)->orderBy('name')
            ->get(['id', 'chain_id', 'name', 'customer_type']);
        $stock = DB::table('inventories as inventory')
            ->join('product_lots as lot', 'lot.id', '=', 'inventory.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->join('product_categories as category', 'category.id', '=', 'product.category_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id')
            ->whereIn('inventory.warehouse_id', $warehouses->pluck('id')->all())
            ->where('inventory.quantity', '>', 0)
            ->where('product.is_active', true)->where('category.is_active', true)->where('unit.is_active', true)
            ->where(function ($query): void {
                $query->whereNull('lot.expires_on')->orWhereDate('lot.expires_on', '>=', now('Asia/Ho_Chi_Minh')->toDateString());
            })->orderBy('product.name')->orderBy('lot.lot_no')
            ->get(['inventory.warehouse_id', 'inventory.lot_id', 'inventory.quantity',
                'product.id as product_id', 'product.code', 'product.name', 'product.sale_price', 'product.tax_rate',
                'lot.lot_no', 'lot.expires_on', 'unit.name as unit_name']);

        foreach ([$warehouses, $customers, $stock] as $rows) {
            foreach ($rows as $row) {
                foreach (['id', 'branch_id', 'chain_id', 'warehouse_id', 'lot_id', 'product_id'] as $field) {
                    if (isset($row->$field)) $row->$field = (string) $row->$field;
                }
            }
        }

        return response()->json(['warehouses' => $warehouses, 'customers' => $customers, 'stock' => $stock]);
    }

    public function index(Request $request, BranchAccess $branches): JsonResponse
    {
        $allowed = $branches->branchesFor($request->user())->pluck('id')->all();
        abort_if($allowed === [], 403);
        $orders = DB::table('sales_orders as sale')
            ->join('branches as branch', 'branch.id', '=', 'sale.branch_id')
            ->leftJoin('customers as customer', 'customer.id', '=', 'sale.customer_id')
            ->leftJoin('invoices as invoice', 'invoice.sales_order_id', '=', 'sale.id')
            ->whereIn('sale.branch_id', $allowed)
            ->orderByDesc('sale.id')->limit(50)
            ->get(['sale.id', 'sale.order_no', 'sale.status', 'sale.total_amount', 'sale.sold_at',
                'sale.branch_id', 'branch.name as branch_name', 'sale.customer_id', 'customer.name as customer_name',
                'invoice.id as invoice_id', 'invoice.invoice_no']);
        foreach ($orders as $order) $this->stringIds($order);

        return response()->json(['data' => $orders]);
    }

    public function show(Request $request, BranchAccess $branches, string $id): JsonResponse
    {
        $id = DecimalId::parse($id, 'id');
        $allowed = $branches->branchesFor($request->user())->pluck('id')->all();
        $order = DB::table('sales_orders as sale')
            ->join('branches as branch', 'branch.id', '=', 'sale.branch_id')
            ->leftJoin('customers as customer', 'customer.id', '=', 'sale.customer_id')
            ->leftJoin('invoices as invoice', 'invoice.sales_order_id', '=', 'sale.id')
            ->where('sale.id', $id)->whereIn('sale.branch_id', $allowed)
            ->first(['sale.*', 'branch.name as branch_name', 'branch.address as branch_address',
                'customer.name as customer_name', 'customer.phone as customer_phone', 'customer.address as customer_address',
                'invoice.id as invoice_id', 'invoice.invoice_no', 'invoice.issued_at',
                'invoice.subtotal', 'invoice.discount_amount as invoice_discount_amount', 'invoice.tax_amount as invoice_tax_amount']);
        abort_if($order === null, 404);
        $items = DB::table('sales_order_items as item')
            ->join('product_lots as lot', 'lot.id', '=', 'item.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->where('item.order_id', $id)->orderBy('item.id')
            ->get(['item.*', 'lot.lot_no', 'product.code as product_code', 'product.name as product_name']);
        $this->stringIds($order);
        foreach ($items as $item) $this->stringIds($item);

        return response()->json(['data' => $order, 'items' => $items]);
    }

    public function store(Request $request, SalesAccess $access, SaleService $service): JsonResponse
    {
        $data = $request->validate([
            'branch_id' => ['required', 'string'],
            'warehouse_id' => ['required', 'string'],
            'customer_id' => ['nullable', 'string'],
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.lot_id' => ['required', 'string'],
            'items.*.quantity' => ['required', 'numeric', 'gt:0', 'decimal:0,3'],
            'items.*.discount_amount' => ['nullable', 'numeric', 'min:0', 'decimal:0,2'],
            'created_by' => ['prohibited'], 'order_no' => ['prohibited'], 'total_amount' => ['prohibited'],
        ]);
        foreach (['branch_id', 'warehouse_id'] as $field) $data[$field] = DecimalId::parse($data[$field], $field);
        if (! empty($data['customer_id'])) $data['customer_id'] = DecimalId::parse($data['customer_id'], 'customer_id');
        foreach ($data['items'] as $index => &$item) $item['lot_id'] = DecimalId::parse($item['lot_id'], "items.{$index}.lot_id");
        unset($item);
        $branch = DB::table('branches as branch')->join('chains as chain', 'chain.id', '=', 'branch.chain_id')
            ->where('branch.id', $data['branch_id'])
            ->first(['branch.chain_id', 'branch.is_active as branch_active', 'chain.is_active as chain_active']);
        abort_if($branch === null, 422);
        abort_unless($access->canSell($request->user(), $data['branch_id'], (string) $branch->chain_id), 403);
        if (! $branch->branch_active || ! $branch->chain_active) {
            throw ValidationException::withMessages(['branch_id' => 'Chi nhánh hoặc chuỗi đã ngừng hoạt động.']);
        }
        if (! DB::table('warehouses')->where('id', $data['warehouse_id'])->where('branch_id', $data['branch_id'])->exists()) {
            throw ValidationException::withMessages(['warehouse_id' => 'Kho không thuộc chi nhánh bán.']);
        }
        if (isset($data['customer_id']) && ! DB::table('customers')->where('id', $data['customer_id'])->where('chain_id', $branch->chain_id)->exists()) {
            throw ValidationException::withMessages(['customer_id' => 'Khách không thuộc chuỗi bán.']);
        }
        foreach ($data['items'] as $index => $item) {
            if (array_diff(array_keys($item), ['lot_id', 'quantity', 'discount_amount']) !== []) {
                throw ValidationException::withMessages(["items.{$index}" => 'Giá, thuế và tổng do hệ thống tính.']);
            }
        }

        return response()->json(['id' => $service->createDraft($data, (string) $request->user()->id), 'status' => 'draft'], 201);
    }

    public function confirm(Request $request, BranchAccess $branches, SalesAccess $access, SaleService $service, string $id): JsonResponse
    {
        $id = DecimalId::parse($id, 'id');
        $order = DB::table('sales_orders as sale')->join('branches as branch', 'branch.id', '=', 'sale.branch_id')
            ->where('sale.id', $id)->first(['sale.branch_id', 'branch.chain_id', 'sale.created_by']);
        abort_if($order === null, 404);
        abort_unless($branches->branchesFor($request->user())->pluck('id')->contains($order->branch_id)
            && $access->canSell($request->user(), (string) $order->branch_id, (string) $order->chain_id), 403);
        abort_unless((string) $order->created_by === (string) $request->user()->id, 403);
        $service->confirm($id);

        return response()->json(['id' => $id, 'status' => 'confirmed']);
    }

    private function stringIds(object $row): void
    {
        foreach (get_object_vars($row) as $field => $value) {
            if ($value !== null && ($field === 'id' || str_ends_with($field, '_id'))) $row->$field = (string) $value;
        }
    }
}
