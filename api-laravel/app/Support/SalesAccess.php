<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class SalesAccess
{
    public function canSell(User $user, string $branchId, string $chainId): bool
    {
        return DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $user->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now('Asia/Ho_Chi_Minh')->toDateString())
            ->where(function ($query) use ($branchId, $chainId): void {
                $query->where(function ($query) use ($branchId): void {
                    $query->where('assignment.branch_id', $branchId)
                        ->whereIn('role.code', ['branch_manager', 'sales_staff']);
                })->orWhere(function ($query) use ($chainId): void {
                    $query->where('branch.chain_id', $chainId)->where('role.code', 'chain_owner');
                });
            })->exists();
    }
}
