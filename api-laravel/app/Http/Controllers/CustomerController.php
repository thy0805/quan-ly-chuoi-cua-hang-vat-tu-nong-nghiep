<?php

namespace App\Http\Controllers;

use App\Support\PartnerAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CustomerController extends Controller
{
    public function index(Request $request, PartnerAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'chain_id' => ['nullable', 'integer', 'min:1'],
            'search' => ['nullable', 'string', 'max:120'],
            'customer_type' => ['nullable', 'in:farmer,small_dealer'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);
        $chainIds = $access->chainIds($request->user(), ['chain_owner', 'branch_manager', 'sales_staff'])->all();
        abort_if($chainIds === [], 403);
        if (isset($filters['chain_id'])) abort_unless(in_array((int) $filters['chain_id'], array_map('intval', $chainIds), true), 403);

        $query = DB::table('customers as customer')
            ->join('chains as chain', 'chain.id', '=', 'customer.chain_id')
            ->whereIn('customer.chain_id', $chainIds);
        if (isset($filters['chain_id'])) $query->where('customer.chain_id', $filters['chain_id']);
        if (isset($filters['customer_type'])) $query->where('customer.customer_type', $filters['customer_type']);
        if (! empty($filters['search'])) {
            $term = '%'.mb_strtolower(trim($filters['search'])).'%';
            $query->where(function ($query) use ($term): void {
                $query->whereRaw('LOWER(customer.name) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(customer.phone) LIKE ?', [$term]);
            });
        }
        $page = $query->select(['customer.id', 'customer.chain_id', 'chain.name as chain_name', 'customer.name', 'customer.customer_type', 'customer.phone', 'customer.address'])
            ->orderBy('customer.name')->orderBy('customer.id')->paginate($filters['per_page'] ?? 20);

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
            'customer_type' => ['required', 'in:farmer,small_dealer'],
            'phone' => ['nullable', 'string', 'max:30'],
            'address' => ['nullable', 'string'],
        ]);
        $this->authorizeChain($request, $access, (int) $data['chain_id']);
        $id = DB::table('customers')->insertGetId($data);

        return response()->json(['data' => DB::table('customers')->find($id)], 201);
    }

    public function update(Request $request, PartnerAccess $access, int $id): JsonResponse
    {
        $customer = DB::table('customers')->find($id);
        abort_if($customer === null, 404);
        $this->authorizeChain($request, $access, (int) $customer->chain_id);
        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:160'],
            'customer_type' => ['sometimes', 'required', 'in:farmer,small_dealer'],
            'phone' => ['sometimes', 'nullable', 'string', 'max:30'],
            'address' => ['sometimes', 'nullable', 'string'],
        ]);
        if ($data !== []) DB::table('customers')->where('id', $id)->update($data);

        return response()->json(['data' => DB::table('customers')->find($id)]);
    }

    private function authorizeChain(Request $request, PartnerAccess $access, int $chainId): void
    {
        abort_unless($access->chainIds($request->user(), ['chain_owner'])->contains($chainId), 403);
    }
}
