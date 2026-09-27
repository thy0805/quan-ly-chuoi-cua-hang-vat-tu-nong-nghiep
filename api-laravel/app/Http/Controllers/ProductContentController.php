<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\CatalogPermission;
use App\Support\ProductContentStore;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class ProductContentController extends Controller
{
    public function show(Request $request, BranchAccess $access, ProductContentStore $store, string $id): JsonResponse
    {
        $this->authorizeProduct($request, $access, $id);

        return response()->json(['data' => $store->find($id)]);
    }

    public function update(Request $request, BranchAccess $access, CatalogPermission $permission, ProductContentStore $store, string $id): JsonResponse
    {
        $this->authorizeProduct($request, $access, $id);
        abort_unless($permission->canManage($request->user()), 403);
        $data = $request->validate([
            'usage_instructions' => ['nullable', 'string', 'max:10000'],
            'additional_info' => ['nullable', 'string', 'max:10000'],
            'images' => ['present', 'array', 'max:12'],
            'images.*' => ['required', 'url:http,https', 'max:2048', 'distinct'],
        ]);

        return response()->json(['data' => $store->save($id, [
            'usage_instructions' => $data['usage_instructions'] ?? null,
            'additional_info' => $data['additional_info'] ?? null,
            'images' => $data['images'],
        ])]);
    }

    private function authorizeProduct(Request $request, BranchAccess $access, string $id): void
    {
        abort_if($access->branchesFor($request->user())->isEmpty(), 403);
        if (! preg_match('/^[1-9][0-9]*$/D', $id) || strlen($id) > 19 || (strlen($id) === 19 && strcmp($id, '9223372036854775807') > 0)) {
            throw ValidationException::withMessages(['id' => 'Mã vật tư không hợp lệ.']);
        }
        abort_unless(DB::table('products')->where('id', $id)->exists(), 404);
    }
}
