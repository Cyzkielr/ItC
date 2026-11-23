-- =====================================================
-- SEED DATA (DEVELOPMENT ONLY) - sari_sari_store
-- All products, prices, stock, and accounts below are
-- PLACEHOLDER sample data for testing. Replace with the
-- real store's data before deployment.
-- Dev password for all sample accounts: ChangeMe123!
-- =====================================================
USE sari_sari_store;

INSERT INTO users (email, password_hash, role) VALUES
 ('admin@example.test',    '$2b$10$kWz5UeY/n7OIVhmI5ZmXSuwzjnuLYkk9qbtdtW54jqY18OwZtnsca', 'admin'),
 ('cashier@example.test',  '$2b$10$kWz5UeY/n7OIVhmI5ZmXSuwzjnuLYkk9qbtdtW54jqY18OwZtnsca', 'cashier'),
 ('customer@example.test', '$2b$10$kWz5UeY/n7OIVhmI5ZmXSuwzjnuLYkk9qbtdtW54jqY18OwZtnsca', 'customer');

INSERT INTO customers (user_id, full_name, phone, email) VALUES
 (3, 'Sample Customer', '09000000000', 'customer@example.test');

INSERT INTO categories (category_name, description) VALUES
 ('Canned Goods', 'Sample category'),
 ('Beverages',    'Sample category'),
 ('Snacks',       'Sample category'),
 ('Household',    'Sample category');

INSERT INTO products (category_id, product_name, sku, description, selling_price) VALUES
 (1, 'Sample Sardines',      'SKU-0001', 'Placeholder item', 20.00),
 (1, 'Sample Corned Beef',   'SKU-0002', 'Placeholder item', 40.00),
 (2, 'Sample Soda 500ml',    'SKU-0003', 'Placeholder item', 25.00),
 (2, 'Sample Instant Coffee','SKU-0004', 'Placeholder item',  8.00),
 (3, 'Sample Chips',         'SKU-0005', 'Placeholder item', 12.00),
 (3, 'Sample Biscuits',      'SKU-0006', 'Placeholder item', 10.00),
 (4, 'Sample Laundry Soap',  'SKU-0007', 'Placeholder item', 15.00),
 (4, 'Sample Dish Soap',     'SKU-0008', 'Placeholder item', 18.00);

INSERT INTO inventory (product_id, quantity_on_hand, quantity_reserved) VALUES
 (1, 50, 0), (2, 30, 0), (3, 40, 0), (4, 100, 0),
 (5, 60, 0), (6, 5, 0),  (7, 25, 0), (8, 0, 0);

INSERT INTO stock_movements (product_id, performed_by, movement_type, quantity_delta, notes)
SELECT product_id, 1, 'restock', quantity_on_hand, 'Initial sample stock'
FROM inventory WHERE quantity_on_hand > 0;

INSERT INTO store_settings (setting_key, setting_value) VALUES
 ('store_name', NULL), ('address', NULL), ('phone', NULL),
 ('opening_hours', NULL), ('landmarks', NULL),
 ('low_stock_threshold', '10');
