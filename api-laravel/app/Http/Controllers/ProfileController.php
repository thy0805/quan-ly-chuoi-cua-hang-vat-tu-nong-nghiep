<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\CatalogPermission;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ProfileController extends Controller
{
    public function show(Request $request, BranchAccess $access, CatalogPermission $catalogPermission): JsonResponse
    {
        $branches = $access->branchesFor($request->user());
        abort_if($branches->isEmpty(), 403);
        $canManageSync = DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->where('assignment.user_id', $request->user()->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now()->toDateString())
            ->where('role.code', 'chain_owner')->exists();

        return response()->json([
            'user' => [
                'id' => $request->user()->id,
                'username' => $request->user()->username,
                'can_manage_catalog' => $catalogPermission->canManage($request->user()),
                'can_manage_sync' => $canManageSync,
            ],
            'branches' => $branches,
        ]);
    }
}
