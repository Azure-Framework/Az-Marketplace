-- az_marketplace INSTALL (updated)
-- If you already have tables, the resource will auto-migrate older schemas on start.

CREATE TABLE IF NOT EXISTS az_marketplace_listings (
  id INT AUTO_INCREMENT PRIMARY KEY,
  listing_type VARCHAR(16) NOT NULL DEFAULT 'item',
  category VARCHAR(32) NOT NULL DEFAULT 'classifieds',
  title VARCHAR(64) NOT NULL,
  price INT NOT NULL DEFAULT 0,
  currency VARCHAR(8) NOT NULL DEFAULT '$',
  `condition` VARCHAR(32) NOT NULL DEFAULT 'Used - Good',
  description VARCHAR(800) DEFAULT NULL,
  images LONGTEXT DEFAULT NULL,
  location_x DOUBLE NOT NULL DEFAULT 0,
  location_y DOUBLE NOT NULL DEFAULT 0,
  location_z DOUBLE NOT NULL DEFAULT 0,
  location_label VARCHAR(64) NOT NULL DEFAULT '',
  seller_discord VARCHAR(64) NOT NULL,
  seller_charid VARCHAR(64) DEFAULT NULL,
  seller_name VARCHAR(100) DEFAULT NULL,
  source_ref VARCHAR(64) DEFAULT NULL,
  source_json LONGTEXT DEFAULT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_status (status),
  KEY idx_category (category),
  KEY idx_listing_type (listing_type),
  KEY idx_seller (seller_discord)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS az_marketplace_messages (
  id INT AUTO_INCREMENT PRIMARY KEY,
  listing_id INT NOT NULL,
  seller_discord VARCHAR(64) NOT NULL,
  buyer_discord VARCHAR(64) NOT NULL,
  sender_discord VARCHAR(64) NOT NULL,
  message VARCHAR(1000) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_listing (listing_id),
  KEY idx_pair (seller_discord, buyer_discord),
  KEY idx_sender (sender_discord)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
