<?php

namespace App\Http\Controllers;

use App\Support\PartnerAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class UserManagementController extends Controller
{
    public function index(Request $request, PartnerAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'search' => ['nullable', 'string', 'max:80'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);
        $chainIds = $this->ownerChains($request, $access);
        $query = DB::table('users as user')->whereExists(function ($query) use ($chainIds): void {
            $query->selectRaw('1')->from('user_role_assignments as assignment')
                ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
                ->whereColumn('assignment.user_id', 'user.id')->whereIn('branch.chain_id', $chainIds);
        });
        if (! empty($filters['search'])) $query->whereRaw('LOWER("user"."username") LIKE ?', ['%'.mb_strtolower(trim($filters['search'])).'%']);
        $page = $query->select(['user.id', 'user.username', 'user.is_active', 'user.is_catalog_admin'])
            ->orderBy('user.username')->paginate($filters['per_page'] ?? 20);
        $userIds = collect($page->items())->pluck('id')->all();
        $assignments = DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->whereIn('assignment.user_id', $userIds)->whereIn('branch.chain_id', $chainIds)
            ->orderBy('branch.name')->get([
                'assignment.id', 'assignment.user_id', 'assignment.branch_id', 'assignment.status', 'assignment.starts_on',
                'role.code as role_code', 'branch.name as branch_name', 'branch.chain_id',
            ])->groupBy('user_id');
        $outsideUsers = DB::table('user_role_assignments as assignment')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->whereIn('assignment.user_id', $userIds)->where('assignment.status', 'active')
            ->whereNotIn('branch.chain_id', $chainIds)->pluck('assignment.user_id')->unique()->all();
        $page->getCollection()->transform(function ($user) use ($assignments, $outsideUsers) {
            $user->assignments = $assignments->get($user->id, collect())->values();
            $outside = in_array($user->id, $outsideUsers);
            $lastOwner = false;
            foreach ($user->assignments as $assignment) {
                $assignment->can_revoke = $assignment->status === 'active';
                if ($assignment->status !== 'active' || $assignment->role_code !== 'chain_owner' || ! $user->is_active) continue;
                if (! $this->hasOtherOwner((int) $assignment->chain_id, null, (int) $assignment->id)) {
                    $assignment->can_revoke = false;
                }
                if (! $this->hasOtherOwner((int) $assignment->chain_id, (int) $user->id)) $lastOwner = true;
            }
            $user->can_toggle_active = ! $outside && (! $user->is_active || ! $lastOwner);
            $user->lock_reason = $outside ? 'Tài khoản còn quyền ở chuỗi khác.' : ($lastOwner && $user->is_active ? 'Đây là Chủ chuỗi hoạt động cuối cùng.' : null);

            return $user;
        });

        return response()->json([
            'data' => $page->items(),
            'branches' => DB::table('branches')->whereIn('chain_id', $chainIds)->orderBy('name')->get(['id', 'chain_id', 'name', 'code']),
            'chains' => DB::table('chains')->whereIn('id', $chainIds)->orderBy('name')->get(['id', 'name']),
            'roles' => DB::table('roles')->whereIn('code', ['chain_owner', 'branch_manager', 'sales_staff'])->orderBy('id')->get(['code', 'name']),
            'pagination' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
        ]);
    }

    public function store(Request $request, PartnerAccess $access): JsonResponse
    {
        $data = $request->validate([
            'username' => ['required', 'string', 'alpha_dash', 'min:3', 'max:80', 'unique:users,username'],
            'password' => ['required', 'string', 'min:10', 'max:255'],
            'branch_id' => ['required', 'integer', 'exists:branches,id'],
            'role_code' => ['required', 'in:chain_owner,branch_manager,sales_staff'],
            'is_catalog_admin' => ['prohibited'],
        ]);
        $chainIds = $this->ownerChains($request, $access);
        $branch = DB::table('branches')->where('id', $data['branch_id'])->first();
        abort_unless(in_array((int) $branch->chain_id, $chainIds, true), 403);
        $id = DB::transaction(function () use ($data, $branch): int {
            DB::table('branches')->where('id', $branch->id)->lockForUpdate()->first();
            $roleId = DB::table('roles')->where('code', $data['role_code'])->value('id');
            abort_if($roleId === null, 500);
            $id = DB::table('users')->insertGetId([
                'username' => $data['username'], 'password_hash' => Hash::make($data['password']),
                'is_active' => true, 'is_catalog_admin' => false,
            ]);
            DB::table('user_role_assignments')->insert([
                'user_id' => $id, 'role_id' => $roleId, 'branch_id' => $branch->id,
                'starts_on' => now()->toDateString(), 'status' => 'active',
            ]);

            return $id;
        });

        return response()->json(['id' => $id], 201);
    }

    public function setActive(Request $request, PartnerAccess $access, int $id): JsonResponse
    {
        $data = $request->validate(['is_active' => ['required', 'boolean']]);
        $chainIds = $this->ownerChains($request, $access);
        DB::transaction(function () use ($id, $data, $chainIds): void {
            $user = DB::table('users')->where('id', $id)->lockForUpdate()->first();
            abort_if($user === null, 404);
            $userChains = $this->activeUserChains($id);
            abort_unless($userChains !== [] && array_diff($userChains, $chainIds) === [], 403);
            if (! $data['is_active'] && $user->is_active) {
                foreach ($userChains as $chainId) DB::table('chains')->where('id', $chainId)->lockForUpdate()->first();
                $this->guardLastOwner($id, $userChains);
            }
            DB::table('users')->where('id', $id)->update(['is_active' => $data['is_active']]);
        });

        return response()->json(['id' => $id, 'is_active' => (bool) $data['is_active']]);
    }

    public function grant(Request $request, PartnerAccess $access, int $id): JsonResponse
    {
        $data = $request->validate([
            'branch_id' => ['required', 'integer', 'exists:branches,id'],
            'role_code' => ['required', 'in:chain_owner,branch_manager,sales_staff'],
        ]);
        $chainIds = $this->ownerChains($request, $access);
        $branch = DB::table('branches')->where('id', $data['branch_id'])->first();
        abort_unless(in_array((int) $branch->chain_id, $chainIds, true), 403);
        abort_unless($this->visibleUser($id, $chainIds), 404);
        $assignmentId = DB::transaction(function () use ($id, $data, $branch): int {
            DB::table('branches')->where('id', $branch->id)->lockForUpdate()->first();
            $roleId = DB::table('roles')->where('code', $data['role_code'])->value('id');
            abort_if($roleId === null, 500);
            $existing = DB::table('user_role_assignments')
                ->where('user_id', $id)->where('role_id', $roleId)->where('branch_id', $branch->id)
                ->where('status', 'active')->first();
            if ($existing) return (int) $existing->id;

            return DB::table('user_role_assignments')->insertGetId([
                'user_id' => $id, 'role_id' => $roleId, 'branch_id' => $branch->id,
                'starts_on' => now()->toDateString(), 'status' => 'active',
            ]);
        });

        return response()->json(['id' => $assignmentId]);
    }

    public function revoke(Request $request, PartnerAccess $access, int $assignmentId): JsonResponse
    {
        $chainIds = $this->ownerChains($request, $access);
        $assignment = DB::table('user_role_assignments as assignment')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->where('assignment.id', $assignmentId)
            ->first(['assignment.user_id', 'assignment.branch_id', 'assignment.status', 'branch.chain_id', 'role.code as role_code']);
        abort_if($assignment === null, 404);
        abort_unless(in_array((int) $assignment->chain_id, $chainIds, true), 403);
        DB::transaction(function () use ($assignment, $assignmentId): void {
            DB::table('chains')->where('id', $assignment->chain_id)->lockForUpdate()->first();
            $current = DB::table('user_role_assignments')->where('id', $assignmentId)->lockForUpdate()->first();
            abort_unless($current->status === 'active', 409);
            if ($assignment->role_code === 'chain_owner') $this->guardLastOwner((int) $assignment->user_id, [(int) $assignment->chain_id], $assignmentId);
            DB::table('user_role_assignments')->where('id', $assignmentId)->update(['status' => 'revoked']);
        });

        return response()->json(['status' => 'revoked']);
    }

    private function ownerChains(Request $request, PartnerAccess $access): array
    {
        $ids = $access->chainIds($request->user(), ['chain_owner'])->map(fn ($id) => (int) $id)->unique()->values()->all();
        abort_if($ids === [], 403);

        return $ids;
    }

    private function visibleUser(int $userId, array $chainIds): bool
    {
        return DB::table('user_role_assignments as assignment')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $userId)->whereIn('branch.chain_id', $chainIds)->exists();
    }

    private function activeUserChains(int $userId): array
    {
        return DB::table('user_role_assignments as assignment')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $userId)->where('assignment.status', 'active')
            ->distinct()->pluck('branch.chain_id')->map(fn ($id) => (int) $id)->sort()->values()->all();
    }

    private function guardLastOwner(int $userId, array $chainIds, ?int $revokeAssignmentId = null): void
    {
        foreach ($chainIds as $chainId) {
            $hasOwnerRole = DB::table('user_role_assignments as assignment')
                ->join('roles as role', 'role.id', '=', 'assignment.role_id')
                ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
                ->where('assignment.user_id', $userId)->where('assignment.status', 'active')
                ->where('role.code', 'chain_owner')->where('branch.chain_id', $chainId);
            if ($revokeAssignmentId !== null) $hasOwnerRole->where('assignment.id', $revokeAssignmentId);
            if (! $hasOwnerRole->exists()) continue;
            if (! $this->hasOtherOwner((int) $chainId, $revokeAssignmentId === null ? $userId : null, $revokeAssignmentId)) {
                throw ValidationException::withMessages(['role_code' => 'Chuỗi phải còn ít nhất một Chủ chuỗi đang hoạt động.']);
            }
        }
    }

    private function hasOtherOwner(int $chainId, ?int $excludedUserId = null, ?int $excludedAssignmentId = null): bool
    {
        $query = DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->join('users as user', 'user.id', '=', 'assignment.user_id')
            ->where('branch.chain_id', $chainId)->where('role.code', 'chain_owner')
            ->where('assignment.status', 'active')->whereDate('assignment.starts_on', '<=', now()->toDateString())
            ->where('user.is_active', true);
        if ($excludedUserId !== null) $query->where('assignment.user_id', '!=', $excludedUserId);
        if ($excludedAssignmentId !== null) $query->where('assignment.id', '!=', $excludedAssignmentId);

        return $query->exists();
    }
}
