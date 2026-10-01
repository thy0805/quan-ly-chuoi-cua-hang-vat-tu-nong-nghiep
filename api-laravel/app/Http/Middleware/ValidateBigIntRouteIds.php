<?php

namespace App\Http\Middleware;

use App\Support\DecimalId;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class ValidateBigIntRouteIds
{
    public function handle(Request $request, Closure $next): Response
    {
        foreach ($request->route()?->parameters() ?? [] as $field => $value) {
            if ($field === 'id' && $request->route()?->uri() === 'api/notifications/{id}/read') continue;
            if (in_array($field, ['id', 'warehouseId', 'productId', 'assignmentId'], true)) {
                DecimalId::parse($value, $field);
            }
        }

        return $next($request);
    }
}
