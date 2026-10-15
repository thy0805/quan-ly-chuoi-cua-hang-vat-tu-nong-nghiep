<?php

namespace Tests\Feature;

use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

trait MobileSalesFixture
{
    private function createSalesSchema(): void
    {
        Schema::create('users', function (Blueprint $table): void {
            $table->id();
            $table->string('username');
            $table->text('password_hash');
            $table->boolean('is_active');
            $table->boolean('is_catalog_admin')->default(false);
        });
        Schema::create('chains', function (Blueprint $table): void {
            $table->id();
            $table->string('name');
            $table->boolean('is_active')->default(true);
        });
        Schema::create('branches', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('chain_id');
            $table->string('code');
            $table->string('name');
            $table->string('address')->nullable();
            $table->unsignedBigInteger('default_sales_warehouse_id')->nullable();
            $table->boolean('is_active')->default(true);
        });
        Schema::create('warehouses', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('branch_id');
            $table->string('name');
            $table->string('code')->nullable();
            $table->string('warehouse_type')->nullable();
        });
        Schema::create('roles', function (Blueprint $table): void {
            $table->id();
            $table->string('code');
            $table->string('name');
        });
        Schema::create('user_role_assignments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id');
            $table->foreignId('role_id');
            $table->foreignId('branch_id')->nullable();
            $table->date('starts_on');
            $table->string('status');
        });
        Schema::create('customers', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('chain_id');
            $table->string('name');
            $table->string('customer_type');
            $table->string('phone')->nullable();
            $table->text('address')->nullable();
        });
        Schema::create('units', function (Blueprint $table): void {
            $table->id();
            $table->string('name');
            $table->boolean('is_active')->default(true);
        });
        Schema::create('product_categories', function (Blueprint $table): void {
            $table->id();
            $table->string('code');
            $table->string('name');
            $table->boolean('is_active')->default(true);
        });
        Schema::create('products', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('category_id');
            $table->foreignId('unit_id');
            $table->string('code');
            $table->string('name');
            $table->decimal('sale_price', 18, 2)->default(0);
            $table->decimal('tax_rate', 5, 2)->nullable();
            $table->integer('expiry_warning_days')->nullable();
            $table->boolean('is_active')->default(true);
        });
        Schema::create('product_lots', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('product_id');
            $table->string('lot_no');
            $table->date('manufactured_on')->nullable();
            $table->date('expires_on')->nullable();
        });
        Schema::create('inventories', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('warehouse_id');
            $table->foreignId('lot_id');
            $table->decimal('quantity', 18, 3);
            $table->decimal('average_unit_cost', 18, 6)->nullable();
            $table->timestamp('updated_at')->nullable();
        });
        Schema::create('stock_movements', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('warehouse_id');
            $table->foreignId('lot_id');
            $table->foreignId('purchase_receipt_id')->nullable();
            $table->foreignId('sales_order_id')->nullable();
            $table->foreignId('stock_transfer_id')->nullable();
            $table->string('movement_type');
            $table->decimal('quantity_delta', 18, 3);
            $table->timestamp('occurred_at')->nullable();
        });
        Schema::create('sales_orders', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('branch_id');
            $table->foreignId('warehouse_id');
            $table->foreignId('customer_id')->nullable();
            $table->string('season_label')->nullable();
            $table->foreignId('created_by');
            $table->string('order_no');
            $table->string('status');
            $table->decimal('total_amount', 18, 2);
            $table->timestamp('sold_at')->nullable();
        });
        Schema::create('sales_order_items', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('order_id');
            $table->foreignId('lot_id');
            $table->decimal('quantity', 18, 3);
            $table->decimal('unit_price', 18, 2);
            $table->decimal('discount_amount', 18, 2);
            $table->decimal('line_total', 18, 2);
            $table->decimal('tax_rate_snapshot', 5, 2)->nullable();
            $table->decimal('tax_amount', 18, 2)->nullable();
            $table->decimal('unit_cost_snapshot', 18, 6)->nullable();
            $table->decimal('cost_total', 18, 2)->nullable();
        });
        Schema::create('invoices', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('sales_order_id');
            $table->string('invoice_no');
            $table->timestamp('issued_at')->nullable();
            $table->decimal('subtotal', 18, 2);
            $table->decimal('discount_amount', 18, 2);
            $table->decimal('tax_amount', 18, 2);
            $table->decimal('total_amount', 18, 2);
            $table->string('status');
        });
        Schema::create('debts', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('customer_id')->nullable()->unique();
            $table->foreignId('supplier_id')->nullable()->unique();
            $table->string('debt_type');
            $table->decimal('opening_balance', 18, 2)->default(0);
            $table->string('status');
        });
        Schema::create('payments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('invoice_id')->nullable();
            $table->foreignId('purchase_receipt_id')->nullable();
            $table->foreignId('created_by')->nullable();
            $table->string('method');
            $table->decimal('amount', 18, 2);
            $table->timestamp('paid_at')->nullable();
            $table->string('status');
            $table->string('request_key')->nullable()->unique();
            $table->string('reference_note')->nullable();
        });
        Schema::create('debt_transactions', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('debt_id');
            $table->foreignId('payment_id')->nullable()->unique();
            $table->foreignId('invoice_id')->nullable();
            $table->foreignId('purchase_receipt_id')->nullable();
            $table->foreignId('branch_id');
            $table->foreignId('warehouse_id');
            $table->foreignId('created_by');
            $table->string('transaction_type');
            $table->decimal('amount', 18, 2);
            $table->timestamp('occurred_at')->nullable();
            $table->string('season_label')->nullable();
        });
        Schema::create('outbox_events', function (Blueprint $table): void {
            $table->id();
            $table->string('aggregate_type');
            $table->unsignedBigInteger('aggregate_id');
            $table->string('event_type');
            $table->integer('event_version')->default(1);
            $table->text('payload');
            $table->string('status')->default('pending');
            $table->integer('attempt_count')->default(0);
            $table->timestamp('next_attempt_at')->nullable();
            $table->timestamp('locked_at')->nullable();
            $table->text('last_error')->nullable();
            $table->timestamp('created_at')->nullable();
            $table->timestamp('published_at')->nullable();
        });
        Schema::create('personal_access_tokens', function (Blueprint $table): void {
            $table->id();
            $table->morphs('tokenable');
            $table->text('name');
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable()->index();
            $table->timestamps();
        });
    }
}
