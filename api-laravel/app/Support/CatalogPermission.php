<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class CatalogPermission
{
    public function canManage(User $user): bool
    {
        if (! $user->is_active || ! $user->is_catalog_admin) {
            return false;
        }

        return DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->where('assignment.user_id', $user->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now()->toDateString())
            ->where('role.code', 'chain_owner')
            ->exists();
    }
}
