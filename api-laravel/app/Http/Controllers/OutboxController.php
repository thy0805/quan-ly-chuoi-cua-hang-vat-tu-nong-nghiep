<?php

namespace App\Http\Controllers;

use App\Support\DecimalId;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class OutboxController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $branches = $this->ownerBranches($request);
        abort_if($branches === [], 403);
        $data = $request->validate(['status' => ['nullable', 'in:pending,processing,retry,failed,published']]);
        $rows = DB::table('outbox_events')->where('status', $data['status'] ?? 'failed')
            ->where(function ($query) use ($branches): void {
                $query->whereIn('payload->branch_id', $branches)
                    ->orWhereIn('payload->from_branch_id', $branches);
            })
            ->orderByDesc('id')->limit(50)->get([
                'id', 'aggregate_type', 'aggregate_id', 'event_type', 'status', 'attempt_count',
                'next_attempt_at', 'last_error', 'created_at', 'published_at', 'payload',
            ])->filter(fn ($event) => $this->inScope($event, $branches))
            ->take(50)->map(function ($event): object {
                $event->id = (string) $event->id;
                $event->aggregate_id = (string) $event->aggregate_id;
                unset($event->payload);

                return $event;
            })->values();

        return response()->json(['data' => $rows]);
    }

    public function retry(Request $request, string $id): JsonResponse
    {
        $id = DecimalId::parse($id, 'id');
        $branches = $this->ownerBranches($request);
        abort_if($branches === [], 403);
        DB::transaction(function () use ($id, $branches): void {
            $event = DB::table('outbox_events')->where('id', $id)->lockForUpdate()->first();
            abort_if($event === null, 404);
            abort_unless($this->inScope($event, $branches), 403);
            abort_unless($event->status === 'failed', 409);
            DB::table('outbox_events')->where('id', $id)->update([
                'status' => 'retry', 'attempt_count' => 0,
                'next_attempt_at' => now(), 'locked_at' => null,
            ]);
        });

        return response()->json(['id' => $id, 'status' => 'retry']);
    }

    private function ownerBranches(Request $request): array
    {
        $chainIds = DB::table('user_role_assignments as assignment')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as branch', 'branch.id', '=', 'assignment.branch_id')
            ->where('assignment.user_id', $request->user()->id)
            ->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', now()->toDateString())
            ->where('role.code', 'chain_owner')->pluck('branch.chain_id')->unique()->all();

        return DB::table('branches')->whereIn('chain_id', $chainIds)->pluck('id')->map(fn ($id) => (string) $id)->all();
    }

    private function inScope(object $event, array $branches): bool
    {
        $payload = is_string($event->payload) ? json_decode($event->payload, true) : (array) $event->payload;
        $branchId = $payload['branch_id'] ?? $payload['from_branch_id'] ?? null;

        return $branchId !== null && in_array((string) $branchId, $branches, true);
    }
}
