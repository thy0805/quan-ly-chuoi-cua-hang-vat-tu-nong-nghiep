<?php

namespace App\Support;

use MongoDB\BSON\UTCDateTime;
use MongoDB\Client;

class NotificationStore
{
    public function list(string $userId, array $branchIds, ?string $status): array
    {
        $scope = ['user_id' => $userId, 'branch_id' => ['$in' => $branchIds]];
        $filter = $scope;
        if ($status !== null) $filter['status'] = $status;
        $collection = $this->collection();
        $documents = $collection->find($filter, ['sort' => ['created_at' => -1], 'limit' => 50]);

        return [
            'data' => array_map(fn ($document) => $this->present($document), iterator_to_array($documents, false)),
            'unread_count' => $collection->countDocuments($scope + ['status' => 'unread']),
        ];
    }

    public function markRead(string $id, string $userId, array $branchIds): ?array
    {
        $filter = ['_id' => $id, 'user_id' => $userId, 'branch_id' => ['$in' => $branchIds]];
        $collection = $this->collection();
        $collection->updateOne($filter + ['status' => 'unread'], [
            '$set' => ['status' => 'read', 'read_at' => new UTCDateTime()],
        ]);
        $document = $collection->findOne($filter);

        return $document === null ? null : $this->present($document);
    }

    private function present(object $document): array
    {
        return [
            'id' => $document['_id'], 'event_id' => $document['event_id'],
            'incident_id' => $document['incident_id'], 'branch_id' => $document['branch_id'],
            'kind' => $document['kind'], 'status' => $document['status'],
            'message' => $document['message'],
            'created_at' => $document['created_at']->toDateTime()->format('c'),
            'read_at' => isset($document['read_at']) ? $document['read_at']->toDateTime()->format('c') : null,
            'resolved_at' => isset($document['resolved_at']) ? $document['resolved_at']->toDateTime()->format('c') : null,
        ];
    }

    private function collection(): \MongoDB\Collection
    {
        $client = new Client(config('mongodb.uri'), ['serverSelectionTimeoutMS' => 3000]);

        return $client->selectCollection(config('mongodb.database'), 'notifications');
    }
}
