Coffee BI Import Templates (Canonical Headers)

Use these templates when you want “zero mapping pain”.
If your CSV headers match these canonical headers exactly, the Import Center can auto-map 1:1 and validations will pass.

Files:
1) products_template.csv
   REQUIRED: sku, product_name
   Recommended: category, default_price, unit_cost, currency, active

2) sales_lines_template.csv
   REQUIRED: invoice_date, external_invoice_number, net_sales
   Recommended: branch_code, invoice_type, channel, payment_method, line_number, sku, product_name, category,
                quantity, unit_price, discount_rate, vat_rate, tax_amount, total_amount, currency

3) expenses_template.csv
   REQUIRED: expense_date, amount, category
   Recommended: reference_number, vendor, branch_code, cost_center_code, vat_rate, tax_amount, total_amount,
                payment_method, notes, currency

4) labor_template.csv
   REQUIRED: work_date, hours, cost
   Recommended: employee_id, employee_name, role, branch_code, hourly_rate, currency

Formatting rules (strict enough for reliable parsing):
- Dates: YYYY-MM-DD
- Numbers: use '.' decimal separator (no currency symbols)
- Booleans: TRUE/FALSE
- VAT: 0.15 for 15%
