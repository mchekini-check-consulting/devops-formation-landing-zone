#!/bin/bash
set -e
echo "Seeding databases..."
psql -v ON_ERROR_STOP=1 -U postgres <<-EOSQL
  SELECT 'CREATE DATABASE ecommerce' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ecommerce')\gexec
  SELECT 'CREATE DATABASE analytics'  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'analytics')\gexec
EOSQL

psql -v ON_ERROR_STOP=1 -U postgres -d ecommerce <<-EOSQL
  CREATE SCHEMA IF NOT EXISTS inventory;
  CREATE SCHEMA IF NOT EXISTS orders;

  CREATE TABLE IF NOT EXISTS inventory.categories (
    id serial PRIMARY KEY,
    name text NOT NULL UNIQUE,
    description text
  );

  CREATE TABLE IF NOT EXISTS inventory.products (
    id serial PRIMARY KEY,
    name text NOT NULL,
    price numeric NOT NULL CHECK (price > 0),
    stock int NOT NULL DEFAULT 0 CHECK (stock >= 0),
    category_id int REFERENCES inventory.categories(id) ON DELETE SET NULL,
    created_at timestamp DEFAULT now()
  );

  CREATE TABLE IF NOT EXISTS inventory.warehouses (
    id serial PRIMARY KEY,
    city text NOT NULL,
    capacity int NOT NULL CHECK (capacity > 0)
  );

  CREATE TABLE IF NOT EXISTS inventory.warehouse_stock (
    id serial PRIMARY KEY,
    warehouse_id int NOT NULL REFERENCES inventory.warehouses(id) ON DELETE CASCADE,
    product_id int NOT NULL REFERENCES inventory.products(id) ON DELETE CASCADE,
    quantity int NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    UNIQUE (warehouse_id, product_id)
  );

  CREATE TABLE IF NOT EXISTS orders.customers (
    id serial PRIMARY KEY,
    name text NOT NULL,
    email text NOT NULL UNIQUE,
    created_at timestamp DEFAULT now()
  );

  CREATE TABLE IF NOT EXISTS orders.orders (
    id serial PRIMARY KEY,
    customer_id int NOT NULL REFERENCES orders.customers(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')),
    total numeric NOT NULL DEFAULT 0 CHECK (total >= 0),
    created_at timestamp DEFAULT now(),
    updated_at timestamp DEFAULT now()
  );

  CREATE TABLE IF NOT EXISTS orders.order_items (
    id serial PRIMARY KEY,
    order_id int NOT NULL REFERENCES orders.orders(id) ON DELETE CASCADE,
    product_id int NOT NULL REFERENCES inventory.products(id) ON DELETE RESTRICT,
    quantity int NOT NULL CHECK (quantity > 0),
    unit_price numeric NOT NULL CHECK (unit_price > 0)
  );

  CREATE INDEX IF NOT EXISTS idx_products_category       ON inventory.products(category_id);
  CREATE INDEX IF NOT EXISTS idx_products_price          ON inventory.products(price);
  CREATE INDEX IF NOT EXISTS idx_warehouse_stock_product ON inventory.warehouse_stock(product_id);
  CREATE INDEX IF NOT EXISTS idx_orders_customer         ON orders.orders(customer_id);
  CREATE INDEX IF NOT EXISTS idx_orders_status           ON orders.orders(status);
  CREATE INDEX IF NOT EXISTS idx_orders_created          ON orders.orders(created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_order_items_order       ON orders.order_items(order_id);
  CREATE INDEX IF NOT EXISTS idx_order_items_product     ON orders.order_items(product_id);

  CREATE OR REPLACE VIEW orders.customer_summary AS
    SELECT c.id, c.name, c.email,
           COUNT(o.id) AS total_orders,
           COALESCE(SUM(o.total), 0) AS total_spent
    FROM orders.customers c
    LEFT JOIN orders.orders o ON o.customer_id = c.id
    GROUP BY c.id, c.name, c.email;

  CREATE OR REPLACE VIEW inventory.stock_overview AS
    SELECT w.city AS warehouse, p.name AS product, ws.quantity
    FROM inventory.warehouse_stock ws
    JOIN inventory.warehouses w ON w.id = ws.warehouse_id
    JOIN inventory.products p   ON p.id = ws.product_id;

  CREATE OR REPLACE FUNCTION orders.update_timestamp()
  RETURNS TRIGGER AS \$trigger\$
  BEGIN NEW.updated_at = now(); RETURN NEW; END;
  \$trigger\$ LANGUAGE plpgsql;

  DROP TRIGGER IF EXISTS trg_orders_updated ON orders.orders;
  CREATE TRIGGER trg_orders_updated
    BEFORE UPDATE ON orders.orders
    FOR EACH ROW EXECUTE FUNCTION orders.update_timestamp();

  CREATE OR REPLACE FUNCTION orders.recalc_order_total()
  RETURNS TRIGGER AS \$trigger\$
  BEGIN
    UPDATE orders.orders SET total = (
      SELECT COALESCE(SUM(quantity * unit_price), 0)
      FROM orders.order_items WHERE order_id = COALESCE(NEW.order_id, OLD.order_id)
    ) WHERE id = COALESCE(NEW.order_id, OLD.order_id);
    RETURN NEW;
  END;
  \$trigger\$ LANGUAGE plpgsql;

  DROP TRIGGER IF EXISTS trg_recalc_total ON orders.order_items;
  CREATE TRIGGER trg_recalc_total
    AFTER INSERT OR UPDATE OR DELETE ON orders.order_items
    FOR EACH ROW EXECUTE FUNCTION orders.recalc_order_total();

  INSERT INTO inventory.categories SELECT 1, 'Laptops',     'Ordinateurs portables' WHERE NOT EXISTS (SELECT FROM inventory.categories WHERE id = 1);
  INSERT INTO inventory.categories SELECT 2, 'Phones',      'Smartphones'           WHERE NOT EXISTS (SELECT FROM inventory.categories WHERE id = 2);
  INSERT INTO inventory.categories SELECT 3, 'Accessories', 'Accessoires audio'     WHERE NOT EXISTS (SELECT FROM inventory.categories WHERE id = 3);

  INSERT INTO inventory.products SELECT 1, 'MacBook Pro', 2499.99,  50, 1, now() WHERE NOT EXISTS (SELECT FROM inventory.products WHERE id = 1);
  INSERT INTO inventory.products SELECT 2, 'iPhone 15',    999.99, 200, 2, now() WHERE NOT EXISTS (SELECT FROM inventory.products WHERE id = 2);
  INSERT INTO inventory.products SELECT 3, 'AirPods Pro',  249.99, 500, 3, now() WHERE NOT EXISTS (SELECT FROM inventory.products WHERE id = 3);

  INSERT INTO inventory.warehouses SELECT 1, 'Paris', 10000 WHERE NOT EXISTS (SELECT FROM inventory.warehouses WHERE id = 1);
  INSERT INTO inventory.warehouses SELECT 2, 'Lyon',   5000 WHERE NOT EXISTS (SELECT FROM inventory.warehouses WHERE id = 2);

  INSERT INTO inventory.warehouse_stock SELECT 1, 1, 1,  30 WHERE NOT EXISTS (SELECT FROM inventory.warehouse_stock WHERE id = 1);
  INSERT INTO inventory.warehouse_stock SELECT 2, 1, 2, 100 WHERE NOT EXISTS (SELECT FROM inventory.warehouse_stock WHERE id = 2);
  INSERT INTO inventory.warehouse_stock SELECT 3, 2, 3, 300 WHERE NOT EXISTS (SELECT FROM inventory.warehouse_stock WHERE id = 3);
  INSERT INTO inventory.warehouse_stock SELECT 4, 2, 1,  20 WHERE NOT EXISTS (SELECT FROM inventory.warehouse_stock WHERE id = 4);

  INSERT INTO orders.customers SELECT 1, 'Alice Dupont',   'alice@example.com',   now() WHERE NOT EXISTS (SELECT FROM orders.customers WHERE id = 1);
  INSERT INTO orders.customers SELECT 2, 'Bob Martin',     'bob@example.com',     now() WHERE NOT EXISTS (SELECT FROM orders.customers WHERE id = 2);
  INSERT INTO orders.customers SELECT 3, 'Charlie Durand', 'charlie@example.com', now() WHERE NOT EXISTS (SELECT FROM orders.customers WHERE id = 3);

  INSERT INTO orders.orders SELECT 1, 1, 'shipped',   0, now(), now() WHERE NOT EXISTS (SELECT FROM orders.orders WHERE id = 1);
  INSERT INTO orders.orders SELECT 2, 2, 'pending',   0, now(), now() WHERE NOT EXISTS (SELECT FROM orders.orders WHERE id = 2);
  INSERT INTO orders.orders SELECT 3, 1, 'delivered', 0, now(), now() WHERE NOT EXISTS (SELECT FROM orders.orders WHERE id = 3);
  INSERT INTO orders.orders SELECT 4, 3, 'confirmed', 0, now(), now() WHERE NOT EXISTS (SELECT FROM orders.orders WHERE id = 4);

  INSERT INTO orders.order_items SELECT 1, 1, 1, 1, 2499.99 WHERE NOT EXISTS (SELECT FROM orders.order_items WHERE id = 1);
  INSERT INTO orders.order_items SELECT 2, 1, 3, 2,  249.99 WHERE NOT EXISTS (SELECT FROM orders.order_items WHERE id = 2);
  INSERT INTO orders.order_items SELECT 3, 2, 2, 1,  999.99 WHERE NOT EXISTS (SELECT FROM orders.order_items WHERE id = 3);
  INSERT INTO orders.order_items SELECT 4, 3, 3, 5,  249.99 WHERE NOT EXISTS (SELECT FROM orders.order_items WHERE id = 4);
  INSERT INTO orders.order_items SELECT 5, 4, 1, 2, 2499.99 WHERE NOT EXISTS (SELECT FROM orders.order_items WHERE id = 5);
EOSQL

psql -v ON_ERROR_STOP=1 -U postgres -d analytics <<-EOSQL
  CREATE SCHEMA IF NOT EXISTS metrics;
  CREATE SCHEMA IF NOT EXISTS reports;

  CREATE TABLE IF NOT EXISTS metrics.page_views (
    id serial PRIMARY KEY,
    page text NOT NULL,
    views int NOT NULL CHECK (views >= 0),
    day date NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_page_views_day  ON metrics.page_views(day DESC);
  CREATE INDEX IF NOT EXISTS idx_page_views_page ON metrics.page_views(page);

  CREATE TABLE IF NOT EXISTS metrics.events (
    id serial PRIMARY KEY,
    event_type text NOT NULL,
    count int NOT NULL CHECK (count >= 0),
    day date NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_events_day  ON metrics.events(day DESC);
  CREATE INDEX IF NOT EXISTS idx_events_type ON metrics.events(event_type);

  CREATE TABLE IF NOT EXISTS reports.daily_sales (
    id serial PRIMARY KEY,
    total numeric NOT NULL CHECK (total >= 0),
    orders_count int NOT NULL CHECK (orders_count >= 0),
    day date NOT NULL UNIQUE
  );

  CREATE TABLE IF NOT EXISTS reports.monthly_summary (
    id serial PRIMARY KEY,
    month text NOT NULL UNIQUE,
    revenue numeric NOT NULL CHECK (revenue >= 0),
    growth_pct numeric
  );

  CREATE OR REPLACE VIEW reports.daily_trend AS
    SELECT ds.day, ds.total, ds.orders_count,
           COALESCE(SUM(pv.views), 0) AS total_views,
           COALESCE(SUM(e.count), 0)  AS total_events
    FROM reports.daily_sales ds
    LEFT JOIN metrics.page_views pv ON pv.day = ds.day
    LEFT JOIN metrics.events e      ON e.day  = ds.day
    GROUP BY ds.day, ds.total, ds.orders_count;

  INSERT INTO metrics.page_views SELECT 1, '/home',     15000, '2026-05-30' WHERE NOT EXISTS (SELECT FROM metrics.page_views WHERE id = 1);
  INSERT INTO metrics.page_views SELECT 2, '/products',  8500, '2026-05-30' WHERE NOT EXISTS (SELECT FROM metrics.page_views WHERE id = 2);
  INSERT INTO metrics.page_views SELECT 3, '/checkout',  3200, '2026-05-30' WHERE NOT EXISTS (SELECT FROM metrics.page_views WHERE id = 3);
  INSERT INTO metrics.page_views SELECT 4, '/home',     16200, '2026-05-31' WHERE NOT EXISTS (SELECT FROM metrics.page_views WHERE id = 4);

  INSERT INTO metrics.events SELECT 1, 'add_to_cart', 4200, '2026-05-30' WHERE NOT EXISTS (SELECT FROM metrics.events WHERE id = 1);
  INSERT INTO metrics.events SELECT 2, 'purchase',    1100, '2026-05-30' WHERE NOT EXISTS (SELECT FROM metrics.events WHERE id = 2);
  INSERT INTO metrics.events SELECT 3, 'add_to_cart', 4800, '2026-05-31' WHERE NOT EXISTS (SELECT FROM metrics.events WHERE id = 3);

  INSERT INTO reports.daily_sales SELECT 1, 45230.50, 320, '2026-05-30' WHERE NOT EXISTS (SELECT FROM reports.daily_sales WHERE id = 1);
  INSERT INTO reports.daily_sales SELECT 2, 52100.00, 410, '2026-05-31' WHERE NOT EXISTS (SELECT FROM reports.daily_sales WHERE id = 2);

  INSERT INTO reports.monthly_summary SELECT 1, '2026-04', 1250000.00, 12.5 WHERE NOT EXISTS (SELECT FROM reports.monthly_summary WHERE id = 1);
  INSERT INTO reports.monthly_summary SELECT 2, '2026-05', 1450000.00, 16.0 WHERE NOT EXISTS (SELECT FROM reports.monthly_summary WHERE id = 2);
EOSQL
echo "Seeding complete"
