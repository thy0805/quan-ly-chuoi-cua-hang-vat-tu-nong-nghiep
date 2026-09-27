<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Response;

class SerializeBigIntIds
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);
        if ($response instanceof JsonResponse) {
            $data = json_decode($response->getContent(), true, 512, JSON_THROW_ON_ERROR);
            $response->setData($this->convert($data));
        }

        return $response;
    }

    private function convert(mixed $value, ?string $key = null): mixed
    {
        if (is_array($value)) {
            if ($key !== null && str_ends_with($key, '_ids')) {
                return array_map(fn ($id) => (string) $id, $value);
            }
            foreach ($value as $childKey => $child) $value[$childKey] = $this->convert($child, is_string($childKey) ? $childKey : null);

            return $value;
        }
        if ($value !== null && $key !== null && ($key === 'id' || str_ends_with($key, '_id') || str_ends_with($key, '_by'))) {
            return (string) $value;
        }

        return $value;
    }
}
