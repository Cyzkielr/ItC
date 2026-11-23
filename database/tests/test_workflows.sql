-- =====================================================
-- WORKFLOW TESTS (run after schema.sql + seed.sql)
-- Usage: mysql < database/tests/test_workflows.sql
-- Each test prints PASS/FAIL. Uses sample data from seed.sql.
-- Resets stock first so it can be re-run.
-- =====================================================
USE sari_sari_store;

DELETE FROM payments; DELETE FROM transaction_items;
DELETE FROM inventory_reservations; DELETE FROM order_status_history;
DELETE FROM stock_movements WHERE movement_type <> 'restock';
DELETE FROM transactions; DELETE FROM orders;
UPDATE inventory SET quantity_reserved = 0;
UPDATE inventory SET quantity_on_hand = 50 WHERE product_id = 1;
UPDATE inventory SET quantity_on_hand = 40 WHERE product_id = 3;

-- TEST 1: Online order reserves stock (product 1, qty 5) ---------
START TRANSACTION;
INSERT INTO orders (order_number, contact_name, contact_phone)
 VALUES ('ORD-TEST-1', 'Guest Buyer', '09000000001');
SET @oid = LAST_INSERT_ID();
SELECT quantity_on_hand - quantity_reserved INTO @avail
  FROM inventory WHERE product_id = 1 FOR UPDATE;
INSERT INTO inventory_reservations (order_id, product_id, quantity) VALUES (@oid, 1, 5);
UPDATE inventory SET quantity_reserved = quantity_reserved + 5 WHERE product_id = 1;
INSERT INTO stock_movements (product_id, order_id, movement_type, reserved_delta)
 VALUES (1, @oid, 'online_reserve', 5);
INSERT INTO order_status_history (order_id, old_status, new_status) VALUES (@oid, NULL, 'pending');
COMMIT;
SELECT IF(quantity_on_hand=50 AND quantity_reserved=5,'PASS','FAIL') AS `T1 reserve`
  FROM inventory WHERE product_id = 1;

-- TEST 2: Cancel releases reservation ---------------------------
START TRANSACTION;
UPDATE orders SET status='cancelled' WHERE order_id=@oid;
UPDATE inventory_reservations SET status='released' WHERE order_id=@oid;
UPDATE inventory SET quantity_reserved = quantity_reserved - 5 WHERE product_id = 1;
INSERT INTO stock_movements (product_id, order_id, movement_type, reserved_delta)
 VALUES (1, @oid, 'online_release', -5);
COMMIT;
SELECT IF(quantity_on_hand=50 AND quantity_reserved=0,'PASS','FAIL') AS `T2 release`
  FROM inventory WHERE product_id = 1;

-- TEST 3: Online pickup completion consumes reservation ---------
START TRANSACTION;
INSERT INTO orders (order_number, contact_name, contact_phone)
 VALUES ('ORD-TEST-3', 'Guest Buyer', '09000000002');
SET @oid3 = LAST_INSERT_ID();
INSERT INTO inventory_reservations (order_id, product_id, quantity) VALUES (@oid3, 1, 4);
UPDATE inventory SET quantity_reserved = quantity_reserved + 4 WHERE product_id = 1;
INSERT INTO transactions (order_id, transaction_number, channel, subtotal, total_amount)
 VALUES (@oid3, 'TXN-TEST-3', 'online', 80.00, 80.00);
SET @tid3 = LAST_INSERT_ID();
INSERT INTO transaction_items (transaction_id, product_id, product_name_snapshot, sku_snapshot, unit_price, quantity, line_total)
 SELECT @tid3, product_id, product_name, sku, selling_price, 4, selling_price*4 FROM products WHERE product_id=1;
INSERT INTO payments (transaction_id, method, amount, reference_number)
 VALUES (@tid3, 'gcash', 80.00, 'GC-TEST-0001');
COMMIT;
START TRANSACTION;
UPDATE payments SET status='verified', verified_by=2, verified_at=NOW() WHERE transaction_id=@tid3;
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 4, quantity_reserved = quantity_reserved - 4 WHERE product_id=1;
UPDATE inventory_reservations SET status='consumed' WHERE order_id=@oid3;
UPDATE orders SET status='completed' WHERE order_id=@oid3;
UPDATE transactions SET status='completed', completed_at=NOW() WHERE transaction_id=@tid3;
INSERT INTO stock_movements (product_id, transaction_id, order_id, movement_type, quantity_delta, reserved_delta)
 VALUES (1, @tid3, @oid3, 'online_fulfillment', -4, -4);
COMMIT;
SELECT IF(quantity_on_hand=46 AND quantity_reserved=0,'PASS','FAIL') AS `T3 pickup`
  FROM inventory WHERE product_id = 1;

-- TEST 4: POS sale deducts immediately (product 3 x2, cash) -----
START TRANSACTION;
SELECT quantity_on_hand - quantity_reserved INTO @a3 FROM inventory WHERE product_id=3 FOR UPDATE;
INSERT INTO transactions (created_by, transaction_number, channel, status, subtotal, total_amount, completed_at)
 VALUES (2, 'TXN-TEST-4', 'pos', 'completed', 50.00, 50.00, NOW());
SET @tid4 = LAST_INSERT_ID();
INSERT INTO transaction_items (transaction_id, product_id, product_name_snapshot, sku_snapshot, unit_price, quantity, line_total)
 SELECT @tid4, product_id, product_name, sku, selling_price, 2, selling_price*2 FROM products WHERE product_id=3;
INSERT INTO payments (transaction_id, method, amount, status, verified_by, verified_at)
 VALUES (@tid4, 'cash', 50.00, 'verified', 2, NOW());
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 2 WHERE product_id=3;
INSERT INTO stock_movements (product_id, transaction_id, performed_by, movement_type, quantity_delta)
 VALUES (3, @tid4, 2, 'pos_sale', -2);
COMMIT;
SELECT IF(quantity_on_hand=38,'PASS','FAIL') AS `T4 pos sale` FROM inventory WHERE product_id=3;

-- Helper: runs a statement that SHOULD fail; prints PASS if it errors.
DROP PROCEDURE IF EXISTS t_expect_fail;
DELIMITER $$
CREATE PROCEDURE t_expect_fail(IN test_name VARCHAR(60), IN stmt TEXT)
BEGIN
  DECLARE failed BOOLEAN DEFAULT FALSE;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION, SQLWARNING SET failed = TRUE;
  SET @sql = stmt;
  PREPARE s FROM @sql;
  EXECUTE s;
  DEALLOCATE PREPARE s;
  SELECT test_name AS test, IF(failed, 'PASS', 'FAIL') AS result;
END$$
DELIMITER ;

-- TEST 5: reserved cannot exceed on_hand (overselling guard)
CALL t_expect_fail('T5 reserved<=on_hand',
  'UPDATE inventory SET quantity_reserved = quantity_on_hand + 1 WHERE product_id = 6');
-- TEST 6: negative stock blocked (UNSIGNED)
CALL t_expect_fail('T6 no negative stock',
  'UPDATE inventory SET quantity_on_hand = quantity_on_hand - 999 WHERE product_id = 6');
-- TEST 7: product with sales history cannot be deleted
CALL t_expect_fail('T7 FK restrict on delete',
  'DELETE FROM products WHERE product_id = 3');
-- TEST 8: duplicate e-wallet reference rejected
CALL t_expect_fail('T8 duplicate reference',
  CONCAT('INSERT INTO payments (transaction_id, method, amount, reference_number) VALUES (', @tid3, ', ''gcash'', 80.00, ''GC-TEST-0001'')'));
-- TEST 9: bad enum value rejected
CALL t_expect_fail('T9 invalid payment method',
  CONCAT('INSERT INTO payments (transaction_id, method, amount) VALUES (', @tid4, ', ''paypal'', 10.00)'));
DROP PROCEDURE t_expect_fail;

-- REPORT QUERIES: must run without error ------------------------
SELECT channel, COUNT(*) txns, SUM(total_amount) sales
  FROM transactions WHERE status='completed' GROUP BY channel;
SELECT c.category_name, SUM(ti.line_total) sales
  FROM transaction_items ti
  JOIN products p ON p.product_id=ti.product_id
  JOIN categories c ON c.category_id=p.category_id
  JOIN transactions t ON t.transaction_id=ti.transaction_id AND t.status='completed'
  GROUP BY c.category_name;
SELECT p.product_name, i.quantity_on_hand, i.quantity_reserved,
       i.quantity_on_hand - i.quantity_reserved AS available
  FROM inventory i JOIN products p USING (product_id)
  WHERE i.quantity_on_hand - i.quantity_reserved
        <= CAST((SELECT setting_value FROM store_settings WHERE setting_key='low_stock_threshold') AS UNSIGNED);
