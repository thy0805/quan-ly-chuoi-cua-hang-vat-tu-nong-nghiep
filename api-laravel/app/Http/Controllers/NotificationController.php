<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\NotificationStore;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request, BranchAccess $access, NotificationStore $store): JsonResponse
    {
        $data = $request->validate(['status' => ['nullable', 'in:unread,read']]);
        $branches = $this->branches($request, $access);

        return response()->json($store->list((string) $request->user()->id, $branches, $data['status'] ?? null));
    }

    public function markRead(Request $request, BranchAccess $access, NotificationStore $store, string $id): JsonResponse
    {
        abort_unless(preg_match('/^[1-9][0-9]*:[1-9][0-9]*$/D', $id), 404);
        $branches = $this->branches($request, $access);
        $notification = $store->markRead($id, (string) $request->user()->id, $branches);
        abort_if($notification === null, 404);

        return response()->json(['data' => $notification]);
    }

    private function branches(Request $request, BranchAccess $access): array
    {
        $branches = $access->branchesFor($request->user())->pluck('id')->map(fn ($id) => (string) $id)->all();
        abort_if($branches === [], 403);

        return $branches;
    }
}
