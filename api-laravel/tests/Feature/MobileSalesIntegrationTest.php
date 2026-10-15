<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class MobileSalesIntegrationTest extends TestCase
{
    use MobileSalesFixture;

    private User $seller;
    private string $token;
    private array $businessTables = ['sales_orders', 'sales_order_items', 'inventories', 'invoices', 'payments', 'debts', 'debt_transactions', 'stock_movements', 'outbox_events'];

    protected function setUp(): void
    {
        parent::setUp();
        $this->assertTrue(app()->environment('testing'));
        $this->assertSame('sqlite', config('database.default'));
        $this->assertSame(':memory:', config('database.connections.sqlite.database'));
        $this->assertEmpty(config('database.connections.sqlite.url'));
        config(['database.connections' => ['sqlite' => config('database.connections.sqlite')]]);
        $this->assertSame('sqlite', DB::connection()->getDriverName());
        $this->assertSame('', DB::select('PRAGMA database_list')[0]->file);
        DB::listen(function ($query): void {
            $this->assertSame('sqlite', $query->connection->getDriverName());
            $this->assertSame(':memory:', $query->connection->getDatabaseName());
        });
        $this->freezeTime();
        $this->createSalesSchema();
        DB::table('chains')->insert([['id' => 1, 'name' => 'A'], ['id' => 2, 'name' => 'B']]);
        foreach ([1 => 1, 2 => 1, 3 => 2] as $branch => $chain) {
            DB::table('branches')->insert(['id' => $branch, 'chain_id' => $chain, 'code' => 'B'.$branch, 'name' => 'Branch '.$branch]);
            DB::table('warehouses')->insert(['id' => $branch, 'branch_id' => $branch, 'name' => 'Warehouse '.$branch]);
            DB::table('customers')->insert(['id' => $branch, 'chain_id' => $chain, 'name' => 'Customer '.$branch, 'customer_type' => 'farmer']);
        }
        DB::table('roles')->insert(['id' => 1, 'code' => 'sales_staff', 'name' => 'Sales']);
        DB::table('units')->insert(['id' => 1, 'name' => 'Bao']);
        DB::table('product_categories')->insert(['id' => 1, 'code' => 'NPK', 'name' => 'Phân']);
        DB::table('products')->insert(['id' => 1, 'category_id' => 1, 'unit_id' => 1, 'code' => 'NPK01', 'name' => 'NPK', 'sale_price' => '100000.00', 'tax_rate' => '5.00']);
        DB::table('product_lots')->insert(['id' => 1, 'product_id' => 1, 'lot_no' => 'L01', 'expires_on' => now('Asia/Ho_Chi_Minh')->addDays(20)->toDateString()]);
        foreach ([1, 2, 3] as $warehouse) {
            DB::table('inventories')->insert(['warehouse_id' => $warehouse, 'lot_id' => 1, 'quantity' => '20.000', 'average_unit_cost' => '60000.000000']);
        }
        $this->seller = $this->userAt(1);
        $this->token = $this->login($this->seller);
    }

    private function userAt(int $branch): User
    {
        $user = User::create(['username' => 's25-'.User::count(), 'password_hash' => Hash::make('isolated-test-password'), 'is_active' => true]);
        DB::table('user_role_assignments')->insert(['user_id' => $user->id, 'role_id' => 1, 'branch_id' => $branch, 'starts_on' => '2020-01-01', 'status' => 'active']);
        return $user;
    }

    private function login(User $user): string
    {
        $this->app['auth']->forgetGuards();
        $response = $this->postJson('/api/mobile/login', ['username' => $user->username, 'password' => 'isolated-test-password', 'device_name' => 'Isolated S25'])
            ->assertOk()->assertJsonPath('token_type', 'Bearer');
        $this->assertGuest('web');
        return $response->json('token');
    }

    private function api(string $method, string $path, array $body = [], ?string $token = null)
    {
        $this->app['auth']->forgetGuards();
        $this->assertGuest('web');
        return $this->json($method, '/api/'.$path, $body, ['Authorization' => 'Bearer '.($token ?? $this->token)]);
    }

    private function payload(?string $customer = '1'): array
    {
        return ['branch_id' => '1', 'warehouse_id' => '1', 'customer_id' => $customer,
            'items' => [['lot_id' => '1', 'quantity' => '2.000', 'discount_amount' => '20000.00']]];
    }

    private function draft(?string $customer = '1'): string
    {
        $id = $this->api('POST', 'sales-orders', $this->payload($customer))->assertCreated()->assertJsonPath('status', 'draft')->json('id');
        $this->assertIsString($id);
        return $id;
    }

    private function state(): array
    {
        $state = [];
        foreach ($this->businessTables as $table) $state[$table] = DB::table($table)->orderBy('id')->get()->toJson();
        return $state;
    }

    public static function collections(): array
    {
        return ['guest cash' => [null, '189000.00', 'cash', '0.00'],
            'customer bank' => ['1', '189000.00', 'bank_transfer', '0.00'],
            'customer partial' => ['1', '100000.00', 'cash', '89000.00'],
            'customer later' => ['1', '0.00', null, '189000.00']];
    }

    #[DataProvider('collections')]
    public function test_bearer_sale_chain_snapshots_and_sequential_reconfirm(?string $customer, string $paid, ?string $method, string $remaining): void
    {
        $this->api('GET', 'sales-orders/options')->assertOk()->assertJsonCount(1, 'warehouses')->assertJsonPath('warehouses.0.id', '1')->assertJsonCount(2, 'customers')->assertJsonCount(1, 'stock');
        $id = $this->draft($customer);
        $this->api('GET', 'sales-orders/'.$id)->assertOk()->assertJsonPath('data.id', $id)->assertJsonPath('data.created_by', (string) $this->seller->id)->assertJsonPath('data.invoice_id', null);
        $this->assertEquals(20, DB::table('inventories')->where('warehouse_id', 1)->value('quantity'));
        $this->assertDatabaseCount('outbox_events', 0);
        $this->api('POST', 'sales-orders/'.$id.'/confirm', ['amount' => $paid, 'method' => $method])->assertOk()->assertJsonPath('id', $id)->assertJsonPath('status', 'confirmed');
        $detail = $this->api('GET', 'sales-orders/'.$id)->assertOk()->assertJsonPath('data.status', 'confirmed')->assertJsonPath('data.paid_amount', $paid)->assertJsonPath('data.remaining_amount', $remaining);
        $invoice = $detail->json('data.invoice_id');
        $this->assertIsString($invoice);
        $this->assertEquals(189000, $detail->json('data.total_amount'));
        $this->assertEquals(9000, $detail->json('data.invoice_tax_amount'));
        $this->assertEquals(60000, $detail->json('items.0.unit_cost_snapshot'));
        $this->assertEquals(120000, $detail->json('items.0.cost_total'));
        $this->assertEquals(18, DB::table('inventories')->where('warehouse_id', 1)->value('quantity'));
        $this->assertDatabaseCount('invoices', 1);
        $this->assertDatabaseCount('stock_movements', 1);
        $this->assertDatabaseCount('outbox_events', 1);
        $this->assertDatabaseCount('payments', $paid === '0.00' ? 0 : 1);
        $this->assertDatabaseCount('debts', $customer === null ? 0 : 1);
        $this->assertDatabaseCount('debt_transactions', $customer === null ? 0 : ($paid === '0.00' ? 1 : 2));
        $event = json_decode(DB::table('outbox_events')->value('payload'), true, flags: JSON_THROW_ON_ERROR);
        $this->assertSame($invoice, $event['invoice_id']);
        $before = $this->state();
        $this->api('POST', 'sales-orders/'.$id.'/confirm', ['amount' => $paid, 'method' => $method])->assertStatus(409);
        $this->assertSame($before, $this->state());
    }

    public static function invalidSessions(): array
    {
        return ['locked' => ['locked', 403], 'assignment revoked' => ['assignment', 403], 'expired' => ['expired', 401], 'token revoked' => ['revoked', 401]];
    }

    #[DataProvider('invalidSessions')]
    public function test_bearer_loses_access_after_draft_without_business_writes(string $mutation, int $status): void
    {
        $this->api('GET', 'sales-orders/options')->assertOk();
        $id = $this->draft();
        match ($mutation) {
            'locked' => $this->seller->update(['is_active' => false]),
            'assignment' => DB::table('user_role_assignments')->where('user_id', $this->seller->id)->update(['status' => 'revoked']),
            'expired' => DB::table('personal_access_tokens')->update(['expires_at' => now()->subSecond()]),
            'revoked' => DB::table('personal_access_tokens')->delete(),
        };
        $before = $this->state();
        foreach (['sales-orders/options', 'sales-orders', 'sales-orders/'.$id] as $path) {
            $expected = $mutation === 'assignment' && $path === 'sales-orders/'.$id ? 404 : $status;
            $this->api('GET', $path)->assertStatus($expected);
        }
        $this->api('POST', 'sales-orders', $this->payload())->assertStatus($status);
        $this->api('POST', 'sales-orders/'.$id.'/confirm', ['amount' => '0'])->assertStatus($status);
        $this->assertSame($before, $this->state());
    }

    public function test_bearer_scopes_creator_and_customer_warehouse_boundaries(): void
    {
        $id = $this->draft();
        $sameBranchToken = $this->login($this->userAt(1));
        $this->api('GET', 'sales-orders/'.$id, token: $sameBranchToken)->assertOk();
        $before = $this->state();
        $this->api('POST', 'sales-orders/'.$id.'/confirm', ['amount' => '0'], $sameBranchToken)->assertForbidden();
        foreach ([2, 3] as $branch) {
            $token = $this->login($this->userAt($branch));
            $this->api('GET', 'sales-orders/options', token: $token)->assertOk()->assertJsonCount(1, 'warehouses')->assertJsonPath('warehouses.0.id', (string) $branch);
            $this->api('GET', 'sales-orders', token: $token)->assertOk()->assertJsonCount(0, 'data');
            $this->api('GET', 'sales-orders/'.$id, token: $token)->assertNotFound();
            $this->api('POST', 'sales-orders/'.$id.'/confirm', ['amount' => '0'], $token)->assertForbidden();
        }
        $this->api('POST', 'sales-orders', array_replace($this->payload(), ['branch_id' => '2', 'warehouse_id' => '2']))->assertForbidden();
        $this->api('POST', 'sales-orders', array_replace($this->payload(), ['warehouse_id' => '2']))->assertUnprocessable()->assertJsonValidationErrors('warehouse_id');
        $this->api('POST', 'sales-orders', array_replace($this->payload(), ['customer_id' => '3']))->assertUnprocessable()->assertJsonValidationErrors('customer_id');
        $this->assertSame($before, $this->state());
    }

    public static function staleData(): array
    {
        return array_combine($cases = ['price', 'tax', 'cost', 'tax_snapshot', 'tax_amount', 'stock', 'expired', 'branch', 'chain', 'product', 'category', 'unit'], array_map(fn ($case) => [$case], $cases));
    }

    #[DataProvider('staleData')]
    public function test_bearer_confirmation_revalidates_draft_and_rolls_back(string $case): void
    {
        $this->api('GET', 'sales-orders/options')->assertOk();
        $id = $this->draft();
        match ($case) {
            'price' => DB::table('products')->update(['sale_price' => '100001.00']),
            'tax' => DB::table('products')->update(['tax_rate' => '10.00']),
            'cost' => DB::table('inventories')->where('warehouse_id', 1)->update(['average_unit_cost' => null]),
            'tax_snapshot' => DB::table('sales_order_items')->update(['tax_rate_snapshot' => null]),
            'tax_amount' => DB::table('sales_order_items')->update(['tax_amount' => null]),
            'stock' => DB::table('inventories')->where('warehouse_id', 1)->update(['quantity' => '1.000']),
            'expired' => DB::table('product_lots')->update(['expires_on' => now('Asia/Ho_Chi_Minh')->subDay()->toDateString()]),
            'branch' => DB::table('branches')->where('id', 1)->update(['is_active' => false]),
            'chain' => DB::table('chains')->where('id', 1)->update(['is_active' => false]),
            'product' => DB::table('products')->update(['is_active' => false]),
            'category' => DB::table('product_categories')->update(['is_active' => false]),
            'unit' => DB::table('units')->update(['is_active' => false]),
        };
        $before = $this->state();
        $this->api('POST', 'sales-orders/'.$id.'/confirm', ['amount' => '0'])->assertUnprocessable();
        $this->assertSame($before, $this->state());
        $this->api('GET', 'sales-orders/'.$id)->assertOk()->assertJsonPath('data.status', 'draft')->assertJsonPath('data.invoice_id', null);
    }

    public function test_bearer_late_line_failure_rolls_back_earlier_inventory_and_cost_writes(): void
    {
        DB::table('product_lots')->insert(['id' => 2, 'product_id' => 1, 'lot_no' => 'L02']);
        DB::table('inventories')->insert(['warehouse_id' => 1, 'lot_id' => 2, 'quantity' => '20', 'average_unit_cost' => null]);
        $payload = $this->payload();
        $payload['items'][] = ['lot_id' => '2', 'quantity' => '1', 'discount_amount' => '0'];
        $id = $this->api('POST', 'sales-orders', $payload)->assertCreated()->json('id');
        $before = $this->state();
        $this->api('POST', 'sales-orders/'.$id.'/confirm', ['amount' => '0'])->assertUnprocessable()->assertJsonValidationErrors('items');
        $this->assertSame($before, $this->state());
        $this->assertNull(DB::table('sales_order_items')->where('lot_id', 1)->value('unit_cost_snapshot'));
    }

    public function test_bearer_invalid_contract_and_payment_failures_leave_no_business_delta(): void
    {
        foreach ([['branch_id' => 1], ['branch_id' => '9223372036854775808'], ['total_amount' => '1']] as $change) {
            $before = $this->state();
            $this->api('POST', 'sales-orders', array_replace($this->payload(), $change))->assertUnprocessable();
            $this->assertSame($before, $this->state());
        }
        $body = $this->payload();
        $body['items'][0]['quantity'] = '1000000000000000';
        $this->api('POST', 'sales-orders', $body)->assertUnprocessable();
        $this->assertDatabaseCount('sales_orders', 0);
        $id = $this->draft(null);
        foreach ([['amount' => '0'], ['amount' => '189000.01', 'method' => 'cash'], ['amount' => '1.001', 'method' => 'cash'], ['amount' => '189000', 'method' => 'cash', 'request_key' => 'forbidden']] as $body) {
            $before = $this->state();
            $this->api('POST', 'sales-orders/'.$id.'/confirm', $body)->assertUnprocessable();
            $this->assertSame($before, $this->state());
        }
        $this->api('GET', 'sales-orders/9223372036854775808')->assertUnprocessable();
    }

    public function test_bearer_large_string_ids_survive_draft_detail_and_confirmation(): void
    {
        $id = '9007199254740993';
        DB::table('product_lots')->where('id', 1)->update(['id' => $id]);
        DB::table('inventories')->update(['lot_id' => $id]);
        $body = $this->payload();
        $body['items'][0]['lot_id'] = $id;
        $this->api('GET', 'sales-orders/options')->assertOk()->assertJsonPath('stock.0.lot_id', $id);
        $order = $this->api('POST', 'sales-orders', $body)->assertCreated()->json('id');
        $this->api('GET', 'sales-orders/'.$order)->assertOk()->assertJsonPath('items.0.lot_id', $id);
        $this->api('POST', 'sales-orders/'.$order.'/confirm', ['amount' => '0'])->assertOk();
        $this->api('GET', 'sales-orders/'.$order)->assertOk()->assertJsonPath('items.0.lot_id', $id);
    }
}
