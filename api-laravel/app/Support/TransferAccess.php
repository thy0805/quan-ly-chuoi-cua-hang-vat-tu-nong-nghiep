<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\DB;

class TransferAccess
{
    public function canRequest(User $user, string $branchId): bool
    {
        return $this->assignments($user)
            ->where('assignment.branch_id', $branchId)
            ->whereIn('role.code', ['branch_manager', 'sales_staff'])
            ->exists();
    }

    public function canApprove(User $user, string $branchId, string $chainId): bool
    {
        return $this->assignments($user)
            ->where(function ($query) use ($branchId, $chainId): void {
                $query->where(function ($query) use ($branchId): void {
                    $query->where('role.code', 'branch_manager')->where('assignment.branch_id', $branchId);
                })->orWhere(function ($query) use ($chainId): void {
                    $query->where('role.code', 'chain_owner')->where('branch.chain_id', $chainId);
                });
            })->exists();
    }

    public function canReceive(User $user, string $branchId): bool
    {
        return $this->canRequest($user, $branchId);
    }

    public function canReconcile(User $user, string $sourceBranchId, string $targetBranchId, string $chainId): bool
    {
        $query = $this->assignments($user);
        if ((clone $query)->where('role.code', 'chain_owner')->where('branch.chain_id', $chainId)->exists()) return true;

        foreach (array_unique([$sourceBranchId, $targetBranchId]) as $branchId) {
            if (! (clone $query)->where('role.code', 'branch_manager')->where('assignment.branch_id', $branchId)->exists()) return false;
        }

        return true;
    }

    private function assignments(User $user)
    {
        return DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $user->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now()->toDateString());
    }
}
