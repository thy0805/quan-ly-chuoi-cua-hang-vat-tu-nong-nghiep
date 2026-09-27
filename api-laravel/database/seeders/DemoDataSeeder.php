<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use RuntimeException;

class DemoDataSeeder extends Seeder
{
    public function run(): void
    {
        if (DB::connection()->getDatabaseName() !== 'klcn186_dev') {
            throw new RuntimeException('Dữ liệu mẫu chỉ được tạo trong klcn186_dev.');
        }

        DB::transaction(function (): void {
            $this->call(DatabaseSeeder::class);

            $chainId = DB::table('chains')->where('name', 'Chuỗi dữ liệu mẫu')->value('id')
                ?? DB::table('chains')->insertGetId(['name' => 'Chuỗi dữ liệu mẫu']);

            $branchId = DB::table('branches')->where('chain_id', $chainId)->where('code', 'DEMO')->value('id')
                ?? DB::table('branches')->insertGetId([
                    'chain_id' => $chainId,
                    'code' => 'DEMO',
                    'name' => 'Chi nhánh mẫu',
                ]);

            $warehouseId = DB::table('warehouses')->where('branch_id', $branchId)->where('code', 'DEMO')->value('id')
                ?? DB::table('warehouses')->insertGetId([
                    'branch_id' => $branchId,
                    'code' => 'DEMO',
                    'name' => 'Kho bán hàng mẫu',
                    'warehouse_type' => 'sales',
                ]);

            DB::table('branches')->where('id', $branchId)->update([
                'default_sales_warehouse_id' => $warehouseId,
                'is_active' => true,
            ]);

            $categoryId = DB::table('product_categories')->where('code', 'DEMO-CATEGORY')->value('id')
                ?? DB::table('product_categories')->insertGetId([
                    'code' => 'DEMO-CATEGORY',
                    'name' => 'Nhóm vật tư mẫu',
                ]);

            $unitId = DB::table('units')->where('code', 'DEMO-UNIT')->value('id')
                ?? DB::table('units')->insertGetId([
                    'code' => 'DEMO-UNIT',
                    'name' => 'Gói',
                ]);

            $productId = DB::table('products')->where('code', 'DEMO-PRODUCT')->value('id')
                ?? DB::table('products')->insertGetId([
                    'category_id' => $categoryId,
                    'unit_id' => $unitId,
                    'code' => 'DEMO-PRODUCT',
                    'name' => 'Vật tư kiểm thử',
                    'sale_price' => 25000,
                ]);

            $lotId = DB::table('product_lots')->where('product_id', $productId)->where('lot_no', 'DEMO-LOT')->value('id')
                ?? DB::table('product_lots')->insertGetId([
                    'product_id' => $productId,
                    'lot_no' => 'DEMO-LOT',
                    'expires_on' => now()->addDays(20)->toDateString(),
                ]);

            DB::table('inventories')->updateOrInsert(
                ['warehouse_id' => $warehouseId, 'lot_id' => $lotId],
                ['quantity' => 25],
            );
        });
    }
}
