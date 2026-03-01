export type ImportEntityType = 'sales' | 'expenses' | 'products' | 'labor' | 'unknown';

export type Detection = {
  entity: ImportEntityType;
  score: number;
  signals: string[];
  confidence: 'low' | 'medium' | 'high';
};

function norm(h: string) {
  return h.trim().toLowerCase();
}

function countAny(headers: string[], needles: string[]) {
  const set = new Set(headers.map(norm));
  return needles.reduce((acc, n) => acc + (set.has(norm(n)) ? 1 : 0), 0);
}

/**
 * Lightweight CSV entity detection.
 *
 * IMPORTANT: Signals should align with canonical template headers under /public/templates.
 */
export function detectEntity(headers: string[]): Detection {
  const h = headers.map(norm);

  // SALES signals (sales_lines_template.csv)
  const scoreSales =
    countAny(h, ['invoice_date']) * 3 +
    countAny(h, ['external_invoice_number', 'invoice_number', 'invoice']) * 3 +
    countAny(h, ['net_sales', 'total_amount', 'line_total']) * 3 +
    countAny(h, ['product_name', 'sku']) * 2 +
    countAny(h, ['quantity', 'unit_price']) * 2 +
    countAny(h, ['payment_method', 'channel']) * 1;

  // EXPENSES signals (expenses_template.csv)
  const scoreExpenses =
    countAny(h, ['expense_date']) * 3 +
    countAny(h, ['amount', 'total_amount']) * 3 +
    countAny(h, ['vendor', 'category']) * 2 +
    countAny(h, ['payment_method']) * 1;

  // PRODUCTS signals (products_template.csv)
  const scoreProducts =
    countAny(h, ['sku']) * 3 +
    countAny(h, ['product_name', 'name', 'product']) * 3 +
    countAny(h, ['unit_cost', 'default_price']) * 2 +
    countAny(h, ['category']) * 1;

  // LABOR signals (labor_template.csv)
  const scoreLabor =
    countAny(h, ['work_date']) * 3 +
    countAny(h, ['hours']) * 3 +
    countAny(h, ['cost']) * 3 +
    countAny(h, ['employee_id', 'employee_name', 'role']) * 1;

  const candidates = [
    { entity: 'sales' as const, score: scoreSales, signals: ['invoice_date', 'external_invoice_number', 'net_sales', 'product_name'] },
    { entity: 'expenses' as const, score: scoreExpenses, signals: ['expense_date', 'amount', 'category'] },
    { entity: 'products' as const, score: scoreProducts, signals: ['sku', 'product_name', 'unit_cost'] },
    { entity: 'labor' as const, score: scoreLabor, signals: ['work_date', 'hours', 'cost'] },
  ];

  candidates.sort((a, b) => b.score - a.score);
  const best = candidates[0];

  const confidence: Detection['confidence'] =
    best.score >= 10 ? 'high' :
    best.score >= 6 ? 'medium' :
    best.score >= 3 ? 'low' : 'low';

  if (best.score < 3) {
    return { entity: 'unknown', score: best.score, signals: [], confidence: 'low' };
  }

  return { entity: best.entity, score: best.score, signals: best.signals, confidence };
}
