<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class PartnerAccess
{
    public function chainIds(User $user, array $roles): Collection
    {
        return DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $user->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now()->toDateString())
            ->whereIn('role.code', $roles)
            ->distinct()
            ->pluck('branch.chain_id');
    }
}
