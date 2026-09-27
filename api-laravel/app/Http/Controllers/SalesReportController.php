<?php

namespace App\Http\Controllers;

use App\Support\BranchAccess;
use App\Support\DecimalId;
use Brick\Math\BigDecimal;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class SalesReportController extends Controller
{
    public function index(Request $request, BranchAccess $access): JsonResponse
    {
        $filters = $request->validate([
            'period' => ['required', 'in:day,month,year'],
            'date' => ['required', 'date_format:Y-m-d'],
            'chain_id' => ['nullable', 'string', DecimalId::rule()],
            'branch_id' => ['nullable', 'string', DecimalId::rule()],
        ]);
        $branches = $access->branchesFor($request->user(), ['branch_manager']);
        abort_if($branches->isEmpty(), 403);
        $chainIds = $branches->pluck('chain_id')->map(fn ($id) => (string) $id)->unique()->values();
        $chainId = $filters['chain_id'] ?? null;
        if ($chainId === null && $chainIds->count() > 1) {
            throw ValidationException::withMessages(['chain_id' => 'Hãy chọn chuỗi cần xem báo cáo.']);
        }
        $chainId ??= $chainIds->first();
        abort_unless($chainIds->contains($chainId), 403);
        $branches = $branches->filter(fn ($branch) => (string) $branch->chain_id === $chainId)->values();
        $branchId = $filters['branch_id'] ?? null;
        abort_if($branchId !== null && ! $branches->contains(fn ($branch) => (string) $branch->id === $branchId), 403);

        $local = CarbonImmutable::createFromFormat('!Y-m-d', $filters['date'], 'Asia/Ho_Chi_Minh');
        $start = match ($filters['period']) {
            'day' => $local->startOfDay(),
            'month' => $local->startOfMonth(),
            'year' => $local->startOfYear(),
        };
        $end = match ($filters['period']) {
            'day' => $start->addDay(),
            'month' => $start->addMonth(),
            'year' => $start->addYear(),
        };

        $items = DB::table('sales_order_items as item')
            ->select('item.order_id')
            ->selectRaw('SUM(ROUND(item.quantity * item.unit_price, 2)) as gross_sales')
            ->selectRaw('SUM(item.discount_amount) as total_discount')
            ->selectRaw('SUM(item.tax_amount) as total_tax')
            ->selectRaw('SUM(ROUND(item.quantity * item.unit_cost_snapshot, 2)) as cogs')
            ->selectRaw('SUM(CASE WHEN item.unit_cost_snapshot IS NULL THEN 1 ELSE 0 END) as incomplete_cost_items')
            ->selectRaw('SUM(CASE WHEN item.tax_amount IS NULL OR item.tax_rate_snapshot IS NULL THEN 1 ELSE 0 END) as incomplete_tax_items')
            ->groupBy('item.order_id');
        $payments = DB::table('payments')
            ->where('status', 'completed')
            ->whereNotNull('invoice_id')
            ->select('invoice_id')
            ->selectRaw('SUM(amount) as amount_collected')
            ->groupBy('invoice_id');
        $orders = DB::table('sales_orders as sale')
            ->join('invoices as invoice', 'invoice.sales_order_id', '=', 'sale.id')
            ->join('branches as branch', 'branch.id', '=', 'sale.branch_id')
            ->joinSub($items, 'item_totals', fn ($join) => $join->on('item_totals.order_id', '=', 'sale.id'))
            ->leftJoinSub($payments, 'payment_totals', fn ($join) => $join->on('payment_totals.invoice_id', '=', 'invoice.id'))
            ->where('sale.status', 'confirmed')
            ->whereIn('sale.branch_id', $branches->pluck('id')->all())
            ->where('sale.sold_at', '>=', $start->utc()->toDateTimeString())
            ->where('sale.sold_at', '<', $end->utc()->toDateTimeString());
        if ($branchId !== null) $orders->where('sale.branch_id', $branchId);
        $rows = $orders->orderBy('sale.sold_at')->select([
            'sale.id', 'sale.branch_id', 'sale.sold_at', 'branch.name as branch_name',
            'invoice.total_amount as recorded_invoice_total', 'item_totals.gross_sales',
            'item_totals.total_discount', 'item_totals.total_tax', 'item_totals.cogs',
            'item_totals.incomplete_cost_items', 'item_totals.incomplete_tax_items', 'payment_totals.amount_collected',
        ])->cursor();

        $summary = $this->emptyMetrics();
        $byBranch = [];
        $trend = [];
        foreach ($rows as $row) {
            $gross = BigDecimal::of((string) $row->gross_sales);
            $discount = BigDecimal::of((string) $row->total_discount);
            $tax = BigDecimal::of((string) ($row->total_tax ?? '0'));
            $net = $gross->minus($discount);
            $invoiceTotal = $net->plus($tax);
            $collected = BigDecimal::of((string) ($row->amount_collected ?? '0'));
            $cogs = BigDecimal::of((string) ($row->cogs ?? '0'));
            $values = [
                'gross_sales' => $gross, 'total_discount' => $discount,
                'net_sales' => $net, 'total_tax' => $tax,
                'invoice_total' => $invoiceTotal, 'cogs' => $cogs,
                'gross_profit' => $net->minus($cogs), 'amount_collected' => $collected,
                'receivable_remaining' => $invoiceTotal->minus($collected),
            ];
            $incompleteCost = (int) $row->incomplete_cost_items > 0;
            $incompleteTax = (int) $row->incomplete_tax_items > 0;
            $mismatch = ! $invoiceTotal->isEqualTo((string) $row->recorded_invoice_total);
            $this->accumulate($summary, $values, $incompleteCost, $incompleteTax, $mismatch);

            $key = (string) $row->branch_id;
            if (! isset($byBranch[$key])) $byBranch[$key] = ['branch_id' => $key, 'branch_name' => $row->branch_name, 'metrics' => $this->emptyMetrics()];
            $this->accumulate($byBranch[$key]['metrics'], $values, $incompleteCost, $incompleteTax, $mismatch);

            $soldAt = CarbonImmutable::parse($row->sold_at)->setTimezone('Asia/Ho_Chi_Minh');
            $bucket = match ($filters['period']) {
                'day' => $soldAt->format('H:00'),
                'month' => $soldAt->format('Y-m-d'),
                'year' => $soldAt->format('Y-m'),
            };
            if (! isset($trend[$bucket])) $trend[$bucket] = ['bucket' => $bucket, 'metrics' => $this->emptyMetrics()];
            $this->accumulate($trend[$bucket]['metrics'], $values, $incompleteCost, $incompleteTax, $mismatch);
        }

        $summary = $this->present($summary);
        $branchRows = array_values(array_map(fn ($row) => [
            'branch_id' => $row['branch_id'], 'branch_name' => $row['branch_name'],
            'metrics' => $this->present($row['metrics']),
        ], $byBranch));
        usort($branchRows, fn ($a, $b) => strcmp($a['branch_name'], $b['branch_name']));
        $trendRows = array_values(array_map(fn ($row) => [
            'bucket' => $row['bucket'], 'metrics' => $this->present($row['metrics']),
        ], $trend));

        return response()->json([
            'period' => $filters['period'], 'date' => $filters['date'], 'chain_id' => $chainId,
            'timezone' => 'Asia/Ho_Chi_Minh',
            'branches' => $branches->map(fn ($branch) => [
                'id' => (string) $branch->id, 'chain_id' => (string) $branch->chain_id, 'name' => $branch->name,
            ])->values(),
            'summary' => $summary, 'by_branch' => $branchRows, 'trend' => $trendRows,
        ]);
    }

    private function emptyMetrics(): array
    {
        return [
            'invoice_count' => 0, 'gross_sales' => BigDecimal::zero(),
            'total_discount' => BigDecimal::zero(), 'net_sales' => BigDecimal::zero(),
            'total_tax' => BigDecimal::zero(), 'invoice_total' => BigDecimal::zero(),
            'cogs' => BigDecimal::zero(), 'gross_profit' => BigDecimal::zero(),
            'amount_collected' => BigDecimal::zero(), 'receivable_remaining' => BigDecimal::zero(),
            'incomplete_cost_count' => 0, 'incomplete_tax_count' => 0, 'invoice_mismatch_count' => 0,
        ];
    }

    private function accumulate(array &$target, array $values, bool $incompleteCost, bool $incompleteTax, bool $mismatch): void
    {
        $target['invoice_count']++;
        foreach ($values as $field => $amount) $target[$field] = $target[$field]->plus($amount);
        if ($incompleteCost) $target['incomplete_cost_count']++;
        if ($incompleteTax) $target['incomplete_tax_count']++;
        if ($mismatch) $target['invoice_mismatch_count']++;
    }

    private function present(array $metrics): array
    {
        foreach (['gross_sales', 'total_discount', 'net_sales', 'total_tax', 'invoice_total', 'cogs', 'gross_profit', 'amount_collected', 'receivable_remaining'] as $field) {
            $metrics[$field] = (string) $metrics[$field]->toScale(2);
        }
        if ($metrics['incomplete_cost_count'] > 0) {
            $metrics['cogs'] = null;
            $metrics['gross_profit'] = null;
        }
        if ($metrics['incomplete_tax_count'] > 0) {
            $metrics['total_tax'] = null;
            $metrics['invoice_total'] = null;
            $metrics['receivable_remaining'] = null;
        }

        return $metrics;
    }
}
