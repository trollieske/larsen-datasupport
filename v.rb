require_relative 'db'
r = db.get_first_row("SELECT id,name,quantity_in_stock,sold_quantity FROM hardware_items WHERE name='Temp UX Test'")
puts "qty=#{r['quantity_in_stock']} sold=#{r['sold_quantity']} (#{r['name']})"
s = db.get_first_row("SELECT quantity FROM hardware_sales WHERE hardware_item_id=#{r['id']} ORDER BY id LIMIT 1")
puts "sale recorded qty=#{s['quantity']}"
