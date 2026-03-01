import Papa from 'papaparse';

export async function readCsvHeaders(file: File, maxBytes = 256_000): Promise<string[]> {
  const slice = file.slice(0, maxBytes);
  const text = await slice.text();

  const parsed = Papa.parse(text, {
    header: true,
    skipEmptyLines: true,
    dynamicTyping: false
  });

  const fields = (parsed.meta.fields ?? []).map((f) => (f ?? '').trim()).filter(Boolean);
  return Array.from(new Set(fields));
}
