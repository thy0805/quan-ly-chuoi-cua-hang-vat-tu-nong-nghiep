<?php

namespace App\Support;

use Closure;
use Illuminate\Validation\ValidationException;

class DecimalLimit
{
    public static function rule(int $wholeDigits, int $fractionDigits): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail) use ($wholeDigits, $fractionDigits): void {
            if (! self::fits($value, $wholeDigits, $fractionDigits)) {
                $fail('Giá trị vượt độ rộng số thập phân cho phép.');
            }
        };
    }

    public static function assertFits(mixed $value, int $wholeDigits, int $fractionDigits, string $field): void
    {
        if (! self::fits($value, $wholeDigits, $fractionDigits)) {
            throw ValidationException::withMessages([$field => 'Giá trị vượt độ rộng số thập phân cho phép.']);
        }
    }

    private static function fits(mixed $value, int $wholeDigits, int $fractionDigits): bool
    {
        if (! is_string($value) && ! is_int($value) && ! is_float($value) && ! $value instanceof \Stringable) return false;
        $text = (string) $value;
        $pattern = '/^-?\d{1,'.$wholeDigits.'}(?:\.\d{1,'.$fractionDigits.'})?$/D';

        return preg_match($pattern, $text) === 1;
    }
}
