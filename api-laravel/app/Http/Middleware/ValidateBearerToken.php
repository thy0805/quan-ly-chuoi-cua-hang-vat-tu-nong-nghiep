<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class ValidateBearerToken
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($token = $request->bearerToken()) {
            abort_if(strlen($token) > 1024, 401);
            if (str_contains($token, '|')) {
                [$id, $secret] = explode('|', $token, 2);
                abort_unless(ctype_digit($id) && $secret !== '' && strlen($id) <= 19
                    && (strlen($id) < 19 || strcmp($id, '9223372036854775807') <= 0), 401);
            }
        }

        return $next($request);
    }
}
