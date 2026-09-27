<?php

namespace Tests\Feature;

use App\Models\User;
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
            $table->string('transfer_no');
        });
        Schema::create('sales_orders', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('branch_id');
            $table->foreignId('warehouse_id');
            $table->foreignId('customer_id')->nullable();
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

        $this->actingAs($owner)->postJson('/api/suppliers', ['chain_id' => $chainA, 'name' => 'Nhà cung cấp A'])
            ->assertCreated();
        $this->postJson('/api/suppliers', ['chain_id' => $chainB, 'name' => 'Nhà cung cấp B'])
            ->assertForbidden();

        $this->actingAs($manager)->getJson('/api/suppliers')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Nhà cung cấp A');
        $this->postJson('/api/suppliers', ['chain_id' => $chainA, 'name' => 'Không được'])
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
                'supplier_id' => $supplier,
                'warehouse_id' => $warehouse,
                'items' => [['product_id' => $product, 'lot_no' => 'LO-MOI', 'quantity' => $quantity, 'unit_cost' => $cost]],
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
            'chain_id' => $chainA, 'name' => 'Hộ A', 'customer_type' => 'farmer',
        ])->assertCreated()->json('data.id');
        $this->postJson('/api/customers', [
            'chain_id' => $chainB, 'name' => 'Ngoài chuỗi', 'customer_type' => 'farmer',
        ])->assertForbidden();
        $this->postJson('/api/customers', [
            'chain_id' => $chainA, 'name' => 'Sai loại', 'customer_type' => 'unknown',
        ])->assertUnprocessable();
        $this->patchJson('/api/customers/'.$id, ['name' => 'Hộ A mới'])->assertOk();

        $this->actingAs($manager)->getJson('/api/customers')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.name', 'Hộ A mới');
        $this->patchJson('/api/customers/'.$id, ['name' => 'Không được'])->assertForbidden();
        $this->actingAs($staff)->getJson('/api/customers')
            ->assertOk()->assertJsonCount(1, 'data');
        $this->postJson('/api/customers', [
            'chain_id' => $chainA, 'name' => 'Không được', 'customer_type' => 'small_dealer',
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
            'supplier_id' => $supplier, 'warehouse_id' => $warehouse,
            'items' => [['product_id' => $product, 'lot_no' => $lot, 'quantity' => '2.000', 'unit_cost' => '100.00']],
        ];

        $this->actingAs($staff)->postJson('/api/purchase-receipts', $draft('LO-MOI') + ['total_amount' => '1.00'])
            ->assertUnprocessable()->assertJsonValidationErrors('total_amount');
        $this->postJson('/api/purchase-receipts', [
            'supplier_id' => $supplier, 'warehouse_id' => $warehouse,
            'items' => [['product_id' => $product, 'lot_no' => 'LO-MOI', 'quantity' => '-2', 'unit_cost' => '100.00']],
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
            'branch_id' => $first, 'role_code' => 'sales_staff', 'is_catalog_admin' => true,
        ])->assertUnprocessable()->json('id');
        $this->assertNull($newId);
        $newId = $this->postJson('/api/users', [
            'username' => 'nguoi_moi', 'password' => 'mat_khau_tam_123',
            'branch_id' => $first, 'role_code' => 'sales_staff',
        ])->assertCreated()->json('id');
        $this->assertFalse((bool) DB::table('users')->where('id', $newId)->value('is_catalog_admin'));

        $firstGrant = $this->postJson('/api/users/'.$manager->id.'/assignments', [
            'branch_id' => $second, 'role_code' => 'chain_owner',
        ])->assertOk()->json('id');
        $secondGrant = $this->postJson('/api/users/'.$manager->id.'/assignments', [
            'branch_id' => $second, 'role_code' => 'chain_owner',
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
        $this->postJson('/api/sales-orders/'.$orderId.'/confirm')->assertOk();
        $this->postJson('/api/sales-orders/'.$orderId.'/confirm')->assertStatus(409);
        $order = DB::table('sales_orders')->find($orderId);
        $invoice = DB::table('invoices')->where('sales_order_id', $orderId)->first();
        $item = DB::table('sales_order_items')->where('order_id', $orderId)->first();
        $this->assertEquals(259200, $order->total_amount);
        $this->assertEquals(19200, $invoice->tax_amount);
        $this->assertEquals(100000, $item->cost_total);
        $this->assertEquals(8, $item->tax_rate_snapshot);
        $this->assertEquals(8, DB::table('inventories')->where('warehouse_id', $warehouse)->value('quantity'));
        $this->assertSame(1, DB::table('stock_movements')->where('sales_order_id', $orderId)->count());
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
        $this->postJson('/api/sales-orders/'.$second.'/confirm')->assertUnprocessable();
        $this->assertSame(1, DB::table('invoices')->count());
        $this->assertEquals(8, DB::table('inventories')->where('warehouse_id', $warehouse)->value('quantity'));
        $third = $this->postJson('/api/sales-orders', $body)->assertCreated()->json('id');
        DB::table('products')->where('code', 'VT01')->update(['tax_rate' => '5.00']);
        $this->postJson('/api/sales-orders/'.$third.'/confirm')->assertUnprocessable();
        $this->assertSame(1, DB::table('invoices')->count());
        $this->assertSame(1, DB::table('stock_movements')->where('sales_order_id', $orderId)->count());
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
