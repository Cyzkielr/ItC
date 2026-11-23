-- =====================================================
-- SARI-SARI STORE MANAGEMENT SYSTEM
-- Database: sari_sari_store
-- Target: MySQL 8.0.16+ / compatible MariaDB
-- Storage engine: InnoDB
-- Character set: utf8mb4
--
-- This file creates the database structure only.
-- It does not insert sample products or user accounts.
-- =====================================================

CREATE DATABASE IF NOT EXISTS sari_sari_store
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE sari_sari_store;


-- =====================================================
-- 1. USERS
-- Admin, cashier, and customer login accounts
-- =====================================================

CREATE TABLE users (
    user_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('admin', 'cashier', 'customer') NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;


-- =====================================================
-- 2. CUSTOMERS
-- Customer profile; user_id is NULL for profiles
-- that are not connected to a registered account.
-- Guest orders can also store contact details directly
-- in the orders table.
-- =====================================================

CREATE TABLE customers (
    customer_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED UNIQUE,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(30) NOT NULL,
    email VARCHAR(150),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_customers_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB;


-- =====================================================
-- 3. CATEGORIES
-- =====================================================

CREATE TABLE categories (
    category_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;


-- =====================================================
-- 4. PRODUCTS
-- =====================================================

CREATE TABLE products (
    product_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_id BIGINT UNSIGNED NOT NULL,
    product_name VARCHAR(150) NOT NULL,
    sku VARCHAR(60) NOT NULL UNIQUE,
    description TEXT,
    selling_price DECIMAL(10,2) NOT NULL,
    image_path VARCHAR(255),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT chk_product_price
        CHECK (selling_price >= 0),

    CONSTRAINT fk_products_category
        FOREIGN KEY (category_id)
        REFERENCES categories(category_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    INDEX idx_products_name (product_name),
    INDEX idx_products_category (category_id)
) ENGINE=InnoDB;


-- =====================================================
-- 5. INVENTORY
-- quantity_on_hand = physical stock currently held
-- quantity_reserved = stock held for online orders
-- available stock = on_hand - reserved
-- =====================================================

CREATE TABLE inventory (
    product_id BIGINT UNSIGNED PRIMARY KEY,
    quantity_on_hand INT UNSIGNED NOT NULL DEFAULT 0,
    quantity_reserved INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT chk_inventory_reserved
        CHECK (quantity_reserved <= quantity_on_hand),

    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB;


-- =====================================================
-- 6. ORDERS
-- Online pickup orders only.
-- customer_id is NULL for guest checkout.
-- Contact fields preserve the details used at checkout.
-- =====================================================

CREATE TABLE orders (
    order_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT UNSIGNED,
    order_number VARCHAR(40) NOT NULL UNIQUE,

    contact_name VARCHAR(150) NOT NULL,
    contact_phone VARCHAR(30) NOT NULL,
    contact_email VARCHAR(150),

    status ENUM(
        'pending',
        'confirmed',
        'preparing',
        'ready_for_pickup',
        'completed',
        'cancelled'
    ) NOT NULL DEFAULT 'pending',

    customer_notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    INDEX idx_orders_status (status),
    INDEX idx_orders_customer (customer_id),
    INDEX idx_orders_created (created_at)
) ENGINE=InnoDB;


-- =====================================================
-- 7. TRANSACTIONS
-- Records online and point-of-sale sales.
-- order_id is NULL for direct POS transactions.
-- =====================================================

CREATE TABLE transactions (
    transaction_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED UNIQUE,
    created_by BIGINT UNSIGNED,
    transaction_number VARCHAR(40) NOT NULL UNIQUE,

    channel ENUM('online', 'pos') NOT NULL,

    status ENUM(
        'pending',
        'completed',
        'cancelled',
        'refunded'
    ) NOT NULL DEFAULT 'pending',

    subtotal DECIMAL(12,2) NOT NULL,
    total_amount DECIMAL(12,2) NOT NULL,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,

    CONSTRAINT chk_transaction_amounts
        CHECK (
            subtotal >= 0
            AND total_amount >= 0
        ),

    CONSTRAINT fk_transactions_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_transactions_user
        FOREIGN KEY (created_by)
        REFERENCES users(user_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    INDEX idx_transactions_channel (channel),
    INDEX idx_transactions_status (status),
    INDEX idx_transactions_created (created_at)
) ENGINE=InnoDB;


-- =====================================================
-- 8. TRANSACTION ITEMS
-- Shared item records for online and POS transactions.
-- Product name and price are snapshots taken at sale time.
-- =====================================================

CREATE TABLE transaction_items (
    item_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    transaction_id BIGINT UNSIGNED NOT NULL,
    product_id BIGINT UNSIGNED NOT NULL,

    product_name_snapshot VARCHAR(150) NOT NULL,
    sku_snapshot VARCHAR(60),

    unit_price DECIMAL(10,2) NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    line_total DECIMAL(12,2) NOT NULL,

    CONSTRAINT chk_transaction_item_values
        CHECK (
            unit_price >= 0
            AND quantity > 0
            AND line_total >= 0
        ),

    CONSTRAINT fk_items_transaction
        FOREIGN KEY (transaction_id)
        REFERENCES transactions(transaction_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_items_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    INDEX idx_items_transaction (transaction_id),
    INDEX idx_items_product (product_id)
) ENGINE=InnoDB;


-- =====================================================
-- 9. INVENTORY RESERVATIONS
-- Records stock reserved for online orders.
-- One reservation row per product per order.
-- =====================================================

CREATE TABLE inventory_reservations (
    reservation_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    product_id BIGINT UNSIGNED NOT NULL,

    quantity INT UNSIGNED NOT NULL,

    status ENUM(
        'active',
        'consumed',
        'released'
    ) NOT NULL DEFAULT 'active',

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT chk_reservation_quantity
        CHECK (quantity > 0),

    CONSTRAINT fk_reservations_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_reservations_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    UNIQUE KEY uq_order_product (order_id, product_id),
    INDEX idx_reservation_status (status)
) ENGINE=InnoDB;


-- =====================================================
-- 10. PAYMENTS
-- Supports cash, GCash, and Maya.
-- Multiple attempts can be recorded for one transaction.
-- =====================================================

CREATE TABLE payments (
    payment_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    transaction_id BIGINT UNSIGNED NOT NULL,
    verified_by BIGINT UNSIGNED,

    method ENUM('cash', 'gcash', 'maya') NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    reference_number VARCHAR(100),

    status ENUM(
        'pending',
        'verified',
        'rejected',
        'refunded'
    ) NOT NULL DEFAULT 'pending',

    payment_notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    verified_at TIMESTAMP NULL,

    CONSTRAINT chk_payment_amount
        CHECK (amount > 0),

    CONSTRAINT fk_payments_transaction
        FOREIGN KEY (transaction_id)
        REFERENCES transactions(transaction_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_payments_verifier
        FOREIGN KEY (verified_by)
        REFERENCES users(user_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    UNIQUE KEY uq_payment_reference (method, reference_number),
    INDEX idx_payments_transaction (transaction_id),
    INDEX idx_payments_status (status)
) ENGINE=InnoDB;


-- =====================================================
-- 11. STOCK MOVEMENTS
-- Audit trail of physical and reserved stock changes.
-- quantity_delta affects quantity_on_hand.
-- reserved_delta affects quantity_reserved.
-- =====================================================

CREATE TABLE stock_movements (
    movement_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED NOT NULL,
    transaction_id BIGINT UNSIGNED,
    order_id BIGINT UNSIGNED,
    performed_by BIGINT UNSIGNED,

    movement_type ENUM(
        'restock',
        'pos_sale',
        'online_reserve',
        'online_release',
        'online_fulfillment',
        'adjustment',
        'return'
    ) NOT NULL,

    quantity_delta INT NOT NULL DEFAULT 0,
    reserved_delta INT NOT NULL DEFAULT 0,

    notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_movements_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_movements_transaction
        FOREIGN KEY (transaction_id)
        REFERENCES transactions(transaction_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    CONSTRAINT fk_movements_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    CONSTRAINT fk_movements_user
        FOREIGN KEY (performed_by)
        REFERENCES users(user_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    INDEX idx_movements_product (product_id),
    INDEX idx_movements_type (movement_type),
    INDEX idx_movements_created (created_at)
) ENGINE=InnoDB;


-- =====================================================
-- 12. ORDER STATUS HISTORY
-- Audit trail of online order status changes.
-- =====================================================

CREATE TABLE order_status_history (
    history_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    changed_by BIGINT UNSIGNED,

    old_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,

    notes TEXT,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_history_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_history_user
        FOREIGN KEY (changed_by)
        REFERENCES users(user_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    INDEX idx_history_order (order_id),
    INDEX idx_history_changed (changed_at)
) ENGINE=InnoDB;


-- =====================================================
-- 13. STORE SETTINGS
-- Configurable store information.
-- Example keys: store_name, address, phone, opening_hours.
-- =====================================================

CREATE TABLE store_settings (
    setting_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(100) NOT NULL UNIQUE,
    setting_value TEXT,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;


-- =====================================================
-- END OF INITIAL DATABASE SCHEMA
-- =====================================================
