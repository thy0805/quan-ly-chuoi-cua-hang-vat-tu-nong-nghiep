<?php

namespace App\Support;

use Closure;
use Illuminate\Validation\ValidationException;

class DecimalId
{
    public static function parse(mixed $value, string $field): string
    {
        if (! self::valid($value)) {
            throw ValidationException::withMessages([$field => 'ID phải là chuỗi số nguyên dương hợp lệ trong phạm vi BIGINT.']);
        }

        return $value;
    }

    public static function rule(): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail): void {
            if (! self::valid($value)) $fail('ID phải là chuỗi số nguyên dương hợp lệ trong phạm vi BIGINT.');
        };
    }

    private static function valid(mixed $value): bool
    {
        return is_string($value) && preg_match('/^[1-9][0-9]{0,18}$/D', $value)
            && (strlen($value) < 19 || strcmp($value, '9223372036854775807') <= 0);
    }
}
