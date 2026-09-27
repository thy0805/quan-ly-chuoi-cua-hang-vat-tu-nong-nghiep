<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\InventoryAlertScanner;
use App\Support\NotificationStore;
use App\Support\OutboxService;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class InventoryAccessTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        Schema::create('users', function (Blueprint $table): void {
            $table->id();
            $table->string('username');
            $table->text('password_hash');
            $table->boolean('is_active');
            $table->boolean('is_catalog_admin')->default(false);
        });
        Schema::create('chains', function (Blueprint $table): void {
            $table->id();
            $table->string('name');
            $table->boolean('is_active')->default(true);
        });
        Schema::create('branches', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('chain_id');
            $table->string('code');
            $table->string('name');
            $table->string('address')->nullable();
            $table->unsignedBigInteger('default_sales_warehouse_id')->nullable();
            $table->boolean('is_active')->default(true);
        });
        Schema::create('warehouses', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('branch_id');
            $table->string('name');
            $table->string('code')->nullable();
            $table->string('warehouse_type')->nullable();
        });
        Schema::create('roles', function (Blueprint $table): void {
            $table->id();
            $table->string('code');
            $table->string('name');
        });
        Schema::create('user_role_assignments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id');
            $table->foreignId('role_id');
            $table->foreignId('branch_id')->nullable();
            $table->date('starts_on');
            $table->string('status');
        });
        Schema::create('suppliers', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('chain_id');
            $table->string('name');
            $table->string('phone')->nullable();
            $table->text('address')->nullable();
        });
        Schema::create('customers', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('chain_id');
            $table->string('name');
            $table->string('customer_type');
            $table->string('phone')->nullable();
            $table->text('address')->nullable();
        });
        Schema::create('units', function (Blueprint $table): void {
            $table->id();
            $table->string('name');
            $table->boolean('is_active')->default(true);
        });
        Schema::create('product_categories', function (Blueprint $table): void {
            $table->id();
            $table->string('code');
            $table->string('name');
            $table->boolean('is_active')->default(true);
        });
        Schema::create('products', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('category_id');
            $table->foreignId('unit_id');
            $table->string('code');
            $table->string('name');
            $table->decimal('sale_price', 18, 2)->default(0);
            $table->decimal('tax_rate', 5, 2)->nullable();
            $table->integer('expiry_warning_days')->nullable();
            $table->boolean('is_active')->default(true);
        });
        Schema::create('product_lots', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('product_id');
            $table->string('lot_no');
            $table->date('manufactured_on')->nullable();
            $table->date('expires_on')->nullable();
        });
        Schema::create('inventories', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('warehouse_id');
            $table->foreignId('lot_id');
            $table->decimal('quantity', 18, 3);
            $table->decimal('average_unit_cost', 18, 6)->nullable();
            $table->timestamp('updated_at')->nullable();
        });
        Schema::create('warehouse_product_settings', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('warehouse_id');
            $table->foreignId('product_id');
            $table->decimal('min_stock_quantity', 18, 3);
            $table->unique(['warehouse_id', 'product_id']);
        });
        Schema::create('inventory_alert_incidents', function (Blueprint $table): void {
            $table->id();
            $table->string('incident_key');
            $table->string('kind');
            $table->string('severity');
            $table->foreignId('branch_id');
            $table->foreignId('warehouse_id');
            $table->foreignId('product_id');
            $table->foreignId('lot_id')->nullable();
            $table->string('status');
            $table->timestamp('opened_at');
            $table->timestamp('last_seen_at');
            $table->timestamp('resolved_at')->nullable();
        });
        Schema::create('purchase_receipts', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('supplier_id');
            $table->foreignId('warehouse_id');
            $table->foreignId('created_by');
            $table->foreignId('approved_by')->nullable();
            $table->foreignId('rejected_by')->nullable();
            $table->string('receipt_no');
            $table->string('status');
            $table->decimal('total_amount', 18, 2);
            $table->timestamp('received_at')->nullable();
            $table->timestamp('submitted_at')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('rejected_at')->nullable();
            $table->text('rejection_reason')->nullable();
        });
        Schema::create('purchase_receipt_items', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('receipt_id');
            $table->foreignId('lot_id');
            $table->decimal('quantity', 18, 3);
            $table->decimal('unit_cost', 18, 2);
            $table->decimal('line_total', 18, 2);
        });
        Schema::create('stock_movements', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('warehouse_id');
            $table->foreignId('lot_id');
            $table->foreignId('purchase_receipt_id')->nullable();
            $table->foreignId('sales_order_id')->nullable();
            $table->foreignId('stock_transfer_id')->nullable();
            $table->string('movement_type');
            $table->decimal('quantity_delta', 18, 3);
            $table->timestamp('occurred_at')->nullable();
        });
        Schema::create('stock_transfers', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('from_warehouse_id');
            $table->foreignId('to_warehouse_id');
            $table->foreignId('requested_by');
            $table->foreignId('approved_by')->nullable();
            $table->foreignId('rejected_by')->nullable();
            $table->foreignId('dispatched_by')->nullable();
            $table->foreignId('received_by')->nullable();
            $table->foreignId('reconciled_by')->nullable();
            $table->string('transfer_no');
            $table->timestamp('requested_at')->useCurrent();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('rejected_at')->nullable();
            $table->text('rejection_reason')->nullable();
            $table->timestamp('dispatched_at')->nullable();
            $table->timestamp('received_at')->nullable();
            $table->timestamp('reconciled_at')->nullable();
            $table->text('reconciliation_reason')->nullable();
            $table->string('status');
        });
        Schema::create('stock_transfer_items', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('transfer_id');
            $table->foreignId('lot_id');
            $table->decimal('requested_quantity', 18, 3);
            $table->decimal('dispatched_quantity', 18, 3)->default(0);
            $table->decimal('received_quantity', 18, 3)->default(0);
            $table->decimal('transfer_unit_cost', 18, 6)->nullable();
            $table->decimal('supplemental_received_quantity', 18, 3)->default(0);
            $table->decimal('returned_quantity', 18, 3)->default(0);
            $table->decimal('lost_quantity', 18, 3)->default(0);
        });
        Schema::create('sales_orders', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('branch_id');
            $table->foreignId('warehouse_id');
            $table->foreignId('customer_id')->nullable();
            $table->string('season_label')->nullable();
            $table->foreignId('created_by');
            $table->string('order_no');
            $table->string('status');
            $table->decimal('total_amount', 18, 2);
            $table->timestamp('sold_at')->nullable();
        });
        Schema::create('sales_order_items', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('order_id');
            $table->foreignId('lot_id');
            $table->decimal('quantity', 18, 3);
            $table->decimal('unit_price', 18, 2);
            $table->decimal('discount_amount', 18, 2);
            $table->decimal('line_total', 18, 2);
            $table->decimal('tax_rate_snapshot', 5, 2)->nullable();
            $table->decimal('tax_amount', 18, 2)->nullable();
            $table->decimal('unit_cost_snapshot', 18, 6)->nullable();
            $table->decimal('cost_total', 18, 2)->nullable();
        });
        Schema::create('invoices', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('sales_order_id');
            $table->string('invoice_no');
            $table->timestamp('issued_at')->nullable();
            $table->decimal('subtotal', 18, 2);
            $table->decimal('discount_amount', 18, 2);
            $table->decimal('tax_amount', 18, 2);
            $table->decimal('total_amount', 18, 2);
            $table->string('status');
        });
        Schema::create('debts', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('customer_id')->nullable()->unique();
            $table->foreignId('supplier_id')->nullable()->unique();
            $table->string('debt_type');
            $table->decimal('opening_balance', 18, 2)->default(0);
            $table->string('status');
        });
        Schema::create('payments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('invoice_id')->nullable();
            $table->foreignId('purchase_receipt_id')->nullable();
            $table->foreignId('created_by')->nullable();
            $table->string('method');
            $table->decimal('amount', 18, 2);
            $table->timestamp('paid_at')->nullable();
            $table->string('status');
            $table->string('request_key')->nullable()->unique();
            $table->string('reference_note')->nullable();
        });
        Schema::create('debt_transactions', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('debt_id');
            $table->foreignId('payment_id')->nullable()->unique();
            $table->foreignId('invoice_id')->nullable();
            $table->foreignId('purchase_receipt_id')->nullable();
            $table->foreignId('branch_id');
            $table->foreignId('warehouse_id');
            $table->foreignId('created_by');
            $table->string('transaction_type');
            $table->decimal('amount', 18, 2);
            $table->timestamp('occurred_at')->nullable();
            $table->string('season_label')->nullable();
        });
        Schema::create('outbox_events', function (Blueprint $table): void {
            $table->id();
            $table->string('aggregate_type');
            $table->unsignedBigInteger('aggregate_id');
            $table->string('event_type');
            $table->integer('event_version')->default(1);
            $table->text('payload');
            $table->string('status')->default('pending');
            $table->integer('attempt_count')->default(0);
            $table->timestamp('next_attempt_at')->nullable();
            $table->timestamp('locked_at')->nullable();
            $table->text('last_error')->nullable();
            $table->timestamp('created_at')->nullable();
            $table->timestamp('published_at')->nullable();
        });
    }

    public function test_guest_cannot_read_inventory(): void
    {
        $this->getJson('/api/inventory')->assertUnauthorized();
    }

    public function test_manager_sees_only_assigned_branch(): void
    {
        [$first, $second] = $this->makeInventory();
        $user = $this->makeUser('branch_manager', $first);

        $this->actingAs($user)
            ->getJson('/api/inventory')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.branch_id', (string) $first)
            ->assertJsonPath('summary.inventory_rows', 1);

        $this->getJson('/api/inventory?branch_id='.$second)->assertForbidden();
        $this->getJson('/api/inventory?branch_id=9223372036854775808')->assertUnprocessable();
        $this->getJson('/api/inventory?branch_id=01')->assertUnprocessable();
    }

    public function test_owner_sees_branches_in_same_chain_only(): void
    {
        [$first, $second, $third] = $this->makeInventory();
        $user = $this->makeUser('chain_owner', $first);

        $this->actingAs($user)
            ->getJson('/api/inventory')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('summary.branches_with_stock', 2);

        $this->getJson('/api/inventory?branch_id='.$third)->assertForbidden();
        $this->getJson('/api/inventory?branch_id='.$second)->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_user_without_assignment_cannot_read_inventory(): void
    {
        $this->makeInventory();
        $user = User::create([
            'username' => 'khongquyen',
            'password_hash' => Hash::make('matkhau'),
            'is_active' => true,
        ]);

        $this->actingAs($user)->getJson('/api/inventory')->assertForbidden();
        $this->getJson('/api/me')->assertForbidden();
    }

    public function test_locked_account_and_revoked_assignment_lose_access_during_session(): void
    {
        [$branch] = $this->makeInventory();
        $user = $this->makeUser('branch_manager', $branch);

        $this->actingAs($user)->getJson('/api/me')->assertOk();
        DB::table('users')->where('id', $user->id)->update(['is_active' => false]);
        $user->refresh();
        $this->getJson('/api/me')->assertForbidden();
        $this->getJson('/api/inventory')->assertForbidden();

        DB::table('users')->where('id', $user->id)->update(['is_active' => true]);
        $user->refresh();
        DB::table('user_role_assignments')->where('user_id', $user->id)->update(['status' => 'revoked']);
        $this->getJson('/api/me')->assertForbidden();
        $this->getJson('/api/inventory')->assertForbidden();
    }

    public function test_zero_quantity_is_not_counted_as_stock_or_expiring(): void
    {
        [$first] = $this->makeInventory();
        DB::table('inventories')->update(['quantity' => 0]);
        $user = $this->makeUser('branch_manager', $first);

        $this->actingAs($user)
            ->getJson('/api/inventory')
            ->assertOk()
            ->assertJsonPath('summary.inventory_rows', 1)
            ->assertJsonPath('summary.expiring_lots', 0)
            ->assertJsonPath('summary.branches_with_stock', 0);
    }

    public function test_expiry_window_uses_product_setting_and_defaults_to_thirty_days(): void
    {
        [$branch] = $this->makeInventory();
        $user = $this->makeUser('branch_manager', $branch);
        $this->actingAs($user)->getJson('/api/inventory')->assertOk()
            ->assertJsonPath('summary.expiring_lots', 1)
            ->assertJsonPath('data.0.status', 'Gần hết hạn');
        DB::table('products')->where('code', 'VT01')->update(['expiry_warning_days' => 5]);
        $this->getJson('/api/inventory')->assertOk()
            ->assertJsonPath('summary.expiring_lots', 0)
            ->assertJsonPath('data.0.status', 'Bình thường');
        DB::table('products')->where('code', 'VT01')->update(['expiry_warning_days' => 12]);
        $this->getJson('/api/inventory')->assertOk()->assertJsonPath('summary.expiring_lots', 1);
    }

    public function test_organization_read_stays_within_assigned_scope(): void
    {
        [$first, $second] = $this->makeInventory();
        $manager = $this->makeUser('branch_manager', $first);

        $this->actingAs($manager)->getJson('/api/organization')
            ->assertOk()
            ->assertJsonCount(1, 'branches')
            ->assertJsonCount(1, 'warehouses')
            ->assertJsonPath('branches.0.id', (string) $first);

        $owner = $this->makeUser('chain_owner', $first);
        $this->actingAs($owner)->getJson('/api/organization')
            ->assertOk()
            ->assertJsonCount(2, 'branches')
            ->assertJsonPath('branches.1.id', (string) $second);
    }

    public function test_supplier_master_is_writable_only_by_owner_of_its_chain(): void
    {
        [$first, $second, $third] = $this->makeInventory();
        $owner = $this->makeUser('chain_owner', $first);
        $manager = $this->makeUser('branch_manager', $second);
        $staff = $this->makeUser('sales_staff', $first);
        $chainA = DB::table('branches')->where('id', $first)->value('chain_id');
        $chainB = DB::table('branches')->where('id', $third)->value('chain_id');

        $this->actingAs($owner)->postJson('/api/suppliers', ['chain_id' => (string) $chainA, 'name' => 'Nhà cung cấp A'])
            ->assertCreated();
        $this->postJson('/api/suppliers', ['chain_id' => (string) $chainB, 'name' => 'Nhà cung cấp B'])
            ->assertForbidden();
        $this->postJson('/api/suppliers', ['chain_id' => $chainA, 'name' => 'Sai kiểu ID'])
            ->assertUnprocessable()->assertJsonValidationErrors('chain_id');

        $this->actingAs($manager)->getJson('/api/suppliers')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Nhà cung cấp A');
        $this->postJson('/api/suppliers', ['chain_id' => (string) $chainA, 'name' => 'Không được'])
            ->assertForbidden();

        $this->actingAs($staff)->getJson('/api/suppliers')->assertForbidden();
    }

    public function test_purchase_receipt_requires_another_approver_and_updates_average_cost_once(): void
    {
        [$branch] = $this->makeInventory();
        $staff = $this->makeUser('sales_staff', $branch);
        $owner = $this->makeUser('chain_owner', $branch);
        $warehouse = DB::table('warehouses')->where('branch_id', $branch)->value('id');
        $product = DB::table('products')->where('code', 'VT01')->value('id');
        $chain = DB::table('branches')->where('id', $branch)->value('chain_id');
        $supplier = DB::table('suppliers')->insertGetId(['chain_id' => $chain, 'name' => 'NCC thử']);

        $draft = function (string $quantity, string $cost) use ($supplier, $warehouse, $product): array {
            return [
                'supplier_id' => (string) $supplier,
                'warehouse_id' => (string) $warehouse,
                'items' => [['product_id' => (string) $product, 'lot_no' => 'LO-MOI', 'quantity' => $quantity, 'unit_cost' => $cost]],
            ];
        };

        $this->actingAs($staff)->getJson('/api/purchase-receipts/options')
            ->assertOk()->assertJsonCount(1, 'suppliers');
        $this->postJson('/api/purchase-receipts', $draft('2', '10.00') + ['created_by' => $owner->id])
            ->assertUnprocessable()->assertJsonValidationErrors('created_by');
        $first = $this->postJson('/api/purchase-receipts', $draft('2', '10.00'))
            ->assertCreated()->json('id');
        $this->putJson('/api/purchase-receipts/'.$first, $draft('2', '10.00'))
            ->assertOk();
        $this->postJson('/api/purchase-receipts/'.$first.'/submit')->assertOk();
        $this->postJson('/api/purchase-receipts/'.$first.'/approve')->assertForbidden();

        $this->actingAs($owner)->postJson('/api/purchase-receipts/'.$first.'/approve')->assertOk();
        $this->postJson('/api/purchase-receipts/'.$first.'/approve')->assertStatus(409);
        $lot = DB::table('product_lots')->where('lot_no', 'LO-MOI')->value('id');
        $inventory = DB::table('inventories')->where('warehouse_id', $warehouse)->where('lot_id', $lot)->first();
        $this->assertEquals(2, $inventory->quantity);
        $this->assertEquals(10, $inventory->average_unit_cost);
        $this->assertSame(1, DB::table('stock_movements')->where('purchase_receipt_id', $first)->count());
        $this->assertSame(1, DB::table('outbox_events')->where('aggregate_type', 'purchase_receipt')->where('aggregate_id', $first)->count());
        $this->assertSame(1, DB::table('debts')->where('supplier_id', $supplier)->count());
        $this->assertSame(1, DB::table('debt_transactions')->where('purchase_receipt_id', $first)->count());
        $this->getJson('/api/inventory/movements')->assertOk()
            ->assertJsonPath('data.0.movement_type', 'purchase_in')
            ->assertJsonPath('data.0.purchase_receipt_id', (string) $first);

        $second = $this->actingAs($staff)->postJson('/api/purchase-receipts', $draft('3', '20.00'))
            ->assertCreated()->json('id');
        $this->postJson('/api/purchase-receipts/'.$second.'/submit')->assertOk();
        $this->actingAs($owner)->postJson('/api/purchase-receipts/'.$second.'/approve')->assertOk();
        $inventory = DB::table('inventories')->where('warehouse_id', $warehouse)->where('lot_id', $lot)->first();
        $this->assertEquals(5, $inventory->quantity);
        $this->assertEquals(16, $inventory->average_unit_cost);
        $this->assertSame(2, DB::table('stock_movements')->where('warehouse_id', $warehouse)->where('lot_id', $lot)->count());
        $this->assertSame(2, DB::table('debt_transactions')->where('debt_id', DB::table('debts')->where('supplier_id', $supplier)->value('id'))->count());
    }

    public function test_customer_master_is_scoped_to_chain_and_only_owner_can_write(): void
    {
        [$first, $second, $third] = $this->makeInventory();
        $owner = $this->makeUser('chain_owner', $first);
        $manager = $this->makeUser('branch_manager', $second);
        $staff = $this->makeUser('sales_staff', $second);
        $chainA = DB::table('branches')->where('id', $first)->value('chain_id');
        $chainB = DB::table('branches')->where('id', $third)->value('chain_id');

        $id = $this->actingAs($owner)->postJson('/api/customers', [
            'chain_id' => (string) $chainA, 'name' => 'Hộ A', 'customer_type' => 'farmer',
        ])->assertCreated()->json('data.id');
        $this->postJson('/api/customers', [
            'chain_id' => (string) $chainB, 'name' => 'Ngoài chuỗi', 'customer_type' => 'farmer',
        ])->assertForbidden();
        $this->postJson('/api/customers', [
            'chain_id' => (string) $chainA, 'name' => 'Sai loại', 'customer_type' => 'unknown',
        ])->assertUnprocessable();
        $this->patchJson('/api/customers/'.$id, ['name' => 'Hộ A mới'])->assertOk();

        $this->actingAs($manager)->getJson('/api/customers')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Hộ A mới');
        $this->patchJson('/api/customers/'.$id, ['name' => 'Không được'])->assertForbidden();
        $this->actingAs($staff)->getJson('/api/customers')
            ->assertOk()->assertJsonCount(1, 'data');
        $this->postJson('/api/customers', [
            'chain_id' => (string) $chainA, 'name' => 'Không được', 'customer_type' => 'small_dealer',
        ])->assertForbidden();
        $this->getJson('/api/customers?chain_id='.$chainB)->assertForbidden();
    }

    public function test_owner_creates_chain_and_first_branch_with_own_assignment_atomically(): void
    {
        [$first] = $this->makeInventory();
        $owner = $this->makeUser('chain_owner', $first);
        $manager = $this->makeUser('branch_manager', $first);
        $payload = ['name' => 'Chuỗi mới', 'first_branch_code' => 'N1', 'first_branch_name' => 'Chi nhánh đầu'];

        $this->actingAs($manager)->postJson('/api/organization/chains', $payload)->assertForbidden();
        $created = $this->actingAs($owner)->postJson('/api/organization/chains', $payload)->assertCreated();
        $chainId = $created->json('chain_id');
        $branchId = $created->json('branch_id');
        $this->assertSame(1, DB::table('user_role_assignments')->where('user_id', $owner->id)->where('branch_id', $branchId)->count());
        $this->assertFalse((bool) DB::table('branches')->where('id', $branchId)->value('is_active'));
        $visible = $this->getJson('/api/organization')->assertOk()->json('chains');
        $this->assertContains($chainId, array_column($visible, 'id'));

        $this->patchJson('/api/organization/branches/'.$branchId, ['is_active' => true])
            ->assertUnprocessable()->assertJsonValidationErrors('default_sales_warehouse_id');
        $warehouse = $this->postJson('/api/organization/warehouses', [
            'branch_id' => $branchId, 'code' => 'BAN', 'name' => 'Kho bán', 'warehouse_type' => 'sales',
        ])->assertCreated()->json('data.id');
        $foreignWarehouse = DB::table('warehouses')->where('branch_id', $first)->value('id');
        $this->patchJson('/api/organization/branches/'.$branchId, ['default_sales_warehouse_id' => $foreignWarehouse])
            ->assertUnprocessable()->assertJsonValidationErrors('default_sales_warehouse_id');
        $this->patchJson('/api/organization/branches/'.$branchId, [
            'default_sales_warehouse_id' => $warehouse, 'is_active' => true,
        ])->assertOk()->assertJsonPath('data.is_active', 1);
        $this->postJson('/api/organization/branches', [
            'chain_id' => $chainId, 'code' => 'N2', 'name' => 'Chi nhánh tiếp theo',
        ])->assertCreated();
    }

    public function test_receipt_rejection_and_failed_cost_approval_leave_inventory_unchanged(): void
    {
        [$branch] = $this->makeInventory();
        $staff = $this->makeUser('sales_staff', $branch);
        $manager = $this->makeUser('branch_manager', $branch);
        $owner = $this->makeUser('chain_owner', $branch);
        $warehouse = DB::table('warehouses')->where('branch_id', $branch)->value('id');
        $product = DB::table('products')->where('code', 'VT01')->value('id');
        $supplier = DB::table('suppliers')->insertGetId([
            'chain_id' => DB::table('branches')->where('id', $branch)->value('chain_id'), 'name' => 'NCC QA',
        ]);
        $draft = fn (string $lot) => [
            'supplier_id' => (string) $supplier, 'warehouse_id' => (string) $warehouse,
            'items' => [['product_id' => (string) $product, 'lot_no' => $lot, 'quantity' => '2.000', 'unit_cost' => '100.00']],
        ];

        $this->actingAs($staff)->postJson('/api/purchase-receipts', $draft('LO-MOI') + ['total_amount' => '1.00'])
            ->assertUnprocessable()->assertJsonValidationErrors('total_amount');
        $this->postJson('/api/purchase-receipts', [
            'supplier_id' => (string) $supplier, 'warehouse_id' => (string) $warehouse,
            'items' => [['product_id' => (string) $product, 'lot_no' => 'LO-MOI', 'quantity' => '-2', 'unit_cost' => '100.00']],
        ])->assertUnprocessable()->assertJsonValidationErrors('items.0.quantity');

        $rejected = $this->postJson('/api/purchase-receipts', $draft('LO-MOI'))->assertCreated()->json('id');
        $this->postJson('/api/purchase-receipts/'.$rejected.'/submit')->assertOk();
        $this->actingAs($manager)->postJson('/api/purchase-receipts/'.$rejected.'/reject', ['reason' => 'Sai hóa đơn'])
            ->assertOk();
        $this->actingAs($owner)->postJson('/api/purchase-receipts/'.$rejected.'/approve')->assertStatus(409);
        $this->assertSame(0, DB::table('stock_movements')->count());
        $this->assertSame('Sai hóa đơn', DB::table('purchase_receipts')->where('id', $rejected)->value('rejection_reason'));

        $existing = $this->actingAs($staff)->postJson('/api/purchase-receipts', $draft('LO01'))->assertCreated()->json('id');
        $this->postJson('/api/purchase-receipts/'.$existing.'/submit')->assertOk();
        $this->actingAs($owner)->postJson('/api/purchase-receipts/'.$existing.'/approve')->assertUnprocessable();
        $this->assertSame('submitted', DB::table('purchase_receipts')->where('id', $existing)->value('status'));
        $this->assertSame(0, DB::table('stock_movements')->count());
        $this->assertEquals(10, DB::table('inventories')->where('warehouse_id', $warehouse)->first()->quantity);
    }

    public function test_owner_manages_users_without_removing_the_last_active_owner(): void
    {
        [$first, $second, $third] = $this->makeInventory();
        $owner = $this->makeUser('chain_owner', $first);
        $manager = $this->makeUser('branch_manager', $second);
        $this->makeUser('sales_staff', $third);
        $this->actingAs($manager)->getJson('/api/users')->assertForbidden();

        $this->actingAs($owner)->patchJson('/api/users/'.$owner->id.'/active', ['is_active' => false])
            ->assertUnprocessable();
        $users = $this->getJson('/api/users')->assertOk()->assertJsonCount(2, 'data')->json('data');
        $listedOwner = collect($users)->firstWhere('id', $owner->id);
        $this->assertFalse($listedOwner['can_toggle_active']);
        $this->assertFalse($listedOwner['assignments'][0]['can_revoke']);
        $newId = $this->postJson('/api/users', [
            'username' => 'nguoi_moi', 'password' => 'mat_khau_tam_123',
            'branch_id' => (string) $first, 'role_code' => 'sales_staff', 'is_catalog_admin' => true,
        ])->assertUnprocessable()->json('id');
        $this->assertNull($newId);
        $newId = $this->postJson('/api/users', [
            'username' => 'nguoi_moi', 'password' => 'mat_khau_tam_123',
            'branch_id' => (string) $first, 'role_code' => 'sales_staff',
        ])->assertCreated()->json('id');
        $this->assertFalse((bool) DB::table('users')->where('id', $newId)->value('is_catalog_admin'));

        $firstGrant = $this->postJson('/api/users/'.$manager->id.'/assignments', [
            'branch_id' => (string) $second, 'role_code' => 'chain_owner',
        ])->assertOk()->json('id');
        $secondGrant = $this->postJson('/api/users/'.$manager->id.'/assignments', [
            'branch_id' => (string) $second, 'role_code' => 'chain_owner',
        ])->assertOk()->json('id');
        $this->assertSame($firstGrant, $secondGrant);
        $this->getJson('/api/users?search=nguoi_moi')->assertOk()->assertJsonCount(1, 'data');
        $this->patchJson('/api/users/'.$owner->id.'/active', ['is_active' => false])->assertOk();
        $this->actingAs($manager)->postJson('/api/assignments/'.$firstGrant.'/revoke')->assertUnprocessable();
        $this->patchJson('/api/users/'.$owner->id.'/active', ['is_active' => true])->assertOk();
        $this->postJson('/api/assignments/'.$firstGrant.'/revoke')->assertOk();

        $otherChain = DB::table('branches')->where('id', $third)->value('chain_id');
        $this->assertNotNull($otherChain);
        $otherRole = DB::table('roles')->where('code', 'branch_manager')->value('id');
        DB::table('user_role_assignments')->insert([
            'user_id' => $manager->id, 'role_id' => $otherRole, 'branch_id' => $third,
            'starts_on' => now()->toDateString(), 'status' => 'active',
        ]);
        $this->actingAs($owner)->patchJson('/api/users/'.$manager->id.'/active', ['is_active' => false])->assertForbidden();
    }

    public function test_sale_confirmation_snapshots_tax_and_cost_and_never_decrements_twice(): void
    {
        [$branch, , $foreignBranch] = $this->makeInventory();
        $staff = $this->makeUser('sales_staff', $branch);
        $warehouse = (string) DB::table('warehouses')->where('branch_id', $branch)->value('id');
        $foreignWarehouse = (string) DB::table('warehouses')->where('branch_id', $foreignBranch)->value('id');
        $lot = (string) DB::table('product_lots')->where('lot_no', 'LO01')->value('id');
        DB::table('products')->where('code', 'VT01')->update(['sale_price' => '125000.00', 'tax_rate' => '8.00']);
        DB::table('inventories')->where('warehouse_id', $warehouse)->update(['average_unit_cost' => '50000.000000']);
        $body = [
            'branch_id' => (string) $branch, 'warehouse_id' => $warehouse,
            'items' => [['lot_id' => $lot, 'quantity' => '2', 'discount_amount' => '10000.00']],
        ];

        $this->actingAs($staff)->getJson('/api/sales-orders/options')->assertOk()->assertJsonPath('stock.0.lot_id', $lot);
        $this->postJson('/api/sales-orders', $body + ['total_amount' => '1'])->assertUnprocessable();
        $this->postJson('/api/sales-orders', array_replace($body, ['warehouse_id' => $foreignWarehouse]))
            ->assertUnprocessable();
        $this->postJson('/api/sales-orders', array_replace($body, ['branch_id' => $branch]))
            ->assertUnprocessable();
        $orderId = $this->postJson('/api/sales-orders', $body)->assertCreated()->json('id');
        $this->assertIsString($orderId);
        $this->postJson('/api/sales-orders/'.$orderId.'/confirm', ['amount' => '0'])->assertUnprocessable();
        $this->postJson('/api/sales-orders/'.$orderId.'/confirm', ['amount' => '259200.00', 'method' => 'cash'])->assertOk();
        $this->postJson('/api/sales-orders/'.$orderId.'/confirm', ['amount' => '259200.00', 'method' => 'cash'])->assertStatus(409);
        $order = DB::table('sales_orders')->find($orderId);
        $invoice = DB::table('invoices')->where('sales_order_id', $orderId)->first();
        $item = DB::table('sales_order_items')->where('order_id', $orderId)->first();
        $this->assertEquals(259200, $order->total_amount);
        $this->assertEquals(19200, $invoice->tax_amount);
        $this->assertEquals(100000, $item->cost_total);
        $this->assertEquals(8, $item->tax_rate_snapshot);
        $this->assertEquals(8, DB::table('inventories')->where('warehouse_id', $warehouse)->value('quantity'));
        $this->assertSame(1, DB::table('stock_movements')->where('sales_order_id', $orderId)->count());
        $this->assertSame(1, DB::table('outbox_events')->where('aggregate_type', 'sales_order')->where('aggregate_id', $orderId)->count());
        $this->assertSame(1, DB::table('payments')->where('invoice_id', $invoice->id)->count());
        $this->assertSame(0, DB::table('debts')->count());
        $this->getJson('/api/inventory/movements')->assertOk()
            ->assertJsonPath('data.0.movement_type', 'sale_out')
            ->assertJsonPath('data.0.sales_order_id', $orderId);
        $this->getJson('/api/sales-orders/'.$orderId)->assertOk()->assertJsonPath('data.id', $orderId);
        $outsider = $this->makeUser('branch_manager', $foreignBranch);
        $this->actingAs($outsider)->getJson('/api/sales-orders/'.$orderId)->assertNotFound();
        $this->postJson('/api/sales-orders/'.$orderId.'/confirm')->assertForbidden();
        $this->actingAs($staff);

        $second = $this->postJson('/api/sales-orders', array_replace($body, [
            'items' => [['lot_id' => $lot, 'quantity' => '9', 'discount_amount' => '0']],
        ]))->assertCreated()->json('id');
        $this->postJson('/api/sales-orders/'.$second.'/confirm', ['amount' => '0'])->assertUnprocessable();
        $this->assertSame(1, DB::table('invoices')->count());
        $this->assertEquals(8, DB::table('inventories')->where('warehouse_id', $warehouse)->value('quantity'));
        $third = $this->postJson('/api/sales-orders', $body)->assertCreated()->json('id');
        DB::table('products')->where('code', 'VT01')->update(['tax_rate' => '5.00']);
        $this->postJson('/api/sales-orders/'.$third.'/confirm', ['amount' => '0'])->assertUnprocessable();
        $this->assertSame(1, DB::table('invoices')->count());
        $this->assertSame(1, DB::table('stock_movements')->where('sales_order_id', $orderId)->count());
    }

    public function test_sales_report_uses_confirmed_snapshots_payments_local_day_and_branch_scope(): void
    {
        [$first, $second, $foreign] = $this->makeInventory();
        $owner = $this->makeUser('chain_owner', $first);
        $lot = DB::table('product_lots')->value('id');
        $soldAt = '2026-09-26 17:30:00';
        foreach ([[$first, '189.00', '9.00', '120.00', '100.00'], [$second, '50.00', '0.00', '20.00', null], [$foreign, '999.00', '0.00', '100.00', null]] as $index => [$branch, $total, $tax, $cost, $paid]) {
            $warehouse = DB::table('warehouses')->where('branch_id', $branch)->value('id');
            $orderId = DB::table('sales_orders')->insertGetId([
                'branch_id' => $branch, 'warehouse_id' => $warehouse, 'created_by' => $owner->id,
                'order_no' => 'REPORT-'.$index, 'status' => 'confirmed', 'total_amount' => $total, 'sold_at' => $soldAt,
            ]);
            DB::table('sales_order_items')->insert([
                'order_id' => $orderId, 'lot_id' => $lot,
                'quantity' => $index === 0 ? '2.000' : '1.000',
                'unit_price' => $index === 0 ? '100.00' : $total,
                'discount_amount' => $index === 0 ? '20.00' : '0.00',
                'line_total' => $index === 0 ? '180.00' : $total,
                'tax_rate_snapshot' => $index === 0 ? '5.00' : '0.00',
                'tax_amount' => $tax, 'unit_cost_snapshot' => $index === 0 ? '60.000000' : $cost,
                'cost_total' => $cost,
            ]);
            $invoiceId = DB::table('invoices')->insertGetId([
                'sales_order_id' => $orderId, 'invoice_no' => 'REPORT-INV-'.$index,
                'subtotal' => $index === 0 ? '200.00' : $total,
                'discount_amount' => $index === 0 ? '20.00' : '0.00',
                'tax_amount' => $tax, 'total_amount' => $total, 'status' => 'issued',
            ]);
            if ($paid !== null) {
                DB::table('payments')->insert([
                    'invoice_id' => $invoiceId, 'method' => 'cash', 'amount' => $paid, 'status' => 'completed',
                ]);
                DB::table('payments')->insert([
                    'invoice_id' => $invoiceId, 'method' => 'cash', 'amount' => '40.00', 'status' => 'pending',
                ]);
            }
        }
        $url = '/api/reports/sales?period=day&date=2026-09-27';
        $this->actingAs($owner)->getJson($url)->assertOk()
            ->assertJsonPath('timezone', 'Asia/Ho_Chi_Minh')
            ->assertJsonPath('summary.invoice_count', 2)
            ->assertJsonPath('summary.gross_sales', '250.00')
            ->assertJsonPath('summary.total_discount', '20.00')
            ->assertJsonPath('summary.net_sales', '230.00')
            ->assertJsonPath('summary.total_tax', '9.00')
            ->assertJsonPath('summary.invoice_total', '239.00')
            ->assertJsonPath('summary.cogs', '140.00')
            ->assertJsonPath('summary.gross_profit', '90.00')
            ->assertJsonPath('summary.amount_collected', '100.00')
            ->assertJsonPath('summary.receivable_remaining', '139.00')
            ->assertJsonCount(2, 'by_branch');
        $this->getJson($url.'&branch_id='.$first)->assertOk()->assertJsonPath('summary.invoice_total', '189.00');
        $this->getJson($url.'&branch_id='.$foreign)->assertForbidden();
        $this->getJson($url.'&branch_id=9223372036854775808')->assertUnprocessable();
        $this->getJson('/api/reports/sales?period=day&date=2026-09-26')->assertJsonPath('summary.invoice_count', 0);
        $this->getJson('/api/reports/sales?period=month&date=2026-09-01')->assertJsonPath('summary.invoice_count', 2);
        $staff = $this->makeUser('sales_staff', $first);
        $this->actingAs($staff)->getJson('/api/me')->assertJsonPath('user.can_view_reports', false);
        $this->getJson($url)->assertForbidden();
        $manager = $this->makeUser('branch_manager', $first);
        $this->actingAs($manager)->getJson('/api/me')->assertJsonPath('user.can_view_reports', true);
        $this->getJson($url)->assertOk()->assertJsonPath('summary.invoice_count', 1);
        $this->getJson($url.'&branch_id='.$second)->assertForbidden();
        $this->actingAs($owner);
        $firstOrder = DB::table('sales_orders')->where('branch_id', $first)->value('id');
        DB::table('sales_order_items')->where('order_id', $firstOrder)->update(['cost_total' => '999.00']);
        $this->getJson($url)->assertJsonPath('summary.cogs', '140.00')
            ->assertJsonPath('summary.gross_profit', '90.00');
        DB::table('sales_order_items')->where('order_id', $firstOrder)->update(['unit_cost_snapshot' => null, 'cost_total' => null]);
        $this->getJson($url)->assertJsonPath('summary.incomplete_cost_count', 1)
            ->assertJsonPath('summary.cogs', null)->assertJsonPath('summary.gross_profit', null);
        DB::table('sales_order_items')->where('order_id', $firstOrder)->update(['tax_rate_snapshot' => null, 'tax_amount' => null]);
        $this->getJson($url)->assertJsonPath('summary.incomplete_tax_count', 1)
            ->assertJsonPath('summary.total_tax', null)->assertJsonPath('summary.invoice_total', null)
            ->assertJsonPath('summary.receivable_remaining', null);
        $ownerRole = DB::table('user_role_assignments')->where('user_id', $owner->id)->value('role_id');
        DB::table('user_role_assignments')->insert([
            'user_id' => $owner->id, 'role_id' => $ownerRole, 'branch_id' => $foreign,
            'starts_on' => now()->subDay()->toDateString(), 'status' => 'active',
        ]);
        $firstChain = (string) DB::table('branches')->where('id', $first)->value('chain_id');
        $foreignChain = (string) DB::table('branches')->where('id', $foreign)->value('chain_id');
        $this->getJson('/api/me')->assertJsonCount(2, 'report_chains');
        $this->getJson($url)->assertUnprocessable()->assertJsonValidationErrors('chain_id');
        $this->getJson($url.'&chain_id='.$firstChain)->assertOk()->assertJsonPath('summary.invoice_count', 2);
        $this->getJson($url.'&chain_id='.$foreignChain)->assertOk()->assertJsonPath('summary.invoice_count', 1)
            ->assertJsonPath('summary.gross_sales', '999.00');
        $this->getJson($url.'&chain_id='.$firstChain.'&branch_id='.$foreign)->assertForbidden();
    }

    public function test_customer_debt_accepts_partial_payments_without_overpayment_and_checks_source_branch(): void
    {
        [$branch, $otherBranch, $foreignBranch] = $this->makeInventory();
        $seller = $this->makeUser('sales_staff', $branch);
        $otherStaff = $this->makeUser('sales_staff', $otherBranch);
        $foreignOwner = $this->makeUser('chain_owner', $foreignBranch);
        $warehouse = (string) DB::table('warehouses')->where('branch_id', $branch)->value('id');
        $lot = (string) DB::table('product_lots')->where('lot_no', 'LO01')->value('id');
        $chain = DB::table('branches')->where('id', $branch)->value('chain_id');
        $customer = DB::table('customers')->insertGetId(['chain_id' => $chain, 'name' => 'Hộ trả sau', 'customer_type' => 'farmer']);
        DB::table('products')->where('code', 'VT01')->update(['sale_price' => '100.00', 'tax_rate' => '0.00']);
        DB::table('inventories')->where('warehouse_id', $warehouse)->update(['average_unit_cost' => '50.000000']);
        $this->actingAs($seller);
        $orderId = $this->postJson('/api/sales-orders', [
            'branch_id' => (string) $branch, 'warehouse_id' => $warehouse, 'customer_id' => (string) $customer,
            'season_label' => 'Vụ Đông Xuân',
            'items' => [['lot_id' => $lot, 'quantity' => '2', 'discount_amount' => '0']],
        ])->assertCreated()->json('id');
        $this->postJson('/api/sales-orders/'.$orderId.'/confirm', ['amount' => '50.00', 'method' => 'cash'])->assertOk();
        $invoice = DB::table('invoices')->where('sales_order_id', $orderId)->first();
        $this->assertSame('issued', $invoice->status);
        $charge = $this->getJson('/api/debts')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.remaining_amount', '150.00')
            ->assertJsonPath('data.0.season_label', 'Vụ Đông Xuân')->json('data.0.id');
        $this->actingAs($otherStaff)->getJson('/api/debts')->assertOk()->assertJsonCount(0, 'data');
        $this->postJson('/api/debts/'.$charge.'/payments', [
            'amount' => '10.00', 'method' => 'cash', 'request_key' => 'other-branch-01',
        ])->assertForbidden();
        $this->actingAs($foreignOwner)->postJson('/api/debts/'.$charge.'/payments', [
            'amount' => '10.00', 'method' => 'cash', 'request_key' => 'foreign-chain-01',
        ])->assertForbidden();
        $this->actingAs($seller)->postJson('/api/debts/'.$charge.'/payments', [
            'amount' => '151.00', 'method' => 'cash', 'request_key' => 'over-payment-01',
        ])->assertUnprocessable();
        $first = ['amount' => '100.00', 'method' => 'bank_transfer', 'request_key' => 'debt-payment-01'];
        $this->postJson('/api/debts/'.$charge.'/payments', $first)->assertOk()->assertJsonPath('remaining_amount', '50.00');
        $this->postJson('/api/debts/'.$charge.'/payments', $first)->assertOk()->assertJsonPath('replayed', true);
        $this->postJson('/api/debts/'.$charge.'/payments', [
            'amount' => '50.00', 'method' => 'cash', 'request_key' => 'debt-payment-01',
        ])->assertStatus(409);
        $this->postJson('/api/debts/'.$charge.'/payments', [
            'amount' => '50.00', 'method' => 'cash', 'request_key' => 'debt-payment-02',
        ])->assertOk()->assertJsonPath('remaining_amount', '0.00');
        $this->assertSame('paid', DB::table('invoices')->where('id', $invoice->id)->value('status'));
        $this->assertSame('closed', DB::table('debts')->where('customer_id', $customer)->value('status'));
        $this->assertSame(3, DB::table('payments')->where('invoice_id', $invoice->id)->count());
        $this->assertSame(2, DB::table('outbox_events')->where('event_type', 'debt.payment_recorded')->count());
        $this->getJson('/api/debts?status=paid')->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_customer_ledger_spans_chain_but_each_branch_can_pay_only_its_source(): void
    {
        [$firstBranch, $secondBranch] = $this->makeInventory();
        $firstStaff = $this->makeUser('sales_staff', $firstBranch);
        $secondStaff = $this->makeUser('sales_staff', $secondBranch);
        $owner = $this->makeUser('chain_owner', $firstBranch);
        $chain = DB::table('branches')->where('id', $firstBranch)->value('chain_id');
        $customer = DB::table('customers')->insertGetId(['chain_id' => $chain, 'name' => 'Hộ hai chi nhánh', 'customer_type' => 'farmer']);
        $lot = (string) DB::table('product_lots')->where('lot_no', 'LO01')->value('id');
        DB::table('products')->where('code', 'VT01')->update(['sale_price' => '100.00', 'tax_rate' => '0.00']);
        DB::table('inventories')->update(['average_unit_cost' => '50.000000']);
        $charges = [];
        foreach ([[$firstBranch, $firstStaff], [$secondBranch, $secondStaff]] as [$branch, $seller]) {
            $warehouse = (string) DB::table('warehouses')->where('branch_id', $branch)->value('id');
            $this->actingAs($seller);
            $order = $this->postJson('/api/sales-orders', [
                'branch_id' => (string) $branch, 'warehouse_id' => $warehouse, 'customer_id' => (string) $customer,
                'items' => [['lot_id' => $lot, 'quantity' => '1', 'discount_amount' => '0']],
            ])->assertCreated()->json('id');
            $this->postJson('/api/sales-orders/'.$order.'/confirm', ['amount' => '0'])->assertOk();
            $charges[] = DB::table('debt_transactions')->where('invoice_id', DB::table('invoices')->where('sales_order_id', $order)->value('id'))
                ->where('transaction_type', 'sale_charge')->value('id');
        }
        $this->assertSame(1, DB::table('debts')->where('customer_id', $customer)->count());
        $this->actingAs($firstStaff)->getJson('/api/debts')->assertOk()->assertJsonCount(1, 'data');
        $this->postJson('/api/debts/'.$charges[1].'/payments', [
            'amount' => '10.00', 'method' => 'cash', 'request_key' => 'cross-branch-01',
        ])->assertForbidden();
        $this->actingAs($secondStaff)->getJson('/api/debts')->assertOk()->assertJsonCount(1, 'data');
        $this->actingAs($owner)->getJson('/api/debts')->assertOk()->assertJsonCount(2, 'data');
        $this->postJson('/api/debts/'.$charges[1].'/payments', [
            'amount' => '100.00', 'method' => 'cash', 'request_key' => 'owner-second-01',
        ])->assertOk();
        $this->assertSame('open', DB::table('debts')->where('customer_id', $customer)->value('status'));
        $this->postJson('/api/debts/'.$charges[0].'/payments', [
            'amount' => '100.00', 'method' => 'cash', 'request_key' => 'owner-first-01',
        ])->assertOk();
        $this->assertSame('closed', DB::table('debts')->where('customer_id', $customer)->value('status'));
    }

    public function test_failed_outbox_events_are_scoped_to_chain_owner_and_retry_is_explicit(): void
    {
        [$branch, , $foreignBranch] = $this->makeInventory();
        $owner = $this->makeUser('chain_owner', $branch);
        $foreignOwner = $this->makeUser('chain_owner', $foreignBranch);
        $staff = $this->makeUser('sales_staff', $branch);
        $eventId = DB::table('outbox_events')->insertGetId([
            'aggregate_type' => 'sales_order', 'aggregate_id' => 1,
            'event_type' => 'sale.confirmed', 'event_version' => 1,
            'payload' => json_encode(['branch_id' => (string) $branch, 'actor_id' => (string) $staff->id], JSON_THROW_ON_ERROR),
            'status' => 'failed', 'attempt_count' => 5, 'last_error' => 'Mongo không sẵn sàng',
        ]);
        $this->actingAs($staff)->getJson('/api/outbox')->assertForbidden();
        $this->actingAs($foreignOwner)->getJson('/api/outbox')->assertOk()->assertJsonCount(0, 'data');
        $this->postJson('/api/outbox/'.$eventId.'/retry')->assertForbidden();
        $foreignEvents = array_fill(0, 501, [
            'aggregate_type' => 'sales_order', 'aggregate_id' => 2,
            'event_type' => 'sale.confirmed', 'event_version' => 1,
            'payload' => json_encode(['branch_id' => (string) $foreignBranch], JSON_THROW_ON_ERROR),
            'status' => 'failed', 'attempt_count' => 5,
        ]);
        foreach (array_chunk($foreignEvents, 100) as $chunk) DB::table('outbox_events')->insert($chunk);
        $this->actingAs($owner)->getJson('/api/outbox')->assertOk()
            ->assertJsonCount(1, 'data')->assertJsonPath('data.0.id', (string) $eventId);
        $this->postJson('/api/outbox/'.$eventId.'/retry')->assertOk()->assertJsonPath('status', 'retry');
        $this->assertSame(0, DB::table('outbox_events')->where('id', $eventId)->value('attempt_count'));
        $this->postJson('/api/outbox/'.$eventId.'/retry')->assertStatus(409);
    }

    public function test_login_uses_username_and_active_state(): void
    {
        User::create([
            'username' => 'quanly',
            'password_hash' => Hash::make('matkhau'),
            'is_active' => true,
        ]);
        User::create([
            'username' => 'dakhoa',
            'password_hash' => Hash::make('matkhau'),
            'is_active' => false,
        ]);

        $this->postJson('/login', ['username' => 'quanly', 'password' => 'matkhau'])
            ->assertOk()
            ->assertJsonPath('user.username', 'quanly');
        $this->postJson('/logout')->assertOk();
        $this->postJson('/login', ['username' => 'dakhoa', 'password' => 'matkhau'])
            ->assertUnprocessable();
    }

    public function test_transfer_request_validates_scope_lot_and_quantity_without_changing_stock(): void
    {
        [$first, $second, $foreign] = $this->makeInventory();
        $source = DB::table('warehouses')->where('branch_id', $first)->value('id');
        $target = DB::table('warehouses')->where('branch_id', $second)->value('id');
        $foreignWarehouse = DB::table('warehouses')->where('branch_id', $foreign)->value('id');
        $lot = DB::table('product_lots')->value('id');
        $user = $this->makeUser('sales_staff', $first);
        $this->actingAs($user);

        $body = [
            'from_warehouse_id' => (string) $source,
            'to_warehouse_id' => (string) $target,
            'items' => [['lot_id' => (string) $lot, 'requested_quantity' => '2.500']],
        ];
        $this->getJson('/api/stock-transfers/options')->assertOk()
            ->assertJsonCount(1, 'sources')->assertJsonCount(2, 'destinations');
        $id = $this->postJson('/api/stock-transfers', $body)->assertCreated()->json('id');
        $this->assertSame(1, DB::table('stock_transfers')->count());
        $this->assertEquals(2.5, DB::table('stock_transfer_items')->where('transfer_id', $id)->value('requested_quantity'));
        $this->assertEquals(10, DB::table('inventories')->where('warehouse_id', $source)->value('quantity'));
        $this->assertSame(0, DB::table('stock_movements')->count());
        $this->getJson('/api/stock-transfers/'.$id)->assertOk()
            ->assertJsonPath('data.status', 'requested')->assertJsonPath('items.0.lot_id', (string) $lot);
        $this->getJson('/api/stock-transfers')->assertOk()->assertJsonCount(1, 'data');

        $this->postJson('/api/stock-transfers', array_replace($body, ['to_warehouse_id' => (string) $source]))->assertUnprocessable();
        $this->postJson('/api/stock-transfers', array_replace($body, ['to_warehouse_id' => (string) $foreignWarehouse]))->assertUnprocessable();
        $this->postJson('/api/stock-transfers', array_replace($body, ['from_warehouse_id' => (string) $target, 'to_warehouse_id' => (string) $source]))->assertForbidden();
        $this->postJson('/api/stock-transfers', array_replace($body, ['items' => [['lot_id' => (string) $lot, 'requested_quantity' => '11']]]))->assertUnprocessable();
        $this->postJson('/api/stock-transfers', array_replace($body, ['items' => [$body['items'][0], $body['items'][0]]]))->assertUnprocessable();
        $this->postJson('/api/stock-transfers', array_replace($body, ['requested_by' => (string) $user->id]))->assertUnprocessable();
        $this->assertSame(1, DB::table('stock_transfers')->count());
    }

    public function test_transfer_approval_dispatch_and_short_receipt_apply_stock_once(): void
    {
        [$first, $second] = $this->makeInventory();
        $source = DB::table('warehouses')->where('branch_id', $first)->value('id');
        $target = DB::table('warehouses')->where('branch_id', $second)->value('id');
        $lot = DB::table('product_lots')->value('id');
        DB::table('inventories')->where('warehouse_id', $source)->update(['average_unit_cost' => '100']);
        DB::table('inventories')->where('warehouse_id', $target)->update(['average_unit_cost' => '200']);
        $requester = $this->makeUser('sales_staff', $first);
        $manager = $this->makeUser('branch_manager', $first);
        $receiver = $this->makeUser('sales_staff', $second);
        $this->actingAs($requester);
        $id = $this->postJson('/api/stock-transfers', [
            'from_warehouse_id' => (string) $source, 'to_warehouse_id' => (string) $target,
            'items' => [['lot_id' => (string) $lot, 'requested_quantity' => '2']],
        ])->assertCreated()->json('id');
        $this->postJson('/api/stock-transfers/'.$id.'/approve')->assertForbidden();
        $this->actingAs($receiver)->postJson('/api/stock-transfers/'.$id.'/approve')->assertForbidden();
        $this->actingAs($manager)->postJson('/api/stock-transfers/'.$id.'/approve')->assertOk()->assertJsonPath('status', 'approved');
        $this->postJson('/api/stock-transfers/'.$id.'/approve')->assertStatus(409);
        $this->actingAs($receiver)->postJson('/api/stock-transfers/'.$id.'/dispatch', [
            'items' => [['lot_id' => (string) $lot, 'dispatched_quantity' => '2']],
        ])->assertForbidden();
        $this->actingAs($requester)->postJson('/api/stock-transfers/'.$id.'/dispatch', [
            'items' => [['lot_id' => (string) $lot, 'dispatched_quantity' => '2']],
        ])->assertOk()->assertJsonPath('status', 'dispatched');
        $this->assertEquals(8, DB::table('inventories')->where('warehouse_id', $source)->value('quantity'));
        $this->assertEquals(10, DB::table('inventories')->where('warehouse_id', $target)->value('quantity'));
        $this->assertEquals(100, DB::table('stock_transfer_items')->where('transfer_id', $id)->value('transfer_unit_cost'));
        $this->postJson('/api/stock-transfers/'.$id.'/dispatch', [
            'items' => [['lot_id' => (string) $lot, 'dispatched_quantity' => '2']],
        ])->assertStatus(409);
        $this->postJson('/api/stock-transfers/'.$id.'/receive', [
            'items' => [['lot_id' => (string) $lot, 'received_quantity' => '1']],
        ])->assertForbidden();
        $this->actingAs($receiver)->postJson('/api/stock-transfers/'.$id.'/receive', [
            'items' => [['lot_id' => (string) $lot, 'received_quantity' => '1']],
        ])->assertOk()->assertJsonPath('status', 'discrepancy');
        $this->assertEquals(11, DB::table('inventories')->where('warehouse_id', $target)->value('quantity'));
        $this->assertEqualsWithDelta(190.909091, (float) DB::table('inventories')->where('warehouse_id', $target)->value('average_unit_cost'), 0.000001);
        $this->assertSame(2, DB::table('stock_movements')->where('stock_transfer_id', $id)->count());
        $this->postJson('/api/stock-transfers/'.$id.'/receive', [
            'items' => [['lot_id' => (string) $lot, 'received_quantity' => '2']],
        ])->assertStatus(409);
        $this->assertEquals(11, DB::table('inventories')->where('warehouse_id', $target)->value('quantity'));
        $reconciliation = ['reason' => 'Đối chiếu biên bản giao nhận', 'items' => [[
            'lot_id' => (string) $lot, 'supplemental_received_quantity' => '0.300',
            'returned_quantity' => '0.400', 'lost_quantity' => '0.300',
        ]]];
        $this->postJson('/api/stock-transfers/'.$id.'/reconcile', $reconciliation)->assertForbidden();
        $owner = $this->makeUser('chain_owner', $first);
        $this->actingAs($owner)->postJson('/api/stock-transfers/'.$id.'/reconcile', array_replace($reconciliation, [
            'items' => [[
                'lot_id' => (string) $lot, 'supplemental_received_quantity' => '0.300',
                'returned_quantity' => '0.400', 'lost_quantity' => '0.200',
            ]],
        ]))->assertUnprocessable();
        $this->postJson('/api/stock-transfers/'.$id.'/reconcile', $reconciliation)->assertOk()->assertJsonPath('status', 'reconciled');
        $this->assertEquals(8.4, DB::table('inventories')->where('warehouse_id', $source)->value('quantity'));
        $this->assertEquals(11.3, DB::table('inventories')->where('warehouse_id', $target)->value('quantity'));
        $this->assertEquals(0.3, DB::table('stock_transfer_items')->where('transfer_id', $id)->value('lost_quantity'));
        $this->assertSame(4, DB::table('stock_movements')->where('stock_transfer_id', $id)->count());
        $this->assertEquals($owner->id, DB::table('stock_transfers')->where('id', $id)->value('reconciled_by'));
        $this->postJson('/api/stock-transfers/'.$id.'/reconcile', $reconciliation)->assertStatus(409);
        $this->assertSame(4, DB::table('stock_movements')->where('stock_transfer_id', $id)->count());
        $this->assertSame(5, DB::table('outbox_events')->where('aggregate_type', 'stock_transfer')->where('aggregate_id', $id)->count());
    }

    public function test_low_stock_aggregates_lots_per_warehouse_and_threshold_rights_are_scoped(): void
    {
        [$first, $second, $foreign] = $this->makeInventory();
        $warehouse = DB::table('warehouses')->where('branch_id', $first)->value('id');
        $foreignWarehouse = DB::table('warehouses')->where('branch_id', $foreign)->value('id');
        $product = DB::table('products')->value('id');
        $secondLot = DB::table('product_lots')->insertGetId([
            'product_id' => $product, 'lot_no' => 'LO02',
            'expires_on' => now('Asia/Ho_Chi_Minh')->addDays(100)->toDateString(),
        ]);
        DB::table('inventories')->insert(['warehouse_id' => $warehouse, 'lot_id' => $secondLot, 'quantity' => 2]);
        $staff = $this->makeUser('sales_staff', $first);
        $manager = $this->makeUser('branch_manager', $first);
        $this->actingAs($staff)->getJson('/api/inventory/alerts')->assertOk()
            ->assertJsonCount(0, 'low_stock')->assertJsonCount(1, 'expiring_lots')
            ->assertJsonPath('as_of_date', now('Asia/Ho_Chi_Minh')->toDateString());
        $this->putJson('/api/inventory/thresholds/'.$warehouse.'/'.$product, ['min_stock_quantity' => '13'])->assertForbidden();
        $this->actingAs($manager)->putJson('/api/inventory/thresholds/'.$warehouse.'/'.$product, ['min_stock_quantity' => '13'])->assertOk();
        $this->putJson('/api/inventory/thresholds/'.$foreignWarehouse.'/'.$product, ['min_stock_quantity' => '13'])->assertForbidden();
        $this->getJson('/api/inventory/alerts')->assertOk()
            ->assertJsonCount(1, 'low_stock')->assertJsonPath('low_stock.0.product_id', (string) $product)
            ->assertJsonPath('low_stock.0.quantity', 12);
        $this->putJson('/api/inventory/thresholds/'.$warehouse.'/'.$product, ['min_stock_quantity' => '12'])->assertOk();
        $this->getJson('/api/inventory/alerts')->assertOk()->assertJsonCount(0, 'low_stock');
        $this->getJson('/api/inventory/thresholds')->assertOk()->assertJsonCount(1, 'settings');
        $this->assertSame(1, DB::table('warehouse_product_settings')->count());
        $this->assertEquals(12, DB::table('warehouse_product_settings')->value('min_stock_quantity'));
    }

    public function test_alert_incident_opens_once_resolves_and_reopens_with_scoped_recipients(): void
    {
        [$first, , $foreign] = $this->makeInventory();
        $warehouse = DB::table('warehouses')->where('branch_id', $first)->value('id');
        $product = DB::table('products')->value('id');
        DB::table('products')->where('id', $product)->update(['expiry_warning_days' => 0]);
        DB::table('warehouse_product_settings')->insert([
            'warehouse_id' => $warehouse, 'product_id' => $product, 'min_stock_quantity' => 12,
        ]);
        $owner = $this->makeUser('chain_owner', $first);
        $manager = $this->makeUser('branch_manager', $first);
        $staff = $this->makeUser('sales_staff', $first);
        $other = $this->makeUser('sales_staff', $foreign);
        $scanner = app(InventoryAlertScanner::class);
        $outbox = app(OutboxService::class);

        $this->assertSame(['open' => 1, 'created' => 1, 'resolved' => 0], $scanner->run($outbox));
        $event = DB::table('outbox_events')->first();
        $recipients = json_decode($event->payload, true, 512, JSON_THROW_ON_ERROR)['recipient_user_ids'];
        sort($recipients);
        $expected = [(string) $owner->id, (string) $manager->id, (string) $staff->id];
        sort($expected);
        $this->assertSame($expected, $recipients);
        $this->assertNotContains((string) $other->id, $recipients);
        $this->assertSame(['open' => 1, 'created' => 0, 'resolved' => 0], $scanner->run($outbox));
        $this->assertSame(1, DB::table('outbox_events')->count());

        DB::table('warehouse_product_settings')->where('warehouse_id', $warehouse)->update(['min_stock_quantity' => 10]);
        $this->assertSame(['open' => 0, 'created' => 0, 'resolved' => 1], $scanner->run($outbox));
        $this->assertSame('resolved', DB::table('inventory_alert_incidents')->value('status'));
        DB::table('warehouse_product_settings')->where('warehouse_id', $warehouse)->update(['min_stock_quantity' => 12]);
        $this->assertSame(['open' => 1, 'created' => 1, 'resolved' => 0], $scanner->run($outbox));
        $this->assertSame(2, DB::table('inventory_alert_incidents')->count());
        $this->assertSame(3, DB::table('outbox_events')->count());
    }

    public function test_notifications_require_current_branch_assignment(): void
    {
        [$first] = $this->makeInventory();
        $staff = $this->makeUser('sales_staff', $first);
        $store = $this->mock(NotificationStore::class);
        $store->shouldReceive('list')->once()->with((string) $staff->id, [(string) $first], null)
            ->andReturn(['data' => [], 'unread_count' => 0]);
        $store->shouldReceive('markRead')->once()->with('1:'.$staff->id, (string) $staff->id, [(string) $first])
            ->andReturn(['id' => '1:'.$staff->id, 'status' => 'read']);
        $this->getJson('/api/notifications')->assertUnauthorized();
        $this->actingAs($staff)->getJson('/api/notifications')->assertOk()->assertJsonCount(0, 'data');
        $this->patchJson('/api/notifications/1:'.$staff->id.'/read')->assertOk()->assertJsonPath('data.status', 'read');
        DB::table('user_role_assignments')->where('user_id', $staff->id)->update(['status' => 'revoked']);
        $this->getJson('/api/notifications')->assertForbidden();
    }

    public function test_purchase_sale_payment_transfer_alert_and_report_remain_consistent(): void
    {
        [$branch, $targetBranch] = $this->makeInventory();
        $warehouse = (string) DB::table('warehouses')->where('branch_id', $branch)->value('id');
        $targetWarehouse = (string) DB::table('warehouses')->where('branch_id', $targetBranch)->value('id');
        $chain = DB::table('branches')->where('id', $branch)->value('chain_id');
        $product = DB::table('products')->value('id');
        $lot = (string) DB::table('product_lots')->value('id');
        $supplier = DB::table('suppliers')->insertGetId(['chain_id' => $chain, 'name' => 'NCC chuỗi']);
        $customer = DB::table('customers')->insertGetId(['chain_id' => $chain, 'name' => 'Hộ mua chịu', 'customer_type' => 'farmer']);
        $staff = $this->makeUser('sales_staff', $branch);
        $manager = $this->makeUser('branch_manager', $branch);
        $receiver = $this->makeUser('sales_staff', $targetBranch);
        DB::table('products')->where('id', $product)->update(['sale_price' => '100.00', 'tax_rate' => '5.00', 'expiry_warning_days' => 0]);
        DB::table('inventories')->where('warehouse_id', $warehouse)->update(['average_unit_cost' => '50.000000']);
        DB::table('inventories')->where('warehouse_id', $targetWarehouse)->update(['average_unit_cost' => '80.000000']);

        $this->actingAs($staff);
        $receipt = $this->postJson('/api/purchase-receipts', [
            'supplier_id' => (string) $supplier, 'warehouse_id' => $warehouse,
            'items' => [['product_id' => (string) $product, 'lot_no' => 'LO01', 'quantity' => '2', 'unit_cost' => '100.00']],
        ])->assertCreated()->json('id');
        $this->postJson('/api/purchase-receipts/'.$receipt.'/submit')->assertOk();
        $this->actingAs($manager)->postJson('/api/purchase-receipts/'.$receipt.'/approve')->assertOk();
        $this->assertEquals(12, DB::table('inventories')->where('warehouse_id', $warehouse)->value('quantity'));

        $this->actingAs($staff);
        $order = $this->postJson('/api/sales-orders', [
            'branch_id' => (string) $branch, 'warehouse_id' => $warehouse, 'customer_id' => (string) $customer,
            'items' => [['lot_id' => $lot, 'quantity' => '2', 'discount_amount' => '20.00']],
        ])->assertCreated()->json('id');
        $this->postJson('/api/sales-orders/'.$order.'/confirm', ['amount' => '100.00', 'method' => 'cash'])->assertOk();
        $invoice = DB::table('invoices')->where('sales_order_id', $order)->first();
        $this->assertEquals(189, $invoice->total_amount);
        $this->assertEquals(116.67, DB::table('sales_order_items')->where('order_id', $order)->value('cost_total'));
        $charge = DB::table('debt_transactions')->where('invoice_id', $invoice->id)->where('transaction_type', 'sale_charge')->value('id');
        $this->postJson('/api/debts/'.$charge.'/payments', [
            'amount' => '89.00', 'method' => 'bank_transfer', 'request_key' => 'full-flow-payment',
        ])->assertOk()->assertJsonPath('remaining_amount', '0.00');

        $transfer = $this->postJson('/api/stock-transfers', [
            'from_warehouse_id' => $warehouse, 'to_warehouse_id' => $targetWarehouse,
            'items' => [['lot_id' => $lot, 'requested_quantity' => '1']],
        ])->assertCreated()->json('id');
        $this->actingAs($manager)->postJson('/api/stock-transfers/'.$transfer.'/approve')->assertOk();
        $this->actingAs($staff)->postJson('/api/stock-transfers/'.$transfer.'/dispatch', [
            'items' => [['lot_id' => $lot, 'dispatched_quantity' => '1']],
        ])->assertOk();
        $this->actingAs($receiver)->postJson('/api/stock-transfers/'.$transfer.'/receive', [
            'items' => [['lot_id' => $lot, 'received_quantity' => '1']],
        ])->assertOk();
        $this->assertEquals(9, DB::table('inventories')->where('warehouse_id', $warehouse)->value('quantity'));
        $this->assertEquals(11, DB::table('inventories')->where('warehouse_id', $targetWarehouse)->value('quantity'));

        $this->actingAs($manager)->putJson('/api/inventory/thresholds/'.$warehouse.'/'.$product, [
            'min_stock_quantity' => '10',
        ])->assertOk();
        $alerts = app(InventoryAlertScanner::class)->run(app(OutboxService::class));
        $this->assertSame(1, $alerts['created']);
        $this->assertSame('low_stock', DB::table('inventory_alert_incidents')->value('kind'));

        $date = now('Asia/Ho_Chi_Minh')->toDateString();
        $this->getJson('/api/reports/sales?period=day&date='.$date.'&branch_id='.$branch)
            ->assertOk()->assertJsonPath('summary.invoice_count', 1)
            ->assertJsonPath('summary.gross_sales', '200.00')
            ->assertJsonPath('summary.total_discount', '20.00')
            ->assertJsonPath('summary.net_sales', '180.00')
            ->assertJsonPath('summary.total_tax', '9.00')
            ->assertJsonPath('summary.invoice_total', '189.00')
            ->assertJsonPath('summary.cogs', '116.67')
            ->assertJsonPath('summary.gross_profit', '63.33')
            ->assertJsonPath('summary.amount_collected', '189.00')
            ->assertJsonPath('summary.receivable_remaining', '0.00');
        $this->assertSame(1, DB::table('stock_movements')->where('purchase_receipt_id', $receipt)->count());
        $this->assertSame(1, DB::table('stock_movements')->where('sales_order_id', $order)->count());
        $this->assertSame(2, DB::table('stock_movements')->where('stock_transfer_id', $transfer)->count());
    }

    private function makeInventory(): array
    {
        $firstChain = DB::table('chains')->insertGetId(['name' => 'Chuỗi A']);
        $secondChain = DB::table('chains')->insertGetId(['name' => 'Chuỗi B']);
        $first = DB::table('branches')->insertGetId(['chain_id' => $firstChain, 'code' => 'A1', 'name' => 'Chi nhánh A1']);
        $second = DB::table('branches')->insertGetId(['chain_id' => $firstChain, 'code' => 'A2', 'name' => 'Chi nhánh A2']);
        $third = DB::table('branches')->insertGetId(['chain_id' => $secondChain, 'code' => 'B1', 'name' => 'Chi nhánh B1']);
        $unit = DB::table('units')->insertGetId(['name' => 'Bao']);
        $category = DB::table('product_categories')->insertGetId(['code' => 'VT', 'name' => 'Vật tư']);
        $product = DB::table('products')->insertGetId(['category_id' => $category, 'unit_id' => $unit, 'code' => 'VT01', 'name' => 'Vật tư mẫu']);
        $lot = DB::table('product_lots')->insertGetId([
            'product_id' => $product,
            'lot_no' => 'LO01',
            'expires_on' => now()->addDays(10)->toDateString(),
        ]);

        foreach ([$first, $second, $third] as $branch) {
            $warehouse = DB::table('warehouses')->insertGetId(['branch_id' => $branch, 'name' => 'Kho '.$branch]);
            DB::table('inventories')->insert([
                'warehouse_id' => $warehouse,
                'lot_id' => $lot,
                'quantity' => 10,
            ]);
        }

        return [$first, $second, $third];
    }

    private function makeUser(string $roleCode, int $branchId): User
    {
        $user = User::create([
            'username' => 'nguoidung',
            'password_hash' => Hash::make('matkhau'),
            'is_active' => true,
        ]);
        $role = DB::table('roles')->insertGetId(['code' => $roleCode, 'name' => $roleCode]);
        DB::table('user_role_assignments')->insert([
            'user_id' => $user->id,
            'role_id' => $role,
            'branch_id' => $branchId,
            'starts_on' => now()->subDay()->toDateString(),
            'status' => 'active',
        ]);

        return $user;
    }
}
