<?php

namespace App\Http\Controllers;

use App\Support\PartnerAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SupplierController extends Controller
{
    public function index(Request $request, PartnerAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'chain_id' => ['nullable', 'integer', 'min:1'],
            'search' => ['nullable', 'string', 'max:120'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);
        $chainIds = $access->chainIds($request->user(), ['chain_owner', 'branch_manager'])->all();
        abort_if($chainIds === [], 403);
        if (isset($filters['chain_id'])) abort_unless(in_array((int) $filters['chain_id'], array_map('intval', $chainIds), true), 403);

        $query = DB::table('suppliers as supplier')
            ->join('chains as chain', 'chain.id', '=', 'supplier.chain_id')
            ->whereIn('supplier.chain_id', $chainIds);
        if (isset($filters['chain_id'])) $query->where('supplier.chain_id', $filters['chain_id']);
        if (! empty($filters['search'])) {
            $term = '%'.mb_strtolower(trim($filters['search'])).'%';
            $query->where(function ($query) use ($term): void {
                $query->whereRaw('LOWER(supplier.name) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(supplier.phone) LIKE ?', [$term]);
            });
        }
        $page = $query->select(['supplier.id', 'supplier.chain_id', 'chain.name as chain_name', 'supplier.name', 'supplier.phone', 'supplier.address'])
            ->orderBy('supplier.name')->orderBy('supplier.id')->paginate($filters['per_page'] ?? 20);

        return response()->json([
            'data' => $page->items(),
            'chains' => DB::table('chains')->whereIn('id', $chainIds)->orderBy('name')->get(['id', 'name']),
            'can_manage' => $access->chainIds($request->user(), ['chain_owner'])->isNotEmpty(),
            'pagination' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
        ]);
    }

    public function store(Request $request, PartnerAccess $access): JsonResponse
    {
        $data = $request->validate([
            'chain_id' => ['required', 'integer', 'exists:chains,id'],
            'name' => ['required', 'string', 'max:160'],
            'phone' => ['nullable', 'string', 'max:30'],
            'address' => ['nullable', 'string'],
        ]);
        $this->authorizeChain($request, $access, (int) $data['chain_id']);
        $id = DB::table('suppliers')->insertGetId($data);

        return response()->json(['data' => DB::table('suppliers')->find($id)], 201);
    }

    public function update(Request $request, PartnerAccess $access, int $id): JsonResponse
    {
        $supplier = DB::table('suppliers')->find($id);
        abort_if($supplier === null, 404);
        $this->authorizeChain($request, $access, (int) $supplier->chain_id);
        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:160'],
            'phone' => ['sometimes', 'nullable', 'string', 'max:30'],
            'address' => ['sometimes', 'nullable', 'string'],
        ]);
        if ($data !== []) DB::table('suppliers')->where('id', $id)->update($data);

        return response()->json(['data' => DB::table('suppliers')->find($id)]);
    }

    private function authorizeChain(Request $request, PartnerAccess $access, int $chainId): void
    {
        abort_unless($access->chainIds($request->user(), ['chain_owner'])->contains($chainId), 403);
    }
}
