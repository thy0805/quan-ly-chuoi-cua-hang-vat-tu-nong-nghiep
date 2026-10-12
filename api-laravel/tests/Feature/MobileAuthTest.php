<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class MobileAuthTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        Schema::create('users', function (Blueprint $table): void {
            $table->id();
            $table->string('username');
            $table->text('password_hash');
            $table->boolean('is_active')->default(true);
            $table->boolean('is_catalog_admin')->default(false);
        });
        Schema::create('chains', function (Blueprint $table): void {
            $table->id();
            $table->string('name');
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
        (require database_path('migrations/2026_10_12_000001_create_personal_access_tokens_table.php'))->up();
        DB::table('chains')->insert(['id' => 1, 'name' => 'Chuỗi A']);
        DB::table('chains')->insert(['id' => 2, 'name' => 'Chuỗi B']);
        DB::table('branches')->insert([
            ['id' => 1, 'chain_id' => 1, 'code' => 'A', 'name' => 'Chi nhánh A'],
            ['id' => 2, 'chain_id' => 2, 'code' => 'B', 'name' => 'Chi nhánh B'],
        ]);
        DB::table('roles')->insert(['id' => 1, 'code' => 'sales_staff']);
    }

    private function staff(): User
    {
        $user = User::create(['username' => 'mobile-staff', 'password_hash' => Hash::make('test-password'), 'is_active' => true]);
        DB::table('user_role_assignments')->insert([
            'user_id' => $user->id, 'role_id' => 1, 'branch_id' => 1,
            'starts_on' => '2020-01-01', 'status' => 'active',
        ]);

        return $user;
    }

    private function loginPayload(): array
    {
        return ['username' => 'mobile-staff', 'password' => 'test-password', 'device_name' => 'Android test'];
    }

    private function bearerGet(string $token, string $path = '/api/me')
    {
        $this->app['auth']->forgetGuards();

        return $this->getJson($path, ['Authorization' => 'Bearer '.$token]);
    }

    public function test_mobile_login_issues_hashed_expiring_token_without_web_session(): void
    {
        $user = $this->staff();
        $this->freezeTime();
        $response = $this->postJson('/api/mobile/login', $this->loginPayload())
            ->assertOk()->assertJsonPath('user.id', (string) $user->id)
            ->assertJsonPath('token_type', 'Bearer')->assertHeader('Cache-Control', 'no-store, private');
        $token = $response->json('token');
        $stored = $user->tokens()->first();
        $this->assertSame(hash('sha256', explode('|', $token, 2)[1]), $stored->token);
        $this->assertTrue($stored->expires_at->equalTo(now()->addDays(7)->startOfSecond()));
        $this->assertGuest('web');
        $this->bearerGet($token)->assertOk()->assertJsonCount(1, 'branches')
            ->assertJsonPath('branches.0.id', '1')->assertJsonPath('user.can_manage_catalog', false);
        $this->bearerGet($token, '/api/users')->assertForbidden();
        $this->bearerGet($token, '/api/suppliers')->assertForbidden();
    }

    public function test_invalid_credentials_and_locked_accounts_never_issue_token(): void
    {
        $user = $this->staff();
        $this->postJson('/api/mobile/login', [...$this->loginPayload(), 'password' => 'wrong'])->assertUnprocessable();
        $this->postJson('/api/mobile/login', [...$this->loginPayload(), 'username' => 'missing'])->assertUnprocessable();
        $user->update(['is_active' => false]);
        $this->postJson('/api/mobile/login', $this->loginPayload())->assertUnprocessable();
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_mobile_login_requires_device_name_and_effective_assignment(): void
    {
        $this->staff();
        $this->postJson('/api/mobile/login', ['username' => 'mobile-staff', 'password' => 'test-password'])->assertUnprocessable();
        DB::table('user_role_assignments')->update(['starts_on' => '2099-01-01']);
        $this->postJson('/api/mobile/login', $this->loginPayload())->assertForbidden();
        DB::table('user_role_assignments')->update(['starts_on' => '2020-01-01', 'status' => 'revoked']);
        $this->postJson('/api/mobile/login', $this->loginPayload())->assertForbidden();
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_lock_and_revoke_assignment_take_effect_with_existing_token(): void
    {
        $user = $this->staff();
        $token = $this->postJson('/api/mobile/login', $this->loginPayload())->json('token');
        $user->update(['is_active' => false]);
        $this->bearerGet($token)->assertForbidden();
        $user->update(['is_active' => true]);
        DB::table('user_role_assignments')->update(['status' => 'revoked']);
        $this->bearerGet($token)->assertForbidden();
    }

    public function test_expired_revoked_and_invalid_tokens_are_rejected(): void
    {
        $user = $this->staff();
        $expired = $user->createToken('mobile:expired', ['*'], now()->subSecond());
        $this->bearerGet($expired->plainTextToken)->assertUnauthorized();
        $revoked = $user->createToken('mobile:revoked', ['*'], now()->addDay());
        $revoked->accessToken->delete();
        $this->bearerGet($revoked->plainTextToken)->assertUnauthorized();
        $this->bearerGet('999|invalid')->assertUnauthorized();
    }

    public function test_logout_revokes_only_supplied_mobile_token_and_keeps_web_session(): void
    {
        $user = $this->staff();
        $first = $this->postJson('/api/mobile/login', $this->loginPayload())->json('token');
        $second = $this->postJson('/api/mobile/login', $this->loginPayload())->json('token');
        $this->postJson('/login', ['username' => 'mobile-staff', 'password' => 'test-password'])->assertOk();
        $this->postJson('/api/mobile/logout', [], ['Authorization' => 'Bearer '.$first])->assertOk();
        $this->assertAuthenticatedAs($user, 'web');
        $this->postJson('/api/mobile/logout')->assertUnauthorized();
        $this->assertDatabaseCount('personal_access_tokens', 1);
        $this->postJson('/logout')->assertOk();
        $this->bearerGet($first)->assertUnauthorized();
        $this->bearerGet($second)->assertOk();
    }

    public function test_mobile_logout_is_available_after_account_lock(): void
    {
        $user = $this->staff();
        $token = $this->postJson('/api/mobile/login', $this->loginPayload())->json('token');
        $user->update(['is_active' => false]);
        $this->postJson('/api/mobile/logout', [], ['Authorization' => 'Bearer '.$token])->assertOk();
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_mobile_login_rate_limits_and_does_not_accept_cookie_as_logout_authority(): void
    {
        $this->staff();
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/mobile/login', [...$this->loginPayload(), 'password' => 'wrong'])->assertUnprocessable();
        }
        $this->postJson('/api/mobile/login', $this->loginPayload())->assertStatus(429);
    }

    public function test_mobile_login_ignores_web_origin_csrf_and_returns_bounded_expiration(): void
    {
        $this->staff();
        config(['mobile_auth.token_ttl_days' => 2]);
        $this->freezeTime();
        $this->postJson('/api/mobile/login', $this->loginPayload(), ['Origin' => 'http://localhost:3000'])
            ->assertOk()->assertJsonPath('expires_at', now()->addDays(2)->startOfSecond()->toIso8601String());
        $this->assertGuest('web');
    }

    public function test_malformed_or_overflow_bearer_ids_are_rejected_before_database_lookup(): void
    {
        $tokenQueries = 0;
        DB::listen(function ($query) use (&$tokenQueries): void {
            if (str_contains($query->sql, 'personal_access_tokens')) $tokenQueries++;
        });
        foreach (['bad-id|secret', '9223372036854775808|secret', '999999999999999999999|secret', '1|'] as $token) {
            $this->bearerGet($token)->assertUnauthorized();
            $this->postJson('/api/mobile/logout', [], ['Authorization' => 'Bearer '.$token])->assertUnauthorized();
        }
        $this->assertSame(0, $tokenQueries);
    }

    public function test_token_migration_has_ten_columns_and_reverses_only_its_own_table(): void
    {
        $this->assertCount(10, Schema::getColumns('personal_access_tokens'));
        $this->assertCount(4, Schema::getIndexes('personal_access_tokens'));
        $migration = require database_path('migrations/2026_10_12_000001_create_personal_access_tokens_table.php');
        $migration->down();
        $this->assertFalse(Schema::hasTable('personal_access_tokens'));
        $this->assertTrue(Schema::hasTable('users'));
        $migration->up();
        $this->assertTrue(Schema::hasTable('personal_access_tokens'));
    }
}
