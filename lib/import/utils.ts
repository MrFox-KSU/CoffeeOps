export function sanitizeFilename(filename: string) {
  const cleaned = filename
    .trim()
    .replace(/[^a-zA-Z0-9._-]+/g, '_')
    .replace(/_+/g, '_');

  // Avoid empty names.
  if (!cleaned) return 'upload.csv';

  // Keep it reasonably short for URLs/logs.
  if (cleaned.length > 120) {
    const parts = cleaned.split('.');
    const ext = parts.length > 1 ? parts.pop() : undefined;
    const base = parts.join('.');
    const shortBase = base.slice(0, 100);
    return ext ? `${shortBase}.${ext}` : shortBase;
  }

  return cleaned;
}
