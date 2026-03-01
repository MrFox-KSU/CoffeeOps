Synthetic demo dataset for 3 Star Coffee (2 years)

Date range: 2024-01-01 → 2025-12-31
Branches: 3SC-DTN, 3SC-MAL
Currency: SAR
VAT rate used in demo: 15%

FILES
1) products.csv
   Required columns (Iteration 3 validator): sku, name
   Included columns: sku, name, category, default_price, unit_cost, currency, active

2) sales_lines.csv
   Required columns (Iteration 3 validator): invoice_date, external_invoice_number, net_sales
   Included columns: branch_code, branch_name, invoice_type, channel, payment_method,
                     line_number, sku, product_name, category, quantity, unit_price,
                     discount_rate, vat_rate, tax_amount, total_amount, currency

3) expenses.csv
   Required columns (Iteration 3 validator): expense_date, amount, category
   Included columns: reference_number, vendor, branch_code, cost_center_code, tax_amount,
                     total_amount, payment_method, notes, currency

4) labor.csv
   Required columns (Iteration 3 validator): work_date, hours, cost
   Included columns: employee_id, employee_name, role, hourly_rate, branch_code, branch_name, currency

IMPORT ORDER (recommended)
A) products.csv   (entity: products)
B) sales_lines.csv (entity: sales)
C) expenses.csv   (entity: expenses)
D) labor.csv      (entity: labor)

NOTE
This is synthetic data for testing the Import Center + staging/validation pipeline (Iteration 3).
It is not intended as financial truth.
