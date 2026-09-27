<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DecimalId;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CatalogController extends Controller
{
    public function index(Request $request, BranchAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'search' => ['nullable', 'string', 'max:120'],
            'category_id' => ['bail', 'nullable', 'string', DecimalId::rule()],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
            'active_only' => ['nullable', 'boolean'],
        ]);

        abort_if($access->branchesFor($request->user())->isEmpty(), 403);

        $categories = DB::table('product_categories')
            ->orderBy('name')
            ->get(['id', 'parent_id', 'code', 'name', 'is_active']);
        $units = DB::table('units')
            ->orderBy('name')
            ->get(['id', 'code', 'name', 'is_active']);

        $query = DB::table('products as product')
            ->join('product_categories as category', 'category.id', '=', 'product.category_id')
            ->join('units as unit', 'unit.id', '=', 'product.unit_id');

        if ($request->boolean('active_only')) {
            $query->where('product.is_active', true)
                ->where('category.is_active', true)
                ->where('unit.is_active', true);
        }

        if (isset($filters['category_id'])) {
            $query->where('product.category_id', $filters['category_id']);
        }

        if (! empty($filters['search'])) {
            $term = '%'.mb_strtolower(trim($filters['search'])).'%';
            $query->where(function ($query) use ($term): void {
                $query->whereRaw('LOWER(product.code) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(product.name) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(product.active_ingredient) LIKE ?', [$term]);
            });
        }

        $page = $query
            ->select([
                'product.id',
                'product.code',
                'product.name',
                'product.active_ingredient',
                'product.sale_price',
                'product.tax_rate',
                'product.expiry_warning_days',
                'product.is_active',
                'category.id as category_id',
                'category.name as category_name',
                'category.is_active as category_is_active',
                'unit.id as unit_id',
                'unit.code as unit_code',
                'unit.name as unit_name',
                'unit.is_active as unit_is_active',
            ])
            ->orderBy('product.name')
            ->orderBy('product.id')
            ->paginate($filters['per_page'] ?? 20);

        return response()->json([
            'data' => $page->items(),
            'categories' => $categories,
            'units' => $units,
            'pagination' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
            ],
        ]);
    }
}
