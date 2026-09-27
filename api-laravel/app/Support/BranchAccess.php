<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class BranchAccess
{
    public function branchesFor(User $user): Collection
    {
        $assignments = DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $user->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now()->toDateString())
            ->whereIn('role.code', ['chain_owner', 'branch_manager', 'sales_staff'])
            ->get(['role.code', 'branch.id as branch_id', 'branch.chain_id']);

        $directIds = $assignments
            ->whereIn('code', ['branch_manager', 'sales_staff'])
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
