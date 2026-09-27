<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

class OutboxService
{
    public function record(string $aggregateType, string $aggregateId, string $eventType, array $payload): void
    {
        if (DB::transactionLevel() === 0) throw new \LogicException('Outbox phải được ghi trong transaction nghiệp vụ.');
        DB::table('outbox_events')->insert([
            'aggregate_type' => $aggregateType,
            'aggregate_id' => $aggregateId,
            'event_type' => $eventType,
            'event_version' => 1,
            'payload' => json_encode($payload, JSON_THROW_ON_ERROR),
            'status' => 'pending',
        ]);
    }
}
