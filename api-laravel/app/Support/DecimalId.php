<?php

namespace App\Support;

use Illuminate\Validation\ValidationException;

class DecimalId
{
    public static function parse(mixed $value, string $field): string
    {
        if (! is_string($value) || ! preg_match('/^[1-9][0-9]{0,18}$/D', $value)
            || (strlen($value) === 19 && strcmp($value, '9223372036854775807') > 0)) {
            throw ValidationException::withMessages([$field => 'ID phải là chuỗi số nguyên dương hợp lệ trong phạm vi BIGINT.']);
        }

        return $value;
    }
}
