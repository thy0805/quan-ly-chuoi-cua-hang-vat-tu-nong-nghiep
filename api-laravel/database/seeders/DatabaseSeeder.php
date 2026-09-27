<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        foreach ([
            'chain_owner' => 'Chủ chuỗi',
            'branch_manager' => 'Quản lý chi nhánh',
            'sales_staff' => 'Nhân viên bán hàng',
        ] as $code => $name) {
            DB::table('roles')->updateOrInsert(['code' => $code], ['name' => $name]);
        }
    }
}
