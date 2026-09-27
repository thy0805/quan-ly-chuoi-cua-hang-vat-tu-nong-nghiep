<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\ProductContentStore;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class CatalogAccessTest extends TestCase
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
        });
        Schema::create('branches', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('chain_id');
            $table->string('code');
            $table->string('name');
        });
        Schema::create('roles', function (Blueprint $table): void {
            $table->id();
            $table->string('code');
        });
        Schema::create('user_role_assignments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id');
            $table->foreignId('role_id');
            $table->foreignId('branch_id');
            $table->date('starts_on');
            $table->string('status');
        });
        Schema::create('product_categories', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('parent_id')->nullable();
            $table->string('code');
            $table->string('name');
            $table->boolean('is_active')->default(true);
        });
        Schema::create('units', function (Blueprint $table): void {
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
            $table->string('active_ingredient')->nullable();
            $table->decimal('sale_price', 18, 2);
            $table->decimal('tax_rate', 5, 2)->nullable();
            $table->integer('expiry_warning_days')->nullable();
            $table->boolean('is_active')->default(true);
        });
    }

    public function test_catalog_requires_active_assignment_and_is_shared_across_chains(): void
    {
        $this->getJson('/api/catalog')->assertUnauthorized();

        $chainA = DB::table('chains')->insertGetId([]);
        $chainB = DB::table('chains')->insertGetId([]);
        $branchA = DB::table('branches')->insertGetId(['chain_id' => $chainA, 'code' => 'A', 'name' => 'A']);
        DB::table('branches')->insert(['chain_id' => $chainB, 'code' => 'B', 'name' => 'B']);
        $category = DB::table('product_categories')->insertGetId(['code' => 'HAT', 'name' => 'Hạt giống']);
        $unit = DB::table('units')->insertGetId(['code' => 'GOI', 'name' => 'Gói']);
        DB::table('products')->insert(['id' => '9007199254740993', 'category_id' => $category, 'unit_id' => $unit, 'code' => 'VT01', 'name' => 'Lúa giống', 'sale_price' => 125000]);

        $user = User::create(['username' => 'quanly', 'password_hash' => Hash::make('matkhau'), 'is_active' => true]);
        $this->actingAs($user)->getJson('/api/catalog')->assertForbidden();

        $role = DB::table('roles')->insertGetId(['code' => 'branch_manager']);
        DB::table('user_role_assignments')->insert([
            'user_id' => $user->id,
            'role_id' => $role,
            'branch_id' => $branchA,
            'starts_on' => now()->subDay()->toDateString(),
            'status' => 'active',
        ]);

        $this->getJson('/api/catalog?search=lúa&category_id='.$category)
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', '9007199254740993')
            ->assertJsonPath('data.0.code', 'VT01')
            ->assertJsonPath('pagination.total', 1);

        $this->getJson('/api/catalog?search=không có')->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/catalog?per_page=51')->assertUnprocessable();

        DB::table('products')->where('code', 'VT01')->update(['is_active' => false]);
        $this->getJson('/api/catalog')->assertOk()->assertJsonPath('data.0.is_active', 0);
        $this->getJson('/api/catalog?active_only=1')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_only_designated_owner_can_write_and_inactive_data_stays_visible(): void
    {
        $chain = DB::table('chains')->insertGetId([]);
        $branch = DB::table('branches')->insertGetId(['chain_id' => $chain, 'code' => 'A', 'name' => 'A']);
        $role = DB::table('roles')->insertGetId(['code' => 'chain_owner']);
        $user = User::create(['username' => 'chuchuoi', 'password_hash' => Hash::make('matkhau'), 'is_active' => true]);
        DB::table('user_role_assignments')->insert([
            'user_id' => $user->id,
            'role_id' => $role,
            'branch_id' => $branch,
            'starts_on' => now()->subDay()->toDateString(),
            'status' => 'active',
        ]);

        $this->actingAs($user)->postJson('/api/catalog/categories', ['code' => 'HAT', 'name' => 'Hạt giống'])->assertForbidden();
        DB::table('users')->where('id', $user->id)->update(['is_catalog_admin' => true]);
        $user->refresh();

        $category = $this->postJson('/api/catalog/categories', ['code' => 'HAT', 'name' => 'Hạt giống'])
            ->assertCreated()->json('data.id');
        $unit = $this->postJson('/api/catalog/units', ['code' => 'GOI', 'name' => 'Gói'])
            ->assertCreated()->json('data.id');
        $this->postJson('/api/catalog/products', [
            'code' => 'SAI-ID', 'name' => 'ID không hợp lệ', 'sale_price' => '100.00',
            'category_id' => '9223372036854775808', 'unit_id' => $unit,
        ])->assertUnprocessable()->assertJsonValidationErrors('category_id');
        $product = $this->postJson('/api/catalog/products', [
            'code' => 'VT01', 'name' => 'Lúa giống', 'sale_price' => '125000.00', 'tax_rate' => '8.00',
            'category_id' => $category, 'unit_id' => $unit,
        ])->assertCreated()->assertJsonPath('data.tax_rate', 8)->json('data.id');
        $this->patchJson('/api/catalog/products/'.$product, ['tax_rate' => '101'])->assertUnprocessable();

        $this->patchJson('/api/catalog/categories/'.$category, ['parent_id' => $category])->assertUnprocessable();
        $child = $this->postJson('/api/catalog/categories', ['code' => 'LUA', 'name' => 'Lúa', 'parent_id' => $category])
            ->assertCreated()->json('data.id');
        $this->patchJson('/api/catalog/categories/'.$category, ['parent_id' => $child])
            ->assertUnprocessable()->assertJsonValidationErrors('parent_id');
        $this->patchJson('/api/catalog/units/'.$unit, ['is_active' => false])->assertOk();
        $this->getJson('/api/catalog')->assertOk()->assertJsonPath('data.0.code', 'VT01')
            ->assertJsonPath('data.0.tax_rate', 8)
            ->assertJsonPath('units.0.is_active', 0);
        $this->getJson('/api/catalog?active_only=1')->assertOk()->assertJsonCount(0, 'data');
        $this->postJson('/api/catalog/products', [
            'code' => 'VT02', 'name' => 'Ngô giống', 'sale_price' => '90000.00',
            'category_id' => $category, 'unit_id' => $unit,
        ])->assertUnprocessable()->assertJsonValidationErrors('unit_id');

        DB::table('user_role_assignments')->where('user_id', $user->id)->update(['status' => 'revoked']);
        $this->postJson('/api/catalog/units', ['code' => 'KG', 'name' => 'Kilôgam'])->assertForbidden();
    }

    public function test_product_content_requires_assignment_and_designated_owner_for_writes(): void
    {
        $chain = DB::table('chains')->insertGetId([]);
        $branch = DB::table('branches')->insertGetId(['chain_id' => $chain, 'code' => 'A', 'name' => 'A']);
        $role = DB::table('roles')->insertGetId(['code' => 'chain_owner']);
        $category = DB::table('product_categories')->insertGetId(['code' => 'HAT', 'name' => 'Hạt giống']);
        $unit = DB::table('units')->insertGetId(['code' => 'GOI', 'name' => 'Gói']);
        DB::table('products')->insert(['id' => '9007199254740993', 'category_id' => $category, 'unit_id' => $unit, 'code' => 'VT01', 'name' => 'Lúa giống', 'sale_price' => 125000]);
        $user = User::create(['username' => 'owner', 'password_hash' => Hash::make('matkhau'), 'is_active' => true]);
        $path = '/api/catalog/products/9007199254740993/content';

        $this->actingAs($user)->getJson($path)->assertForbidden();
        DB::table('user_role_assignments')->insert([
            'user_id' => $user->id, 'role_id' => $role, 'branch_id' => $branch,
            'starts_on' => now()->subDay()->toDateString(), 'status' => 'active',
        ]);

        $store = $this->mock(ProductContentStore::class);
        $store->shouldReceive('find')->once()->with('9007199254740993')->andReturn(null);
        $store->shouldReceive('save')->once()->with('9007199254740993', [
            'usage_instructions' => 'Pha theo nhãn', 'additional_info' => null, 'images' => [],
        ])->andReturn([
            'product_id' => '9007199254740993', 'usage_instructions' => 'Pha theo nhãn',
            'additional_info' => null, 'images' => [], 'updated_at' => '2026-09-27T00:00:00+00:00',
        ]);

        $this->getJson($path)->assertOk()->assertJsonPath('data', null);
        $this->putJson($path, ['usage_instructions' => 'Pha theo nhãn', 'images' => []])->assertForbidden();
        DB::table('users')->where('id', $user->id)->update(['is_catalog_admin' => true]);
        $user->refresh();
        $this->putJson($path, ['images' => ['file:///tmp/a.jpg']])->assertUnprocessable()->assertJsonValidationErrors('images.0');
        $this->putJson($path, ['usage_instructions' => 'Pha theo nhãn', 'images' => []])
            ->assertOk()->assertJsonPath('data.product_id', '9007199254740993');
        $this->getJson('/api/catalog/products/9007199254740994/content')->assertNotFound();
    }
}
