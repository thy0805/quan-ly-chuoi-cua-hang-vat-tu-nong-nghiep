<?php

namespace App\Support;

use MongoDB\BSON\UTCDateTime;
use MongoDB\Client;

class ProductContentStore
{
    public function find(string $productId): ?array
    {
        $document = $this->collection()->findOne(['_id' => $productId]);

        return $document === null ? null : [
            'product_id' => $productId,
            'usage_instructions' => $document['usage_instructions'] ?? null,
            'additional_info' => $document['additional_info'] ?? null,
            'images' => array_values((array) ($document['images'] ?? [])),
            'updated_at' => $document['updated_at']->toDateTime()->format('c'),
        ];
    }

    public function save(string $productId, array $content): array
    {
        $document = [
            '_id' => $productId,
            'product_id' => $productId,
            'usage_instructions' => $content['usage_instructions'] ?? null,
            'additional_info' => $content['additional_info'] ?? null,
            'images' => array_values($content['images'] ?? []),
            'updated_at' => new UTCDateTime(),
        ];
        $this->collection()->replaceOne(['_id' => $productId], $document, ['upsert' => true]);

        return $this->find($productId);
    }

    private function collection(): \MongoDB\Collection
    {
        $client = new Client(config('mongodb.uri'), ['serverSelectionTimeoutMS' => 3000]);

        return $client->selectCollection(config('mongodb.database'), 'product_contents');
    }
}
