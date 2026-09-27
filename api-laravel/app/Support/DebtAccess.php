<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class DebtAccess
{
    public function canView(User $user, string $type, string $branchId, string $chainId): bool
    {
        return $this->allows($user, $type, $branchId, $chainId);
    }

    public function canPay(User $user, string $type, string $branchId, string $chainId): bool
    {
        return $this->allows($user, $type, $branchId, $chainId);
    }

    private function allows(User $user, string $type, string $branchId, string $chainId): bool
    {
        return DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as assigned_branch', 'assigned_branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $user->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now()->toDateString())
            ->where(function ($query) use ($type, $branchId, $chainId): void {
                $query->where(function ($query) use ($chainId): void {
                    $query->where('role.code', 'chain_owner')->where('assigned_branch.chain_id', $chainId);
                })->orWhere(function ($query) use ($type, $branchId): void {
                    $query->where('assignment.branch_id', $branchId)
                        ->whereIn('role.code', $type === 'receivable' ? ['branch_manager', 'sales_staff'] : ['branch_manager']);
                });
            })->exists();
    }
}
