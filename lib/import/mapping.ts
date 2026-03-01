import type { FieldRequirement } from '@/lib/import/requirements';

// Synonyms/aliases used to auto-suggest column mappings.
// Canonical keys must match /public/templates/*.csv header rows.
const KEY_ALIASES: Record<string, string[]> = {
  // SALES
  invoice_date: ['date', 'invoice date', 'sale date', 'transaction date', 'posted date', 'timestamp'],
  external_invoice_number: ['invoice number', 'invoice', 'receipt', 'receipt number', 'order number', 'transaction id', 'check'],
  branch_code: ['branch', 'branch code', 'store', 'store code', 'location', 'outlet'],
  invoice_type: ['invoice type', 'type', 'sale type', 'document type'],
  channel: ['channel', 'sales channel', 'source', 'order source'],
  payment_method: ['payment method', 'tender', 'payment', 'tender type'],
  line_number: ['line', 'line number', 'line_no', 'row'],
  sku: ['sku', 'item sku', 'product sku', 'barcode', 'plu', 'item code'],
  product_name: ['product', 'product name', 'item', 'item name', 'menu item', 'description'],
  category: ['category', 'group', 'department', 'product category'],
  quantity: ['qty', 'quantity', 'count', 'units'],
  unit_price: ['unit price', 'price', 'unit_price', 'rate'],
  discount_rate: ['discount', 'discount rate', 'discount %', 'discount_pct'],
  net_sales: ['net sales', 'net', 'sales', 'line total', 'line_total', 'subtotal', 'amount'],
  vat_rate: ['vat', 'vat rate', 'tax rate', 'tax %'],
  tax_amount: ['tax', 'tax amount', 'vat amount'],
  total_amount: ['total', 'total amount', 'gross', 'gross sales', 'grand total'],
  currency: ['currency', 'ccy'],

  // PRODUCTS
  default_price: ['default price', 'price', 'menu price', 'list price'],
  unit_cost: ['unit cost', 'cost', 'cogs', 'unit_cost'],
  active: ['active', 'enabled', 'is_active'],

  // EXPENSES
  expense_date: ['date', 'expense date', 'transaction date', 'posted date'],
  reference_number: ['reference', 'reference number', 'ref', 'invoice', 'bill'],
  vendor: ['vendor', 'supplier', 'merchant'],
  cost_center_code: ['cost center', 'cost center code', 'cost_center', 'department'],
  notes: ['notes', 'memo', 'description'],

  // LABOR
  work_date: ['date', 'work date', 'shift date'],
  employee_id: ['employee id', 'emp id', 'staff id'],
  employee_name: ['employee name', 'staff name', 'name'],
  role: ['role', 'position', 'job'],
  hours: ['hours', 'hrs', 'worked hours'],
  hourly_rate: ['hourly rate', 'rate'],
  cost: ['cost', 'labor cost', 'wages'],
};

function norm(s: string) {
  return s.trim().toLowerCase();
}

export function suggestMapping(requirements: FieldRequirement[], headers: string[]): Record<string, string> {
  const mapping: Record<string, string> = {};
  const hdrNorm = headers.map((h) => ({ raw: h, norm: norm(h) }));

  for (const req of requirements) {
    const key = req.key;
    const aliases = KEY_ALIASES[key] ?? [];

    // 1) Exact match on canonical key
    const exact = hdrNorm.find((h) => h.norm === norm(key));
    if (exact) {
      mapping[key] = exact.raw;
      continue;
    }

    // 2) Exact compact match (invoice_date vs invoice date)
    const compactKey = norm(key).replace(/_/g, '');
    const compact = hdrNorm.find((h) => h.norm.replace(/\s+/g, '').replace(/_/g, '') === compactKey);
    if (compact) {
      mapping[key] = compact.raw;
      continue;
    }

    // 3) Alias match
    for (const a of aliases) {
      const aNorm = norm(a);
      const hit = hdrNorm.find((h) => h.norm === aNorm);
      if (hit) {
        mapping[key] = hit.raw;
        break;
      }

      const aCompact = aNorm.replace(/\s+/g, '').replace(/_/g, '');
      const hit2 = hdrNorm.find((h) => h.norm.replace(/\s+/g, '').replace(/_/g, '') === aCompact);
      if (hit2) {
        mapping[key] = hit2.raw;
        break;
      }
    }
  }

  return mapping;
}
