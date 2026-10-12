<?php

return [
    'token_ttl_days' => max(1, min(30, (int) env('MOBILE_TOKEN_TTL_DAYS', 7))),
];
