<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\CatalogPermission;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ProfileController extends Controller
{
    public function show(Request $request, BranchAccess $access, CatalogPermission $catalogPermission): JsonResponse
    {
        $branches = $access->branchesFor($request->user());
        abort_if($branches->isEmpty(), 403);

        return response()->json([
            'user' => [
                'id' => $request->user()->id,
                'username' => $request->user()->username,
                'can_manage_catalog' => $catalogPermission->canManage($request->user()),
            ],
            'branches' => $branches,
        ]);
    }
}
