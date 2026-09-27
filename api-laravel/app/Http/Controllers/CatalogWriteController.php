<?php

namespace App\Http\Controllers;

use App\Support\CatalogPermission;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class CatalogWriteController extends Controller
{
    public function createCategory(Request $request, CatalogPermission $permission): JsonResponse
    {
        $this->authorizeManager($request, $permission);
        $data = $request->validate([
            'code' => ['required', 'string', 'max:40', Rule::unique('product_categories', 'code')],
            'name' => ['required', 'string', 'max:160'],
            'parent_id' => ['nullable', 'integer', Rule::exists('product_categories', 'id')],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $this->requireActive('product_categories', $data['parent_id'] ?? null, 'parent_id');
        $id = DB::table('product_categories')->insertGetId([
            'code' => trim($data['code']),
            'name' => trim($data['name']),
            'parent_id' => $data['parent_id'] ?? null,
            'is_active' => $data['is_active'] ?? true,
        ]);

        return response()->json(['data' => DB::table('product_categories')->find($id)], 201);
    }

    public function updateCategory(Request $request, CatalogPermission $permission, int $id): JsonResponse
    {
        $this->authorizeManager($request, $permission);
        $data = $request->validate([
            'code' => ['sometimes', 'required', 'string', 'max:40', Rule::unique('product_categories', 'code')->ignore($id)],
            'name' => ['sometimes', 'required', 'string', 'max:160'],
            'parent_id' => ['sometimes', 'nullable', 'integer', Rule::exists('product_categories', 'id')],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $category = DB::transaction(function () use ($id, $data) {
            $categories = DB::table('product_categories')->lockForUpdate()->get(['id', 'parent_id', 'is_active'])->keyBy('id');
            $current = $categories->get($id);
            abort_if($current === null, 404);
            $parentId = array_key_exists('parent_id', $data) ? $data['parent_id'] : $current->parent_id;
            $active = array_key_exists('is_active', $data) ? (bool) $data['is_active'] : (bool) $current->is_active;
            $parent = $parentId === null ? null : $categories->get($parentId);

            if ($parentId !== null && ($parent === null || ($active && ! $parent->is_active))) {
                throw ValidationException::withMessages(['parent_id' => 'Nhóm cha phải còn hoạt động.']);
            }

            $seen = [$id => true];
            while ($parentId !== null) {
                if (isset($seen[$parentId])) {
                    throw ValidationException::withMessages(['parent_id' => 'Nhóm cha tạo thành chu kỳ.']);
                }
                $seen[$parentId] = true;
                $parentId = $categories->get($parentId)?->parent_id;
            }

            $updates = array_intersect_key($data, array_flip(['code', 'name', 'parent_id', 'is_active']));
            if (isset($updates['code'])) $updates['code'] = trim($updates['code']);
            if (isset($updates['name'])) $updates['name'] = trim($updates['name']);
            if ($updates !== []) DB::table('product_categories')->where('id', $id)->update($updates);

            return DB::table('product_categories')->find($id);
        });

        return response()->json(['data' => $category]);
    }

    public function createUnit(Request $request, CatalogPermission $permission): JsonResponse
    {
        $this->authorizeManager($request, $permission);
        $data = $request->validate([
            'code' => ['required', 'string', 'max:40', Rule::unique('units', 'code')],
            'name' => ['required', 'string', 'max:100'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $id = DB::table('units')->insertGetId([
            'code' => trim($data['code']),
            'name' => trim($data['name']),
            'is_active' => $data['is_active'] ?? true,
        ]);

        return response()->json(['data' => DB::table('units')->find($id)], 201);
    }

    public function updateUnit(Request $request, CatalogPermission $permission, int $id): JsonResponse
    {
        $this->authorizeManager($request, $permission);
        $data = $request->validate([
            'code' => ['sometimes', 'required', 'string', 'max:40', Rule::unique('units', 'code')->ignore($id)],
            'name' => ['sometimes', 'required', 'string', 'max:100'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        abort_if(! DB::table('units')->where('id', $id)->exists(), 404);
        if (isset($data['code'])) $data['code'] = trim($data['code']);
        if (isset($data['name'])) $data['name'] = trim($data['name']);
        if ($data !== []) DB::table('units')->where('id', $id)->update($data);

        return response()->json(['data' => DB::table('units')->find($id)]);
    }

    public function createProduct(Request $request, CatalogPermission $permission): JsonResponse
    {
        $this->authorizeManager($request, $permission);
        $data = $request->validate([
            'code' => ['required', 'string', 'max:60', Rule::unique('products', 'code')],
            'name' => ['required', 'string', 'max:200'],
            'active_ingredient' => ['nullable', 'string', 'max:200'],
            'sale_price' => ['required', 'numeric', 'min:0', 'decimal:0,2'],
            'tax_rate' => ['nullable', 'numeric', 'min:0', 'max:100', 'decimal:0,2'],
            'expiry_warning_days' => ['nullable', 'integer', 'min:0', 'max:3650'],
            'category_id' => ['required', 'integer', Rule::exists('product_categories', 'id')],
            'unit_id' => ['required', 'integer', Rule::exists('units', 'id')],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $this->requireActive('product_categories', $data['category_id'], 'category_id');
        $this->requireActive('units', $data['unit_id'], 'unit_id');
        $id = DB::table('products')->insertGetId([
            'code' => trim($data['code']),
            'name' => trim($data['name']),
            'active_ingredient' => $data['active_ingredient'] ?? null,
            'sale_price' => $data['sale_price'],
            'tax_rate' => $data['tax_rate'] ?? null,
            'expiry_warning_days' => $data['expiry_warning_days'] ?? null,
            'category_id' => $data['category_id'],
            'unit_id' => $data['unit_id'],
            'is_active' => $data['is_active'] ?? true,
        ]);

        return response()->json(['data' => DB::table('products')->find($id)], 201);
    }

    public function updateProduct(Request $request, CatalogPermission $permission, int $id): JsonResponse
    {
        $this->authorizeManager($request, $permission);
        $data = $request->validate([
            'code' => ['sometimes', 'required', 'string', 'max:60', Rule::unique('products', 'code')->ignore($id)],
            'name' => ['sometimes', 'required', 'string', 'max:200'],
            'active_ingredient' => ['sometimes', 'nullable', 'string', 'max:200'],
            'sale_price' => ['sometimes', 'required', 'numeric', 'min:0', 'decimal:0,2'],
            'tax_rate' => ['sometimes', 'nullable', 'numeric', 'min:0', 'max:100', 'decimal:0,2'],
            'expiry_warning_days' => ['sometimes', 'nullable', 'integer', 'min:0', 'max:3650'],
            'category_id' => ['sometimes', 'required', 'integer', Rule::exists('product_categories', 'id')],
            'unit_id' => ['sometimes', 'required', 'integer', Rule::exists('units', 'id')],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $product = DB::table('products')->find($id);
        abort_if($product === null, 404);
        $active = array_key_exists('is_active', $data) ? (bool) $data['is_active'] : (bool) $product->is_active;
        if ($active || isset($data['category_id'])) {
            $this->requireActive('product_categories', $data['category_id'] ?? $product->category_id, 'category_id');
        }
        if ($active || isset($data['unit_id'])) {
            $this->requireActive('units', $data['unit_id'] ?? $product->unit_id, 'unit_id');
        }
        if (isset($data['code'])) $data['code'] = trim($data['code']);
        if (isset($data['name'])) $data['name'] = trim($data['name']);
        if ($data !== []) DB::table('products')->where('id', $id)->update($data);

        return response()->json(['data' => DB::table('products')->find($id)]);
    }

    private function authorizeManager(Request $request, CatalogPermission $permission): void
    {
        abort_unless($permission->canManage($request->user()), 403);
    }

    private function requireActive(string $table, ?int $id, string $field): void
    {
        if ($id !== null && ! DB::table($table)->where('id', $id)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages([$field => 'Chỉ được chọn dữ liệu còn hoạt động.']);
        }
    }
}
