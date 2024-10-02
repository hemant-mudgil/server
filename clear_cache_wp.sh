#!/bin/bash

# Navigate to WordPress root directory
cd /path/to/your/wordpress || exit

# Clear WP Cache (default cache mechanism)
echo "Flushing WordPress default cache..."
wp cache flush

# Clear Elementor Cache
echo "Flushing Elementor cache..."
wp elementor flush_cache
wp elementor regenerate-css

# Clear W3 Total Cache (if installed)
if wp plugin is-active w3-total-cache; then
    echo "Flushing W3 Total Cache..."
    wp w3-total-cache flush
fi

# Clear WP Rocket Cache (if installed)
if wp plugin is-active wp-rocket; then
    echo "Flushing WP Rocket cache..."
    wp rocket clean
fi

# Clear WP Super Cache (if installed)
if wp plugin is-active wp-super-cache; then
    echo "Flushing WP Super Cache..."
    wp cache flush
fi

# Clear LiteSpeed Cache (if installed)
if wp plugin is-active litespeed-cache; then
    echo "Flushing LiteSpeed Cache..."
    wp lscache-purge all
fi

# Clear Redis Cache (if Redis is used)
if wp redis status | grep -q "Status: Connected"; then
    echo "Flushing Redis object cache..."
    wp redis flush
fi

# Clear Opcache (if enabled)
if php -m | grep -q opcache; then
    echo "Flushing PHP Opcache..."
    php -r 'opcache_reset();'
fi

echo "All caches cleared."
