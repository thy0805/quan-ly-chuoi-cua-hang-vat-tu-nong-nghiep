<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

class InventoryAlertScanner
{
    public function run(OutboxService $outbox): array
    {
        return DB::transaction(function () use ($outbox): array {
            if (DB::getDriverName() === 'pgsql') DB::select('SELECT pg_advisory_xact_lock(18602702)');
            $today = now('Asia/Ho_Chi_Minh')->toDateString();
            $active = DB::table('inventory_alert_incidents')->where('status', 'open')->lockForUpdate()->get()->keyBy('incident_key');
            $current = $this->currentAlerts($today);
            $recipients = [];
            $opened = 0;
            $resolved = 0;

            foreach ($current as $alert) {
                if ($active->has($alert['incident_key'])) {
                    DB::table('inventory_alert_incidents')->where('id', $active[$alert['incident_key']]->id)
                        ->update(['last_seen_at' => now(), 'severity' => $alert['severity']]);
                    continue;
                }
                $incidentId = DB::table('inventory_alert_incidents')->insertGetId([
                    'incident_key' => $alert['incident_key'], 'kind' => $alert['kind'],
                    'severity' => $alert['severity'], 'branch_id' => $alert['branch_id'],
                    'warehouse_id' => $alert['warehouse_id'], 'product_id' => $alert['product_id'],
                    'lot_id' => $alert['lot_id'], 'status' => 'open',
                    'opened_at' => now(), 'last_seen_at' => now(),
                ]);
                $branchId = (string) $alert['branch_id'];
                $recipients[$branchId] ??= $this->recipients($branchId, $today);
                $outbox->record('inventory_alert_incident', (string) $incidentId, 'inventory.alert_opened', [
                    'branch_id' => $branchId, 'warehouse_id' => (string) $alert['warehouse_id'],
                    'product_id' => (string) $alert['product_id'],
                    'lot_id' => $alert['lot_id'] === null ? null : (string) $alert['lot_id'],
                    'kind' => $alert['kind'], 'severity' => $alert['severity'],
                    'message' => $alert['message'], 'recipient_user_ids' => $recipients[$branchId],
                ]);
                $opened++;
            }

            foreach ($active as $key => $incident) {
                if (isset($current[$key])) continue;
                DB::table('inventory_alert_incidents')->where('id', $incident->id)
                    ->update(['status' => 'resolved', 'resolved_at' => now()]);
                $outbox->record('inventory_alert_incident', (string) $incident->id, 'inventory.alert_resolved', [
                    'branch_id' => (string) $incident->branch_id,
                    'incident_id' => (string) $incident->id,
                ]);
                $resolved++;
            }

            return ['open' => count($current), 'created' => $opened, 'resolved' => $resolved];
        });
    }

    private function currentAlerts(string $today): array
    {
        $alerts = [];
        $low = DB::table('warehouse_product_settings as setting')
            ->join('warehouses as warehouse', 'warehouse.id', '=', 'setting.warehouse_id')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('products as product', 'product.id', '=', 'setting.product_id')
            ->leftJoin('product_lots as lot', 'lot.product_id', '=', 'product.id')
            ->leftJoin('inventories as inventory', function ($join): void {
                $join->on('inventory.lot_id', '=', 'lot.id')->on('inventory.warehouse_id', '=', 'warehouse.id');
            })
            ->groupBy('warehouse.id', 'warehouse.name', 'branch.id', 'product.id', 'product.name', 'setting.min_stock_quantity')
            ->havingRaw('COALESCE(SUM(inventory.quantity), 0) < setting.min_stock_quantity')
            ->select(['warehouse.id as warehouse_id', 'warehouse.name as warehouse_name',
                'branch.id as branch_id', 'product.id as product_id', 'product.name as product_name'])
            ->get();
        foreach ($low as $item) {
            $key = 'low:'.$item->warehouse_id.':'.$item->product_id;
            $alerts[$key] = [
                'incident_key' => $key, 'kind' => 'low_stock', 'severity' => 'low_stock',
                'branch_id' => $item->branch_id, 'warehouse_id' => $item->warehouse_id,
                'product_id' => $item->product_id, 'lot_id' => null,
                'message' => $item->product_name.' tại '.$item->warehouse_name.' đang dưới ngưỡng tồn tối thiểu.',
            ];
        }

        $expiry = DB::table('inventories as inventory')
            ->join('warehouses as warehouse', 'warehouse.id', '=', 'inventory.warehouse_id')
            ->join('branches as branch', 'branch.id', '=', 'warehouse.branch_id')
            ->join('product_lots as lot', 'lot.id', '=', 'inventory.lot_id')
            ->join('products as product', 'product.id', '=', 'lot.product_id')
            ->where('inventory.quantity', '>', 0)->whereNotNull('lot.expires_on')
            ->whereRaw(DB::getDriverName() === 'pgsql'
                ? 'lot.expires_on <= (CAST(? AS DATE) + COALESCE(product.expiry_warning_days, 30))'
                : "date(lot.expires_on) <= date(?, '+' || COALESCE(product.expiry_warning_days, 30) || ' days')", [$today])
            ->select(['warehouse.id as warehouse_id', 'warehouse.name as warehouse_name',
                'branch.id as branch_id', 'product.id as product_id', 'product.name as product_name',
                'lot.id as lot_id', 'lot.lot_no', 'lot.expires_on'])
            ->get();
        foreach ($expiry as $item) {
            $key = 'expiry:'.$item->warehouse_id.':'.$item->lot_id;
            $expired = substr((string) $item->expires_on, 0, 10) < $today;
            $alerts[$key] = [
                'incident_key' => $key, 'kind' => 'expiry', 'severity' => $expired ? 'expired' : 'expiring',
                'branch_id' => $item->branch_id, 'warehouse_id' => $item->warehouse_id,
                'product_id' => $item->product_id, 'lot_id' => $item->lot_id,
                'message' => $item->product_name.' lô '.$item->lot_no.' tại '.$item->warehouse_name
                    .($expired ? ' đã hết hạn.' : ' sắp hết hạn.'),
            ];
        }

        return $alerts;
    }

    private function recipients(string $branchId, string $today): array
    {
        $chainId = DB::table('branches')->where('id', $branchId)->value('chain_id');

        return DB::table('user_role_assignments as assignment')
            ->join('users as user', 'user.id', '=', 'assignment.user_id')
            ->join('roles as role', 'role.id', '=', 'assignment.role_id')
            ->join('branches as assigned_branch', 'assigned_branch.id', '=', 'assignment.branch_id')
            ->where('user.is_active', true)->where('assignment.status', 'active')
            ->whereDate('assignment.starts_on', '<=', $today)
            ->where(function ($query) use ($branchId, $chainId): void {
                $query->where(function ($query) use ($chainId): void {
                    $query->where('role.code', 'chain_owner')->where('assigned_branch.chain_id', $chainId);
                })->orWhere(function ($query) use ($branchId): void {
                    $query->whereIn('role.code', ['branch_manager', 'sales_staff'])
                        ->where('assignment.branch_id', $branchId);
                });
            })->distinct()->pluck('user.id')->map(fn ($id) => (string) $id)->all();
    }
}
