<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Support\BranchAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\PersonalAccessToken;

class MobileAuthController extends Controller
{
    public function login(Request $request, BranchAccess $access): JsonResponse
    {
        $credentials = $request->validate([
            'username' => ['required', 'string', 'max:80'],
            'password' => ['required', 'string', 'max:1024'],
            'device_name' => ['required', 'string', 'max:100'],
        ]);
        $user = User::where('username', $credentials['username'])->first();
        if (! $user || ! Hash::check($credentials['password'], $user->password_hash) || ! $user->is_active) {
            return response()->json(['message' => 'Tên đăng nhập hoặc mật khẩu không đúng.'], 422);
        }

        $expiresAt = now()->addDays(config('mobile_auth.token_ttl_days'))->startOfSecond();
        $token = DB::transaction(function () use ($user, $access, $credentials, $expiresAt) {
            $current = User::whereKey($user->id)->lockForUpdate()->firstOrFail();
            abort_unless($current->is_active, 403, 'Tài khoản không còn hoạt động.');
            abort_if($access->branchesFor($current)->isEmpty(), 403, 'Tài khoản chưa có phạm vi làm việc có hiệu lực.');

            return $current->createToken('mobile:'.$credentials['device_name'], ['*'], $expiresAt);
        });

        return response()->json([
            'token_type' => 'Bearer',
            'token' => $token->plainTextToken,
            'expires_at' => $expiresAt->toIso8601String(),
            'user' => ['id' => (string) $user->id, 'username' => $user->username],
        ])->header('Cache-Control', 'no-store, private')->header('Pragma', 'no-cache');
    }

    public function logout(Request $request): JsonResponse
    {
        $token = $request->bearerToken();
        $accessToken = $token ? PersonalAccessToken::findToken($token) : null;
        abort_unless($accessToken && $accessToken->tokenable instanceof User
            && str_starts_with($accessToken->name, 'mobile:'), 401);
        $accessToken->delete();

        return response()->json(['message' => 'Đã đăng xuất thiết bị này.'])
            ->header('Cache-Control', 'no-store, private');
    }
}
