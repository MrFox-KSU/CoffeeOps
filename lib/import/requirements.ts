import type { ImportEntityType } from '@/lib/import/detect';

export type FieldType = 'string' | 'date' | 'number' | 'boolean';

export type FieldRequirement = {
  key: string;
  label: string;
  type: FieldType;
  required: boolean;
  description?: string;
};

/**
 * Frontend requirement definitions.
 *
 * IMPORTANT: These keys must match the canonical CSV template headers in /public/templates.
 * The backend Edge Function also enforces a contract from DB via public.get_import_contract().
 */
export const ENTITY_REQUIREMENTS: Record<ImportEntityType, FieldRequirement[]> = {
  sales: [
    { key: 'invoice_date', label: 'Invoice date', type: 'date', required: true },
    { key: 'external_invoice_number', label: 'Invoice number', type: 'string', required: true },
    { key: 'branch_code', label: 'Branch code', type: 'string', required: false },
    { key: 'invoice_type', label: 'Invoice type', type: 'string', required: false },
    { key: 'channel', label: 'Channel', type: 'string', required: false },
    { key: 'payment_method', label: 'Payment method', type: 'string', required: false },
    { key: 'line_number', label: 'Line number', type: 'number', required: false },
    { key: 'sku', label: 'SKU', type: 'string', required: false },
    { key: 'product_name', label: 'Product name', type: 'string', required: true },
    { key: 'category', label: 'Category', type: 'string', required: false },
    { key: 'quantity', label: 'Quantity', type: 'number', required: true },
    { key: 'unit_price', label: 'Unit price', type: 'number', required: false },
    { key: 'discount_rate', label: 'Discount rate', type: 'number', required: false },
    {
      key: 'net_sales',
      label: 'Net sales',
      type: 'number',
      required: true,
      description: 'Net sales for the line (after discounts, before/after tax depending on export).'
    },
    { key: 'vat_rate', label: 'VAT rate', type: 'number', required: false },
    { key: 'tax_amount', label: 'Tax amount', type: 'number', required: false },
    { key: 'total_amount', label: 'Total amount', type: 'number', required: false },
    { key: 'currency', label: 'Currency', type: 'string', required: false }
  ],

  products: [
    { key: 'sku', label: 'SKU', type: 'string', required: true },
    { key: 'product_name', label: 'Product name', type: 'string', required: true },
    { key: 'category', label: 'Category', type: 'string', required: false },
    { key: 'default_price', label: 'Default price', type: 'number', required: false },
    { key: 'unit_cost', label: 'Unit cost', type: 'number', required: false },
    { key: 'currency', label: 'Currency', type: 'string', required: false },
    { key: 'active', label: 'Active', type: 'boolean', required: false }
  ],

  expenses: [
    { key: 'expense_date', label: 'Expense date', type: 'date', required: true },
    { key: 'reference_number', label: 'Reference #', type: 'string', required: false },
    { key: 'vendor', label: 'Vendor', type: 'string', required: false },
    { key: 'branch_code', label: 'Branch code', type: 'string', required: false },
    { key: 'cost_center_code', label: 'Cost center code', type: 'string', required: false },
    { key: 'category', label: 'Category', type: 'string', required: true },
    { key: 'amount', label: 'Amount', type: 'number', required: true },
    { key: 'vat_rate', label: 'VAT rate', type: 'number', required: false },
    { key: 'tax_amount', label: 'Tax amount', type: 'number', required: false },
    { key: 'total_amount', label: 'Total amount', type: 'number', required: false },
    { key: 'payment_method', label: 'Payment method', type: 'string', required: false },
    { key: 'notes', label: 'Notes', type: 'string', required: false },
    { key: 'currency', label: 'Currency', type: 'string', required: false }
  ],

  labor: [
    { key: 'work_date', label: 'Work date', type: 'date', required: true },
    { key: 'employee_id', label: 'Employee ID', type: 'string', required: false },
    { key: 'employee_name', label: 'Employee name', type: 'string', required: false },
    { key: 'role', label: 'Role', type: 'string', required: false },
    { key: 'branch_code', label: 'Branch code', type: 'string', required: false },
    { key: 'hours', label: 'Hours', type: 'number', required: true },
    { key: 'hourly_rate', label: 'Hourly rate', type: 'number', required: false },
    { key: 'cost', label: 'Cost', type: 'number', required: true },
    { key: 'currency', label: 'Currency', type: 'string', required: false }
  ],

  unknown: []
};
