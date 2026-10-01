<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class BranchAccess
{
    public function branchesFor(User $user, array $directRoles = ['branch_manager', 'sales_staff']): Collection
    {
        $assignments = DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $user->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now('Asia/Ho_Chi_Minh')->toDateString())
            ->whereIn('role.code', array_merge(['chain_owner'], $directRoles))
            ->get(['role.code', 'branch.id as branch_id', 'branch.chain_id']);

        $directIds = $assignments
            ->whereIn('code', $directRoles)
            ->pluck('branch_id')
            ->all();
        $chainIds = $assignments
            ->where('code', 'chain_owner')
            ->pluck('chain_id')
            ->unique()
            ->all();

        return DB::table('branches')
            ->where(function ($query) use ($directIds, $chainIds): void {
                $query->whereIn('id', $directIds)->orWhereIn('chain_id', $chainIds);
            })
            ->orderBy('name')
            ->get(['id', 'chain_id', 'code', 'name']);
    }
}
