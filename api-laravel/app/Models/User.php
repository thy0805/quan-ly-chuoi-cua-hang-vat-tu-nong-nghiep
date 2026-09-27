<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;

class User extends Authenticatable
{
    public $timestamps = false;

    protected $fillable = ['username', 'password_hash', 'is_active'];

    protected $hidden = ['password_hash'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean', 'is_catalog_admin' => 'boolean'];
    }

    public function getAuthPasswordName(): string
    {
        return 'password_hash';
    }
}
