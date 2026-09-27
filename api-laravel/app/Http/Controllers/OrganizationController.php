<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DecimalId;
use App\Support\PartnerAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class OrganizationController extends Controller
{
    public function index(Request $request, BranchAccess $access): JsonResponse
    {
        $allowed = $access->branchesFor($request->user());
        abort_if($allowed->isEmpty(), 403);

        $branchIds = $allowed->pluck('id')->all();
        $branches = DB::table('branches')
            ->whereIn('id', $branchIds)
            ->orderBy('name')
            ->get(['id', 'chain_id', 'code', 'name', 'address', 'default_sales_warehouse_id', 'is_active']);
        $chains = DB::table('chains')
            ->whereIn('id', $branches->pluck('chain_id')->unique()->all())
            ->orderBy('name')
            ->get(['id', 'name', 'is_active']);
        $warehouses = DB::table('warehouses')
            ->whereIn('branch_id', $branchIds)
            ->orderBy('name')
            ->get(['id', 'branch_id', 'code', 'name', 'warehouse_type']);

        return response()->json([
            'chains' => $chains,
            'branches' => $branches,
            'warehouses' => $warehouses,
            'manageable_chain_ids' => $this->ownerChains($request, app(PartnerAccess::class)),
        ]);
    }

    public function createChain(Request $request, PartnerAccess $access): JsonResponse
    {
        abort_if($this->ownerChains($request, $access) === [], 403);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:160'],
            'first_branch_code' => ['required', 'string', 'max:40'],
            'first_branch_name' => ['required', 'string', 'max:160'],
            'first_branch_address' => ['nullable', 'string'],
        ]);
        $created = DB::transaction(function () use ($request, $data): array {
            $chainId = DB::table('chains')->insertGetId(['name' => $data['name'], 'is_active' => true]);
            $branchId = DB::table('branches')->insertGetId([
                'chain_id' => $chainId,
                'code' => $data['first_branch_code'],
                'name' => $data['first_branch_name'],
                'address' => $data['first_branch_address'] ?? null,
                'is_active' => false,
            ]);
            $roleId = DB::table('roles')->where('code', 'chain_owner')->value('id');
            abort_if($roleId === null, 500);
            $assignment = ['user_id' => $request->user()->id, 'role_id' => $roleId, 'branch_id' => $branchId];
            if (! DB::table('user_role_assignments')->where($assignment)->where('status', 'active')->exists()) {
                DB::table('user_role_assignments')->insert($assignment + ['starts_on' => now()->toDateString(), 'status' => 'active']);
            }

            return ['chain_id' => $chainId, 'branch_id' => $branchId];
        });

        return response()->json($created, 201);
    }

    public function updateChain(Request $request, PartnerAccess $access, int $id): JsonResponse
    {
        $this->authorizeChain($request, $access, $id);
        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:160'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        if ($data !== []) DB::table('chains')->where('id', $id)->update($data);

        return response()->json(['data' => DB::table('chains')->find($id)]);
    }

    public function createBranch(Request $request, PartnerAccess $access): JsonResponse
    {
        $data = $request->validate([
            'chain_id' => ['bail', 'required', 'string', DecimalId::rule(), 'exists:chains,id'],
            'code' => ['required', 'string', 'max:40'],
            'name' => ['required', 'string', 'max:160'],
            'address' => ['nullable', 'string'],
        ]);
        $this->authorizeChain($request, $access, (int) $data['chain_id']);
        $this->requireActiveChain((int) $data['chain_id']);
        $id = DB::table('branches')->insertGetId($data + ['is_active' => false]);

        return response()->json(['data' => DB::table('branches')->find($id)], 201);
    }

    public function updateBranch(Request $request, PartnerAccess $access, int $id): JsonResponse
    {
        $branch = DB::table('branches')->find($id);
        abort_if($branch === null, 404);
        $this->authorizeChain($request, $access, (int) $branch->chain_id);
        $data = $request->validate([
            'code' => ['sometimes', 'required', 'string', 'max:40'],
            'name' => ['sometimes', 'required', 'string', 'max:160'],
            'address' => ['sometimes', 'nullable', 'string'],
            'default_sales_warehouse_id' => ['bail', 'sometimes', 'nullable', 'string', DecimalId::rule(), 'exists:warehouses,id'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        if (array_key_exists('default_sales_warehouse_id', $data) && $data['default_sales_warehouse_id'] !== null) {
            $warehouseBranch = DB::table('warehouses')->where('id', $data['default_sales_warehouse_id'])->value('branch_id');
            if ((int) $warehouseBranch !== $id) {
                throw ValidationException::withMessages(['default_sales_warehouse_id' => 'Kho mặc định phải thuộc chi nhánh này.']);
            }
        }
        $active = $data['is_active'] ?? $branch->is_active;
        $defaultWarehouse = array_key_exists('default_sales_warehouse_id', $data) ? $data['default_sales_warehouse_id'] : $branch->default_sales_warehouse_id;
        if ($active && $defaultWarehouse === null) {
            throw ValidationException::withMessages(['default_sales_warehouse_id' => 'Cần chọn kho bán mặc định trước khi kích hoạt chi nhánh.']);
        }
        if ($active) $this->requireActiveChain((int) $branch->chain_id);
        if ($data !== []) DB::table('branches')->where('id', $id)->update($data);

        return response()->json(['data' => DB::table('branches')->find($id)]);
    }

    public function createWarehouse(Request $request, PartnerAccess $access): JsonResponse
    {
        $data = $request->validate([
            'branch_id' => ['bail', 'required', 'string', DecimalId::rule(), 'exists:branches,id'],
            'code' => ['required', 'string', 'max:40'],
            'name' => ['required', 'string', 'max:160'],
            'warehouse_type' => ['required', 'string', 'max:40'],
        ]);
        $branch = DB::table('branches')->find($data['branch_id']);
        $this->authorizeChain($request, $access, (int) $branch->chain_id);
        $this->requireActiveChain((int) $branch->chain_id);
        $id = DB::table('warehouses')->insertGetId($data);

        return response()->json(['data' => DB::table('warehouses')->find($id)], 201);
    }

    public function updateWarehouse(Request $request, PartnerAccess $access, int $id): JsonResponse
    {
        $warehouse = DB::table('warehouses')->find($id);
        abort_if($warehouse === null, 404);
        $chainId = DB::table('branches')->where('id', $warehouse->branch_id)->value('chain_id');
        $this->authorizeChain($request, $access, (int) $chainId);
        $data = $request->validate([
            'code' => ['sometimes', 'required', 'string', 'max:40'],
            'name' => ['sometimes', 'required', 'string', 'max:160'],
            'warehouse_type' => ['sometimes', 'required', 'string', 'max:40'],
        ]);
        if ($data !== []) DB::table('warehouses')->where('id', $id)->update($data);

        return response()->json(['data' => DB::table('warehouses')->find($id)]);
    }

    private function ownerChains(Request $request, PartnerAccess $access): array
    {
        return $access->chainIds($request->user(), ['chain_owner'])->unique()->values()->all();
    }

    private function authorizeChain(Request $request, PartnerAccess $access, int $chainId): void
    {
        abort_unless(in_array($chainId, array_map('intval', $this->ownerChains($request, $access)), true), 403);
    }

    private function requireActiveChain(int $chainId): void
    {
        if (! DB::table('chains')->where('id', $chainId)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['chain_id' => 'Chuỗi đã ngừng hoạt động.']);
        }
    }
}
