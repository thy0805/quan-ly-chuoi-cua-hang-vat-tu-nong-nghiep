<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class ReceiptAccess
{
    public function canCreate(User $user, int $branchId): bool
    {
        return $this->assignments($user)
            ->where('assignment.branch_id', $branchId)
            ->whereIn('role.code', ['branch_manager', 'sales_staff'])
            ->exists();
    }

    public function canApprove(User $user, int $branchId, int $chainId): bool
    {
        return $this->assignments($user)
            ->where(function ($query) use ($branchId, $chainId): void {
                $query->where(function ($query) use ($branchId): void {
                    $query->where('role.code', 'branch_manager')
                        ->where('assignment.branch_id', $branchId);
                })->orWhere(function ($query) use ($chainId): void {
                    $query->where('role.code', 'chain_owner')
                        ->where('branch.chain_id', $chainId);
                });
            })
            ->exists();
    }

    private function assignments(User $user)
    {
        return DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $user->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now('Asia/Ho_Chi_Minh')->toDateString());
    }
}
